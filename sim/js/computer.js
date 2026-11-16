// One simulated computer: a Lua state (Fengari) running bios.lua, its
// event queue, its screen and peripherals. The `sim` table the bios
// calls is built here as C functions over the Simulation's world, file
// system and clock.

import { Terminal, monitorSize } from './terminal.js';

// Lua strings are byte arrays. Files and screens are treated as latin-1
// so the game's byte-valued glyphs survive the round trip.
export function bytesToString(bytes) {
  let out = '';
  for (let i = 0; i < bytes.length; i += 8192) {
    out += String.fromCharCode.apply(null, bytes.subarray(i, i + 8192));
  }
  return out;
}
export function stringToBytes(str) {
  const out = new Uint8Array(str.length);
  for (let i = 0; i < str.length; i++) out[i] = str.charCodeAt(i) & 0xff;
  return out;
}

export class Computer {
  constructor(simulation, def, fengari) {
    this.sim = simulation;
    this.fengari = fengari;
    this.id = def.id;
    this.label = def.label || null;
    this.kind = def.kind || 'computer';
    this.advanced = def.advanced !== false;
    this.autorun = def.autorun || '';
    this.def = def;
    this.queue = [];
    this.filter = null;
    this.state = 'off';
    this.error = null;
    this.timerId = 0;
    this.ticket = 0;
    this.pendingTimers = new Set();
    this.files = new Map(); // per computer writes on top of the shared repo files
    this.deleted = new Set();

    const size = this.kind === 'turtle' ? [39, 13] : this.kind === 'pocket' ? [26, 20] : [51, 19];
    this.terminal = new Terminal(`${this.kind} ${this.id}`, size[0], size[1], { color: this.advanced, kind: 'computer' });
    this.terminals = new Map([['native', this.terminal]]);
    this.peripherals = [];
    for (const [side, p] of Object.entries(def.peripherals || {})) this.addPeripheral(side, p);
  }

  // Attach a peripheral ({type: 'monitor', blocksW, blocksH, advanced,
  // blocks} or {type: 'modem'}) on a side or network name. A running
  // program gets a peripheral event, as in the game.
  addPeripheral(side, p) {
    const entry = { name: side, type: p.type, def: p };
    if (p.type === 'monitor') {
      const { width, height } = monitorSize(p.blocksW || 1, p.blocksH || 1, 1);
      const t = new Terminal(`monitor ${side} of ${this.id}`, width, height, {
        color: p.advanced !== false, kind: 'monitor', blocksW: p.blocksW || 1, blocksH: p.blocksH || 1, scale: 1,
      });
      t.onResize = () => this.pushEvent(['monitor_resize', side]);
      entry.terminal = t;
      this.terminals.set(side, t);
    }
    this.peripherals.push(entry);
    if (this.state === 'running') this.pushEvent(['peripheral', side]);
    return entry;
  }

  removePeripheral(side) {
    const i = this.peripherals.findIndex((p) => p.name === side);
    if (i < 0) return null;
    const [entry] = this.peripherals.splice(i, 1);
    this.terminals.delete(side);
    if (this.state === 'running') this.pushEvent(['peripheral_detach', side]);
    return entry;
  }

  get turtle() { return this.kind === 'turtle' ? this.sim.world.turtles.get(this.id) : null; }

  // Lua helpers

  _str(L, i) {
    const { lua } = this.fengari;
    if (lua.lua_type(L, i) === lua.LUA_TNIL || lua.lua_type(L, i) === lua.LUA_TNONE) return null;
    return bytesToString(lua.lua_tolstring(L, i));
  }
  _num(L, i) {
    const { lua } = this.fengari;
    return lua.lua_type(L, i) === lua.LUA_TNUMBER ? lua.lua_tonumber(L, i) : null;
  }
  _bool(L, i) { return this.fengari.lua.lua_toboolean(L, i); }

  // Push a JS value as a Lua value. Integral numbers become integers so
  // they print without a decimal point.
  push(L, v) {
    const { lua } = this.fengari;
    if (v === null || v === undefined) lua.lua_pushnil(L);
    else if (typeof v === 'boolean') lua.lua_pushboolean(L, v);
    else if (typeof v === 'number') { if (Number.isInteger(v)) lua.lua_pushinteger(L, v); else lua.lua_pushnumber(L, v); }
    else if (typeof v === 'string') lua.lua_pushstring(L, stringToBytes(v));
    else if (Array.isArray(v)) {
      lua.lua_createtable(L, v.length, 0);
      v.forEach((item, i) => { this.push(L, item); lua.lua_rawseti(L, -2, i + 1); });
    } else if (typeof v === 'object') {
      lua.lua_createtable(L, 0, Object.keys(v).length);
      for (const [k, item] of Object.entries(v)) {
        if (item === undefined) continue;
        this.push(L, item);
        lua.lua_setfield(L, -2, stringToBytes(k));
      }
    } else lua.lua_pushnil(L);
  }

  // Read a Lua value (number, string, boolean, nil) at a stack index.
  value(L, i) {
    const { lua } = this.fengari;
    switch (lua.lua_type(L, i)) {
      case lua.LUA_TNUMBER: return lua.lua_tonumber(L, i);
      case lua.LUA_TSTRING: return this._str(L, i);
      case lua.LUA_TBOOLEAN: return lua.lua_toboolean(L, i);
      default: return null;
    }
  }

  _term(L, i) {
    const name = this._str(L, i);
    const t = this.terminals.get(name);
    if (!t) throw new Error(`no terminal ${name}`);
    return t;
  }

  // The `sim` table of host functions the bios uses.
  _bridge() {
    const self = this;
    const { lua } = this.fengari;
    const multi = (values) => values; // marker: array means several return values
    const fns = {
      id: () => self.id,
      label: () => self.label,
      setLabel: (L) => { self.label = self._str(L, 1); self.sim.changed(); return null; },
      isTurtle: () => self.kind === 'turtle',
      autorun: () => self.autorun,
      clock: () => self.sim.clock,
      log: (L) => { self.sim.log({ computer: self.id, text: self._str(L, 1) }); return null; },
      startTimer: (L) => {
        const id = ++self.timerId;
        const delay = Math.max(0.05, self._num(L, 1) || 0);
        self.pendingTimers.add(id);
        self.sim.schedule(delay, () => { if (self.pendingTimers.delete(id)) self.pushEvent(['timer', id]); });
        return id;
      },
      cancelTimer: (L) => { self.pendingTimers.delete(self._num(L, 1)); return null; },
      shutdown: () => { self.sim.schedule(0, () => self.shutdown()); return null; },
      reboot: () => { self.sim.schedule(0, () => self.reboot()); return null; },
      // terminals
      termWrite: (L) => { self._term(L, 1).write(self._str(L, 2) || ''); return null; },
      termBlit: (L) => { self._term(L, 1).blit(self._str(L, 2), self._str(L, 3), self._str(L, 4)); return null; },
      termClear: (L) => { self._term(L, 1).clear(); return null; },
      termClearLine: (L) => { self._term(L, 1).clearLine(); return null; },
      termScroll: (L) => { self._term(L, 1).scroll(self._num(L, 2) || 0); return null; },
      termGetSize: (L) => multi(self._term(L, 1).getSize()),
      termSetCursor: (L) => { self._term(L, 1).setCursorPos(self._num(L, 2), self._num(L, 3)); return null; },
      termGetCursor: (L) => multi(self._term(L, 1).getCursorPos()),
      termSetBlink: (L) => { self._term(L, 1).setCursorBlink(self._bool(L, 2)); return null; },
      termGetBlink: (L) => self._term(L, 1).cursorBlink,
      termSetColors: (L) => {
        const t = self._term(L, 1);
        const f = self._num(L, 2), b = self._num(L, 3);
        if (f != null) t.setTextColor(f);
        if (b != null) t.setBackgroundColor(b);
        return null;
      },
      termGetColors: (L) => { const t = self._term(L, 1); return multi([t.getTextColor(), t.getBackgroundColor()]); },
      termIsColor: (L) => self._term(L, 1).isColor(),
      termGetLine: (L) => { const l = self._term(L, 1).getLine(self._num(L, 2)); return l ? multi(l) : null; },
      termSetTextScale: (L) => { self._term(L, 1).setTextScale(self._num(L, 2) || 1); return null; },
      termGetTextScale: (L) => self._term(L, 1).getTextScale(),
      // files
      fsRead: (L) => self.readFile(self._str(L, 1)),
      fsWrite: (L) => { self.writeFile(self._str(L, 1), self._str(L, 2) || ''); return null; },
      fsExists: (L) => self.exists(self._str(L, 1)),
      fsIsDir: (L) => self.isDir(self._str(L, 1)),
      fsList: (L) => self.list(self._str(L, 1)),
      fsMakeDir: (L) => { self.dirs.add(self._str(L, 1)); return null; },
      fsDelete: (L) => { self.deleteFile(self._str(L, 1)); return null; },
      fsMove: (L) => {
        const from = self._str(L, 1), to = self._str(L, 2);
        const data = self.readFile(from);
        if (data != null) { self.writeFile(to, data); self.deleteFile(from); }
        return null;
      },
      // peripherals and network
      peripherals: () => self.peripherals.map((p) => ({ name: p.name, type: p.type })),
      rednetSend: (L) => { self.sim.rednet(self.id, self._num(L, 1), self._str(L, 2), self._str(L, 3)); return null; },
      // redstone: a rising edge on a turtle's side fires machines there
      redstoneSet: (L) => {
        const side = self._str(L, 1);
        const on = !!self.value(L, 2);
        const was = !!self.redstone[side];
        self.redstone[side] = on;
        if (on && !was && self.kind === 'turtle') self.sim.world.redstonePulse(self.id, side);
        return null;
      },
      redstoneGet: (L) => !!self.redstone[self._str(L, 1)],
      // turtle
      turtleAction: (L) => {
        const ticket = ++self.ticket;
        const action = self._str(L, 1);
        const result = self.sim.world.turtleAction(self.id, action, self.value(L, 2));
        self.sim.schedule(self.sim.world.actionDelay, () => self.pushEvent(['turtle_response', ticket, result.ok, result.reason || null]));
        return ticket;
      },
      turtleQuery: (L) => {
        const r = self.sim.world.turtleQuery(self.id, self._str(L, 1), self.value(L, 2), self.value(L, 3));
        return Array.isArray(r) ? multi(r) : r;
      },
    };
    lua.lua_createtable(this.L, 0, Object.keys(fns).length);
    for (const [name, fn] of Object.entries(fns)) {
      lua.lua_pushcfunction(this.L, (L) => {
        let result;
        try {
          result = fn(L);
        } catch (e) {
          lua.lua_pushstring(L, stringToBytes(`sim.${name}: ${e && e.message ? e.message : e}`));
          return lua.lua_error(L);
        }
        if (result === undefined || result === null) { lua.lua_pushnil(L); return 1; }
        if (Array.isArray(result) && fn.length !== undefined && result.__multi !== false && ['termGetSize', 'termGetCursor', 'termGetColors', 'termGetLine', 'turtleQuery'].includes(name)) {
          result.forEach((v) => this.push(L, v));
          return result.length;
        }
        this.push(L, result);
        return 1;
      });
      lua.lua_setfield(this.L, -2, stringToBytes(name));
    }
    lua.lua_setglobal(this.L, stringToBytes('sim'));
  }

  // Virtual file system: the shared repo files plus this computer's own
  // writes and deletions.
  readFile(path) {
    if (this.deleted.has(path)) return null;
    if (this.files.has(path)) return this.files.get(path);
    const shared = this.sim.files.get(path);
    return shared === undefined ? null : shared;
  }
  writeFile(path, data) { this.files.set(path, data); this.deleted.delete(path); }
  deleteFile(path) {
    for (const p of [...this.files.keys()]) if (p === path || p.startsWith(path + '/')) this.files.delete(p);
    for (const p of this.sim.files.keys()) if (p === path || p.startsWith(path + '/')) this.deleted.add(p);
  }
  allPaths() {
    const paths = new Set();
    for (const p of this.sim.files.keys()) if (!this.deleted.has(p)) paths.add(p);
    for (const p of this.files.keys()) paths.add(p);
    return paths;
  }
  exists(path) {
    if (path === '') return true;
    if (this.readFile(path) != null) return true;
    return this.isDir(path);
  }
  isDir(path) {
    if (path === '') return true;
    if (this.dirs.has(path)) return true;
    for (const p of this.allPaths()) if (p.startsWith(path + '/')) return true;
    return false;
  }
  list(path) {
    const out = new Set();
    const prefix = path === '' ? '' : path + '/';
    for (const p of this.allPaths()) {
      if (p.startsWith(prefix)) out.add(p.slice(prefix.length).split('/')[0]);
    }
    for (const d of this.dirs) if (d.startsWith(prefix) && d !== path) out.add(d.slice(prefix.length).split('/')[0]);
    return [...out];
  }

  // Lifecycle

  boot() {
    const { lua, lauxlib, lualib } = this.fengari;
    this.redstone = {}; // side -> output on
    this.dirs = this.dirs || new Set();
    this.L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(this.L);
    this._bridge();
    this.thread = lua.lua_newthread(this.L);
    const src = stringToBytes(this.sim.biosSource);
    if (lauxlib.luaL_loadbuffer(this.thread, src, src.length, stringToBytes('=bios')) !== lua.LUA_OK) {
      this.error = 'bios failed to load: ' + this._str(this.thread, -1);
      this.state = 'error';
      return;
    }
    this.queue = [];
    this.filter = null;
    this.pendingTimers.clear();
    this.state = 'running';
    this.error = null;
    this.terminal.resize(this.terminal.width, this.terminal.height);
    this._resume([]);
  }

  shutdown() {
    this.state = 'off';
    this.L = null;
    this.thread = null;
    this.queue = [];
    this.terminal.textColor = 1; this.terminal.backColor = 32768;
    this.terminal.clear();
    this.sim.changed();
  }

  reboot() { this.shutdown(); this.boot(); }
  terminate() { this.pushEvent(['terminate']); }

  pushEvent(ev) {
    if (this.state !== 'running') return;
    this.queue.push(ev);
  }

  // Run the Lua thread until it waits for an event we do not have.
  step(budget = 200) {
    let did = false;
    while (this.state === 'running' && this.queue.length && budget-- > 0) {
      const ev = this.queue[0];
      if (this.filter === null || ev[0] === this.filter || ev[0] === 'terminate') {
        this.queue.shift();
        this._resume(ev);
        did = true;
      } else {
        this.queue.shift(); // the game drops events a filter does not want
      }
    }
    return did;
  }

  _resume(args) {
    const { lua } = this.fengari;
    const T = this.thread;
    for (const a of args) this.push(T, a);
    const status = lua.lua_resume(T, null, args.length);
    if (status === lua.LUA_YIELD) {
      const n = lua.lua_gettop(T);
      this.filter = n >= 1 && lua.lua_type(T, 1) === lua.LUA_TSTRING ? this._str(T, 1) : null;
      lua.lua_pop(T, n);
    } else if (status === lua.LUA_OK) {
      this.state = 'finished';
      this.terminal.write('Shell exited. Press reboot.');
    } else {
      this.error = this._str(T, -1);
      this.state = 'error';
      this.terminal.setTextColor(16384);
      this.terminal.write(`Error: ${this.error}`);
      this.sim.log({ computer: this.id, text: `crashed: ${this.error}`, level: 'error' });
    }
    this.sim.changed();
  }
}
