// One simulated computer: a Lua state (Fengari) running bios.lua, its
// event queue, its screen and peripherals. The `sim` table the bios
// calls is built here as C functions over the Simulation's world, file
// system and clock.

import { Terminal, monitorSize } from './terminal.js';
import { SIDES } from './world.js';
import { peripheralEntries, callEntry, methodNames, PeripheralError } from './peripherals.js';

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
    // A computer placed by a turtle starts with nothing on its disk
    // instead of the repo's files (emptyFs). A labelled computer that
    // was dug up brings its files back with it (files, dirs).
    this.emptyFs = !!def.emptyFs;
    if (def.files) for (const [p, d] of def.files instanceof Map ? def.files : Object.entries(def.files)) this.files.set(p, d);
    this.dirs = new Set(def.dirs || []);
    this.heading = def.heading || 0; // computers face north (front is +y) unless told otherwise
    this.modemChannels = new Map(); // modem peripheral name -> Set of open channels
    this.knownPeripherals = null;   // names at the last peripheral check
    this.device = null;             // redstone device in the world (see Simulation)
    this.redstone = {};             // side -> output level 0..15
    this.bundled = {};              // side -> bundled output mask

    const size = this.kind === 'turtle' ? [39, 13] : this.kind === 'pocket' ? [26, 20] : [51, 19];
    this.terminal = new Terminal(`${this.kind} ${this.id}`, size[0], size[1], { color: this.advanced, kind: 'computer' });
    this.terminals = new Map([['native', this.terminal]]);
    this.peripherals = [];
    for (const [side, p] of Object.entries(def.peripherals || {})) this.addPeripheral(side, p);
  }

  // Attach a peripheral ({type: 'monitor', blocksW, blocksH, advanced,
  // blocks}, {type: 'modem'} or {type: 'modem', wired: true, network})
  // on a side or network name. A running program gets a peripheral
  // event at the next peripheral check, as in the game.
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
    this.sim.devicesChanged();
    return entry;
  }

  removePeripheral(side) {
    const i = this.peripherals.findIndex((p) => p.name === side);
    if (i < 0) return null;
    const [entry] = this.peripherals.splice(i, 1);
    this.terminals.delete(side);
    this.sim.devicesChanged();
    return entry;
  }

  get turtle() { return this.kind === 'turtle' ? this.sim.world.turtles.get(this.id) : null; }

  // Where the computer is and which way it faces, or null for a pocket
  // computer (it is in a player's hand).
  position() {
    if (this.kind === 'turtle') {
      const t = this.sim.world.turtles.get(this.id);
      return t ? { x: t.x, y: t.y, z: t.z, heading: t.heading } : null;
    }
    if (this.kind === 'pocket' || !this.def.pos) return null;
    return { x: this.def.pos.x, y: this.def.pos.y, z: this.def.pos.z, heading: this.heading };
  }

  // Wired networks this computer's own modems are on.
  wiredNetworks() {
    return this.peripherals.filter((p) => p.type === 'modem' && p.def.wired).map((p) => p.def.network || 'default');
  }

  // The name other computers on a wired network see this one by.
  netName() { return `${this.kind === 'turtle' ? 'turtle' : 'computer'}_${this.id}`; }

  peripheralEntries() { return peripheralEntries(this.sim, this); }
  peripheralEntry(name) { return this.peripheralEntries().find((e) => e.name === name) || null; }
  hasModem() { return this.peripheralEntries().some((e) => e.kind === 'modem'); }

  // Floppies in attached drives, mounted at disk, disk2, ... in the order
  // peripheral.getNames lists the drives.
  mounts() {
    const out = [];
    for (const e of this.peripheralEntries()) {
      if (e.kind !== 'block' || e.block !== 'disk_drive') continue;
      const m = this.sim.world.getMeta(e.x, e.y, e.z);
      if (!m || !m.disk) continue;
      out.push({ path: out.length ? `disk${out.length + 1}` : 'disk', data: m.disk.data, entryName: e.name });
    }
    return out;
  }

  _mount(path) {
    for (const m of this.mounts()) {
      if (path === m.path) return { m, rel: '' };
      if (path.startsWith(m.path + '/')) return { m, rel: path.slice(m.path.length + 1) };
    }
    return null;
  }

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
    else if (v instanceof Map) {
      // integer keys stay integers: a sparse slot table like list() gives
      lua.lua_createtable(L, 0, v.size);
      for (const [k, item] of v) {
        this.push(L, k);
        this.push(L, item);
        lua.lua_settable(L, -3);
      }
    } else if (Array.isArray(v)) {
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
      isPocket: () => self.kind === 'pocket',
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
      fsMakeDir: (L) => {
        const path = self._str(L, 1);
        const mt = self._mount(path);
        if (mt) { if (mt.rel) mt.m.data.dirs.add(mt.rel); } else self.dirs.add(path);
        return null;
      },
      fsDrive: (L) => {
        const path = self._str(L, 1);
        if (!self.exists(path)) return null;
        if (self._mount(path)) return self._mount(path).m.path;
        return /^rom(\/|$)/.test(path) ? 'rom' : 'hdd';
      },
      fsDelete: (L) => { self.deleteFile(self._str(L, 1)); return null; },
      fsMove: (L) => {
        const from = self._str(L, 1), to = self._str(L, 2);
        const data = self.readFile(from);
        if (data != null) { self.writeFile(to, data); self.deleteFile(from); }
        return null;
      },
      // peripherals and network: periList gives { name, types } for
      // every peripheral; periCall returns true and the results, or
      // false and the error a program should see
      periList: () => self.peripheralEntries().map((e) => ({ name: e.name, types: e.types })),
      periMethods: (L) => { const e = self.peripheralEntry(self._str(L, 1)); return e ? methodNames(self.sim, self, e) : null; },
      periCall: (L) => {
        const name = self._str(L, 1), method = self._str(L, 2);
        const args = [];
        for (let i = 3; i <= lua.lua_gettop(L); i++) args.push(self.value(L, i));
        const e = self.peripheralEntry(name);
        if (!e) return multi([false, `No peripheral attached to '${name}'`]);
        try {
          return multi([true, ...callEntry(self.sim, self, e, method, args)]);
        } catch (err) {
          if (err instanceof PeripheralError) return multi([false, err.message]);
          throw err;
        }
      },
      rednetSend: (L) => { self.sim.rednet(self.id, self._num(L, 1), self._str(L, 2), self._str(L, 3)); return null; },
      // redstone: outputs reach the world at once, so a pulse set on and
      // off in one go still fires a machine; levels are 0..15
      redstoneSet: (L) => {
        const side = self._str(L, 1);
        const level = Math.max(0, Math.min(15, Math.floor(self._num(L, 2) || 0)));
        const was = self.redstone[side] || 0;
        self.redstone[side] = level;
        if (level === was) return null;
        if (level > 0 && !was && self.kind === 'turtle') self.sim.world.redstonePulse(self.id, side);
        else self.sim.world.updateRedstone();
        return null;
      },
      redstoneGet: (L) => self.redstone[self._str(L, 1)] || 0,
      redstoneInput: (L) => (self.device ? self.device.in[self._str(L, 1)] || 0 : 0),
      bundledSet: (L) => {
        const side = self._str(L, 1);
        const mask = Math.max(0, Math.min(65535, Math.floor(self._num(L, 2) || 0)));
        if ((self.bundled[side] || 0) === mask) return null;
        self.bundled[side] = mask;
        self.sim.world.updateRedstone();
        return null;
      },
      bundledGet: (L) => self.bundled[self._str(L, 1)] || 0,
      bundledInput: (L) => (self.device ? self.device.bundledIn[self._str(L, 1)] || 0 : 0),
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
        if (Array.isArray(result) && fn.length !== undefined && result.__multi !== false && ['termGetSize', 'termGetCursor', 'termGetColors', 'termGetLine', 'turtleQuery', 'periCall'].includes(name)) {
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
  // A floppy in a drive is mounted at disk/ (disk2/ ...) and its files
  // live with the disk item, so they travel with it.
  readFile(path) {
    const mt = this._mount(path);
    if (mt) { const d = mt.m.data.files.get(mt.rel); return d === undefined ? null : d; }
    if (this.deleted.has(path)) return null;
    if (this.files.has(path)) return this.files.get(path);
    if (this.emptyFs) return null;
    const shared = this.sim.files.get(path);
    return shared === undefined ? null : shared;
  }
  writeFile(path, data) {
    const mt = this._mount(path);
    if (mt) { if (mt.rel) mt.m.data.files.set(mt.rel, data); return; }
    this.files.set(path, data); this.deleted.delete(path);
  }
  deleteFile(path) {
    const mt = this._mount(path);
    if (mt) {
      const { files, dirs } = mt.m.data;
      for (const p of [...files.keys()]) if (mt.rel === '' || p === mt.rel || p.startsWith(mt.rel + '/')) files.delete(p);
      for (const d of [...dirs]) if (mt.rel === '' || d === mt.rel || d.startsWith(mt.rel + '/')) dirs.delete(d);
      return;
    }
    for (const p of [...this.files.keys()]) if (p === path || p.startsWith(path + '/')) this.files.delete(p);
    for (const d of [...this.dirs]) if (d === path || d.startsWith(path + '/')) this.dirs.delete(d);
    if (!this.emptyFs) for (const p of this.sim.files.keys()) if (p === path || p.startsWith(path + '/')) this.deleted.add(p);
  }
  allPaths() {
    const paths = new Set();
    if (!this.emptyFs) for (const p of this.sim.files.keys()) if (!this.deleted.has(p)) paths.add(p);
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
    const mt = this._mount(path);
    if (mt) {
      if (mt.rel === '' || mt.m.data.dirs.has(mt.rel)) return true;
      for (const p of mt.m.data.files.keys()) if (p.startsWith(mt.rel + '/')) return true;
      return false;
    }
    if (this.dirs.has(path)) return true;
    for (const p of this.allPaths()) if (p.startsWith(path + '/')) return true;
    return false;
  }
  list(path) {
    const out = new Set();
    const mt = this._mount(path);
    const paths = mt ? mt.m.data.files.keys() : this.allPaths();
    const dirs = mt ? mt.m.data.dirs : this.dirs;
    const at = mt ? mt.rel : path;
    const prefix = at === '' ? '' : at + '/';
    for (const p of paths) {
      if (p.startsWith(prefix)) out.add(p.slice(prefix.length).split('/')[0]);
    }
    for (const d of dirs) if (d.startsWith(prefix) && d !== at) out.add(d.slice(prefix.length).split('/')[0]);
    if (path === '') for (const m of this.mounts()) out.add(m.path);
    return [...out];
  }

  // Lifecycle

  boot() {
    const { lua, lauxlib, lualib } = this.fengari;
    this._resetOutputs();
    this.modemChannels = new Map();
    this.knownPeripherals = new Set(this.peripheralEntries().map((e) => e.name));
    this._showState(true);
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

  // Redstone outputs (levels and bundled masks per side) go back to off
  // whenever the computer starts or stops, as in the game.
  _resetOutputs() {
    const had = this.redstone && (Object.values(this.redstone).some(Boolean) || Object.values(this.bundled).some(Boolean));
    this.redstone = {};
    this.bundled = {};
    if (this.device) { this.device.out = this.redstone; this.device.bundledOut = this.bundled; }
    if (had) this.sim.world.updateRedstone();
  }

  // The block's on/off state, for turtle.inspect.
  _showState(on) {
    const p = this.position();
    if (this.kind === 'computer' && p) { const m = this.sim.world.getMeta(p.x, p.y, p.z); if (m) m.on = on; }
  }

  shutdown() {
    this.state = 'off';
    this._resetOutputs();
    this.modemChannels = new Map();
    this.knownPeripherals = null;
    this._showState(false);
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
