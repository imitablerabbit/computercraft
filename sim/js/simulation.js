// The simulation ties the world, the computers and the clock together.
// It runs without a browser so the same code is used by the node tests.

import { World, BLOCKS, ITEMS, sideToward, makeStack } from './world.js';
import { Computer } from './computer.js';
import { Terminal } from './terminal.js';

// Marks an event argument the bios turns back into a Lua value.
const SERIALIZED = '\0serialized';

export class Simulation {
  constructor({ fengari, files, biosSource }) {
    this.fengari = fengari;
    this.files = files;        // Map of repo path -> contents
    this.biosSource = biosSource;
    this.world = new World();
    this.computers = new Map();
    this.clock = 0;            // simulated seconds
    this.speed = 1;
    this.paused = false;
    this.scheduled = [];       // { at, fn }
    this.logs = [];
    this.maxLogs = 500;
    this.version = 0;
    this.onLog = null;
    this.devicesVersion = 0;   // bumped when computers or their peripherals come and go
    this._peripheralStamp = null;
    this._wireWorld();
  }

  _wireWorld() {
    this.world.onLog = (e) => this.log({ computer: e.turtle == null ? 'world' : e.turtle, text: e.text });
    this.world.onInventory = (id) => { const c = this.computers.get(id); if (c) c.pushEvent(['turtle_inventory']); };
    this.world.host = this;
  }

  changed() { this.version++; }
  devicesChanged() { this.devicesVersion++; this.version++; }

  log(entry) {
    entry.at = this.clock;
    this.logs.push(entry);
    if (this.logs.length > this.maxLogs) this.logs.splice(0, this.logs.length - this.maxLogs);
    if (this.onLog) this.onLog(entry);
  }

  schedule(delay, fn) {
    const at = this.clock + delay;
    // keep sorted by time; stable for equal times
    let i = this.scheduled.length;
    while (i > 0 && this.scheduled[i - 1].at > at) i--;
    this.scheduled.splice(i, 0, { at, fn });
  }

  // Ids for devices added while running.
  nextId() {
    let m = 0;
    for (const c of this.computers.values()) m = Math.max(m, c.id);
    return m + 1;
  }

  // Blocks a monitor peripheral occupies, from its definition.
  _monitorBlocks(c) {
    const blocks = [];
    for (const p of c.peripherals) if (p.type === 'monitor' && p.def.blocks) blocks.push(...p.def.blocks);
    return blocks;
  }

  // Add a computer or turtle from a definition like a scenario's. It
  // boots at once unless the definition says on: false. Other fields:
  // heading (which way a computer faces, 0 north like turtles), emptyFs
  // (start with an empty disk instead of the repo's files), equipped
  // ({ left, right } upgrades of a turtle). Returns the Computer.
  addComputer(def) {
    def = { ...def, id: def.id == null ? this.nextId() : def.id };
    const c = new Computer(this, def, this.fengari);
    this.computers.set(def.id, c);
    if (def.kind === 'turtle') {
      // a wireless modem in the definition is an equipped upgrade
      const equipped = { ...(def.equipped || {}) };
      for (const side of ['left', 'right']) {
        const p = (def.peripherals || {})[side];
        if (p && p.type === 'modem' && !p.wired && equipped[side] === undefined) equipped[side] = 'computercraft:wireless_modem_normal';
      }
      if (equipped.right === 'computercraft:wireless_modem_normal' && equipped.left === undefined) equipped.left = 'minecraft:diamond_pickaxe';
      this.world.addTurtle({
        id: def.id, label: def.label, x: def.pos.x, y: def.pos.y, z: def.pos.z, heading: def.heading || 0,
        fuel: def.fuel == null ? 1000 : def.fuel, fuelLimit: def.fuelLimit || (def.advanced === false ? 20000 : 100000),
        slots: def.slots || [], advanced: def.advanced !== false, equipped,
      });
    } else if (def.pos && def.kind !== 'pocket') {
      this.world.setBlock(def.pos.x, def.pos.y, def.pos.z, def.advanced === false ? 'computer_normal' : 'computer', { facing: def.heading || 0 });
    }
    for (const b of this._monitorBlocks(c)) this.world.setBlock(b.x, b.y, b.z, 'monitor');
    if (def.kind !== 'pocket') {
      // the computer's redstone sides as the world sees them
      c.device = {
        id: def.id, pos: () => c.position(), out: c.redstone, bundledOut: c.bundled, in: {}, bundledIn: {},
        onInput: () => c.pushEvent(['redstone']),
      };
      this.world.devices.set(def.id, c.device);
    }
    if (def.on !== false) c.boot();
    this.log({ computer: def.id, text: `${def.kind} #${def.id} added` });
    this.devicesChanged();
    return c;
  }

  // Shut a computer down and take it, its block and its monitors away.
  removeComputer(id) {
    const c = this.computers.get(id);
    if (!c) return false;
    if (c.state !== 'off') c.shutdown();
    this.computers.delete(id);
    this.world.devices.delete(id);
    if (c.kind === 'turtle') this.world.turtles.delete(id);
    else if (c.def.pos) this.world.setBlock(c.def.pos.x, c.def.pos.y, c.def.pos.z, null);
    for (const b of this._monitorBlocks(c)) this.world.setBlock(b.x, b.y, b.z, null);
    this.world.redstoneDirty = true;
    this.world.version++;
    this.log({ computer: id, text: `${c.kind} #${id} removed` });
    this.devicesChanged();
    return true;
  }

  // A turtle placed a computer item: a new computer, off, facing back at
  // the turtle. A fresh one has an empty disk; one dug up with a label
  // keeps its id, label and files.
  placeComputer(x, y, z, heading, stack) {
    const data = stack.data || {};
    const advanced = (ITEMS[stack.name] || {}).computer === 'advanced';
    const id = data.id != null && !this.computers.has(data.id) ? data.id : this.nextId();
    this.addComputer({
      id, kind: 'computer', label: data.label || null, advanced, pos: { x, y, z }, heading,
      emptyFs: data.emptyFs !== false, files: data.files, dirs: data.dirs, on: false, peripherals: {}, autorun: '',
    });
    return id;
  }

  // A turtle dug a computer block: the computer goes, and the turtle gets
  // its item (with its id, label and files when it has a label, as the
  // game keeps them) and any modem that was stuck to it.
  digComputer(x, y, z) {
    const c = this.computerAt(x, y, z);
    if (!c) return null;
    const stack = { name: c.advanced ? 'computercraft:computer_advanced' : 'computercraft:computer_normal', count: 1 };
    if (c.label) stack.data = { id: c.id, label: c.label, files: new Map(c.files), dirs: [...c.dirs], emptyFs: c.emptyFs };
    const stacks = [stack];
    this.removeComputer(c.id);
    for (const [dx, dy, dz] of [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]) {
      const p = [x + dx, y + dy, z + dz];
      const m = this.world.getMeta(...p);
      if (this.world.getBlock(...p) === 'wireless_modem' && m && m.attached && m.attached.join() === [x, y, z].join()) {
        stacks.push({ name: m.advanced ? 'computercraft:wireless_modem_advanced' : 'computercraft:wireless_modem_normal', count: 1 });
        this.world.setBlock(...p, null);
      }
    }
    return stacks;
  }

  // A turtle equipped or took off an upgrade: a wireless modem is a
  // modem peripheral on that side.
  equipmentChanged(id, side, item) {
    const c = this.computers.get(id);
    if (!c) return;
    const has = c.peripherals.find((p) => p.name === side);
    if (has && has.type === 'modem') c.removePeripheral(side);
    const info = ITEMS[item] || {};
    if (info.modem) c.addPeripheral(side, { type: 'modem', advanced: info.modem === 'advanced' });
  }

  // The computer one of these blocks touches, and which of its sides it
  // is on, by the computer's heading (0, north, unless set): right is
  // east and back is south for one facing north. Returns null when no
  // computer is adjacent.
  adjacentComputer(blocks) {
    const dirs = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]];
    for (const b of blocks) {
      for (const [dx, dy, dz] of dirs) {
        const c = this.computerAt(b.x - dx, b.y - dy, b.z - dz);
        if (c) return { computer: c, side: sideToward(c.heading, dx, dy, dz) };
      }
    }
    return null;
  }

  // Attach a monitor made of the given blocks to a computer. A monitor
  // touching the computer is on that side ("right"), as in the game;
  // otherwise it is a networked monitor named monitor_N.
  addMonitor(computer, blocks, blocksW, blocksH, side) {
    let name = side || null;
    if (!name || computer.peripherals.some((p) => p.name === name)) {
      let n = 0;
      while (computer.peripherals.some((p) => p.name === `monitor_${n}`)) n++;
      name = `monitor_${n}`;
    }
    computer.addPeripheral(name, { type: 'monitor', advanced: true, blocksW, blocksH, blocks });
    for (const b of blocks) this.world.setBlock(b.x, b.y, b.z, 'monitor');
    this.log({ computer: computer.id, text: `monitor ${name} (${blocksW}x${blocksH}) attached` });
    this.changed();
    return name;
  }

  // The computer (and peripheral name) owning a monitor block, if any.
  monitorAt(x, y, z) {
    for (const c of this.computers.values()) {
      for (const p of c.peripherals) {
        if (p.type === 'monitor' && p.def.blocks && p.def.blocks.some((b) => b.x === x && b.y === y && b.z === z)) return { computer: c, name: p.name };
      }
    }
    return null;
  }

  removeMonitor(computer, name) {
    const entry = computer.removePeripheral(name);
    if (!entry) return;
    for (const b of entry.def.blocks || []) this.world.setBlock(b.x, b.y, b.z, null);
    this.log({ computer: computer.id, text: `monitor ${name} removed` });
    this.changed();
  }

  computerAt(x, y, z) {
    for (const c of this.computers.values()) {
      if (c.kind !== 'turtle' && c.def.pos && c.def.pos.x === x && c.def.pos.y === y && c.def.pos.z === z) return c;
    }
    return null;
  }

  // Build everything from a scenario definition. A scenario may list a
  // timeline of things a player does at given times (see runTimeline).
  load(scenario) {
    this.world = new World();
    this._wireWorld();
    this.computers = new Map();
    this.scheduled = [];
    this.clock = 0;
    this.logs = [];
    this.scenario = scenario;
    scenario.build(this.world);
    // everything is in place before the first computer starts, so a
    // program that looks for its neighbours at boot finds them all
    const boot = [];
    for (const def of scenario.computers) {
      const c = this.addComputer({ ...def, on: false });
      if (def.on !== false) boot.push(c);
    }
    for (const c of boot) c.boot();
    for (const ev of scenario.timeline || []) this.schedule(ev.at || 0, () => this.runTimeline(ev));
    this.world.updateRedstone();
    this._refreshPeripherals();
    this.changed();
  }

  // One timeline entry: { at, action, ... } where action is
  //   toggle  { pos }            flip a lever, or hold/release a plate
  //   press   { pos }            press a button, or step on a plate
  //   step    { pos, seconds }   stand on a pressure plate for a while
  //   give    { turtle, item, count, slot }   item is a name or a stack
  //                              like { name, files } for a floppy
  //   place   { pos, block, meta }, remove { pos }
  //   type    { computer, text } paste a line and press enter
  //   turnOn / shutdown / reboot { computer }
  runTimeline(ev) {
    // the position may also be given flat (x, y, z) and the turtle or
    // computer as either turtle or computer
    const p = ev.pos || { x: ev.x, y: ev.y, z: ev.z };
    if (ev.computer == null && ev.turtle != null) ev = { ...ev, computer: ev.turtle };
    if (ev.turtle == null && ev.computer != null) ev = { ...ev, turtle: ev.computer };
    const where = [p.x, p.y, p.z];
    const fail = (text) => this.log({ computer: 'world', text: `timeline at ${ev.at}s: ${text}`, level: 'error' });
    switch (ev.action) {
      case 'toggle': if (!this.world.use(...where, 'toggle')) fail(`nothing to toggle at ${where}`); break;
      case 'press': if (!this.world.use(...where, 'press')) fail(`nothing to press at ${where}`); break;
      case 'step': if (!this.world.use(...where, 'step', ev.seconds || 0)) fail(`no pressure plate at ${where}`); break;
      case 'give': {
        const item = typeof ev.item === 'string' ? { name: ev.item } : ev.item;
        const stack = makeStack({ ...item, count: ev.count || item.count || 1 });
        this.world.give(ev.turtle, stack.name, stack.count, ev.slot, stack.data);
        break;
      }
      case 'place': this.world.edit(...where, ev.block, ev.meta); break;
      case 'remove': this.world.edit(...where, null); break;
      case 'type': {
        const c = this.computers.get(ev.computer);
        if (!c) { fail(`no computer ${ev.computer}`); break; }
        c.pushEvent(['paste', ev.text]);
        c.pushEvent(['key', 257, false]);
        break;
      }
      case 'turnOn': case 'shutdown': case 'reboot': {
        const c = this.computers.get(ev.computer);
        if (!c) { fail(`no computer ${ev.computer}`); break; }
        if (ev.action === 'turnOn') { if (c.state !== 'running') c.boot(); } else if (ev.action === 'shutdown') c.shutdown(); else c.reboot();
        break;
      }
      default: fail(`unknown action ${ev.action}`);
    }
  }

  // Deliver a rednet message to every other computer with a modem.
  rednet(from, to, payload, protocol) {
    const sender = this.computers.get(from);
    this.log({ computer: from, text: `rednet ${to === -1 ? 'broadcast' : 'to ' + to} ${protocol || ''} ${payload.length > 60 ? payload.slice(0, 60) + '...' : payload}`, level: 'net' });
    for (const c of this.computers.values()) {
      if (c === sender) continue;
      if (to !== -1 && c.id !== to) continue;
      if (c.state !== 'running' || !c.hasModem()) continue;
      // a tick of latency, like the game
      this.schedule(0.05, () => c.pushEvent(['rednet_message', from, payload, protocol || null, SERIALIZED]));
    }
  }

  // modem.transmit: every other computer with a modem of the same kind
  // (wireless, or wired on the same network) that has the channel open
  // gets a modem_message with the distance between the two computers.
  // Wireless range is not limited.
  transmit(sender, entry, channel, replyChannel, payload) {
    const from = sender.position();
    this.log({ computer: sender.id, text: `modem ${entry.name} transmit on ${channel} (reply ${replyChannel}) ${String(payload).slice(0, 60)}`, level: 'net' });
    for (const c of this.computers.values()) {
      if (c === sender || c.state !== 'running') continue;
      for (const [name, chans] of c.modemChannels) {
        if (!chans.has(channel)) continue;
        const e = c.peripheralEntry(name);
        if (!e || e.kind !== 'modem' || e.wired !== entry.wired || (e.wired && e.network !== entry.network)) continue;
        const to = c.position();
        const distance = from && to ? Math.hypot(from.x - to.x, from.y - to.y, from.z - to.z) : null;
        this.schedule(0.05, () => c.pushEvent(['modem_message', name, channel, replyChannel, payload, distance, SERIALIZED]));
      }
    }
  }

  // Tell running computers about peripherals that came or went since the
  // last check (a chest placed beside one, a drive dug up ...).
  _refreshPeripherals() {
    for (const c of this.computers.values()) {
      if (c.state !== 'running') continue;
      const names = new Set(c.peripheralEntries().map((e) => e.name));
      if (c.knownPeripherals) {
        for (const n of names) if (!c.knownPeripherals.has(n)) c.pushEvent(['peripheral', n]);
        for (const n of c.knownPeripherals) {
          if (!names.has(n)) { c.pushEvent(['peripheral_detach', n]); c.modemChannels.delete(n); }
        }
      }
      c.knownPeripherals = names;
    }
  }

  // Redstone and peripherals follow world changes between steps.
  _settle() {
    if (this.world.redstoneDirty) this.world.updateRedstone();
    const stamp = `${this.world.version}:${this.devicesVersion}`;
    if (stamp !== this._peripheralStamp) { this._peripheralStamp = stamp; this._refreshPeripherals(); }
  }

  // Advance simulated time by dt seconds and run whatever is due.
  advance(dt) {
    if (this.paused) return;
    const target = this.clock + dt * this.speed;
    let guard = 0;
    while (guard++ < 10000) {
      // run computers on everything already queued
      let busy = false;
      for (const c of [...this.computers.values()]) if (c.step()) busy = true;
      this._settle();
      const next = this.scheduled[0];
      if (next && next.at <= target) {
        this.clock = Math.max(this.clock, next.at);
        this.world.now = this.clock;
        this.scheduled.shift();
        next.fn();
        continue;
      }
      if (!busy) break;
    }
    this.clock = target;
    this.world.now = this.clock;
    this.world.tick();
    this._settle();
  }

  // Run until the clock reaches t (for tests).
  runUntil(t) { while (this.clock < t) this.advance(Math.min(0.1, t - this.clock) / this.speed); }

  // Input

  terminalOwner(terminal) {
    for (const c of this.computers.values()) {
      for (const [name, t] of c.terminals) if (t === terminal) return { computer: c, side: name };
    }
    return null;
  }

  click(terminal, x, y, button = 1) {
    const owner = this.terminalOwner(terminal);
    if (!owner) return;
    if (owner.side === 'native') owner.computer.pushEvent(['mouse_click', button, x, y]);
    else owner.computer.pushEvent(['monitor_touch', owner.side, x, y]);
  }

  key(computer, code, char) {
    computer.pushEvent(['key', code, false]);
    if (char) computer.pushEvent(['char', char]);
  }

  keyUp(computer, code) { computer.pushEvent(['key_up', code]); }
  paste(computer, text) { computer.pushEvent(['paste', text]); }
}
