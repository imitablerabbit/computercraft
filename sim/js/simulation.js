// The simulation ties the world, the computers and the clock together.
// It runs without a browser so the same code is used by the node tests.

import { World } from './world.js';
import { Computer } from './computer.js';
import { Terminal } from './terminal.js';

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
    this.world.onLog = (e) => this.log({ computer: e.turtle, text: e.text });
    this.world.onInventory = (id) => { const c = this.computers.get(id); if (c) c.pushEvent(['turtle_inventory']); };
  }

  changed() { this.version++; }

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

  // Build everything from a scenario definition.
  load(scenario) {
    this.world = new World();
    this.world.onLog = (e) => this.log({ computer: e.turtle, text: e.text });
    this.world.onInventory = (id) => { const c = this.computers.get(id); if (c) c.pushEvent(['turtle_inventory']); };
    this.computers = new Map();
    this.scheduled = [];
    this.clock = 0;
    this.logs = [];
    this.scenario = scenario;
    scenario.build(this.world);
    for (const def of scenario.computers) {
      const c = new Computer(this, def, this.fengari);
      this.computers.set(def.id, c);
      if (def.kind === 'turtle') {
        this.world.addTurtle({
          id: def.id, label: def.label, x: def.pos.x, y: def.pos.y, z: def.pos.z, heading: def.heading || 0,
          fuel: def.fuel == null ? 1000 : def.fuel, fuelLimit: def.fuelLimit || (def.advanced === false ? 20000 : 100000),
          slots: def.slots || [], advanced: def.advanced !== false,
        });
      } else if (def.pos) {
        this.world.setBlock(def.pos.x, def.pos.y, def.pos.z, 'computer');
      }
      for (const [side, p] of Object.entries(def.peripherals || {})) {
        if (p.type === 'monitor' && p.blocks) for (const b of p.blocks) this.world.setBlock(b.x, b.y, b.z, 'monitor');
      }
    }
    for (const c of this.computers.values()) c.boot();
    this.changed();
  }

  // Deliver a rednet message to every other computer with a modem.
  rednet(from, to, payload, protocol) {
    const sender = this.computers.get(from);
    this.log({ computer: from, text: `rednet ${to === -1 ? 'broadcast' : 'to ' + to} ${protocol || ''} ${payload.length > 60 ? payload.slice(0, 60) + '...' : payload}`, level: 'net' });
    for (const c of this.computers.values()) {
      if (c === sender) continue;
      if (to !== -1 && c.id !== to) continue;
      if (!c.peripherals.some((p) => p.type === 'modem')) continue;
      // a tick of latency, like the game
      this.schedule(0.05, () => c.pushEvent(['rednet_message', from, payload, protocol || null, '\0serialized']));
    }
  }

  // Advance simulated time by dt seconds and run whatever is due.
  advance(dt) {
    if (this.paused) return;
    const target = this.clock + dt * this.speed;
    let guard = 0;
    while (guard++ < 10000) {
      // run computers on everything already queued
      let busy = false;
      for (const c of this.computers.values()) if (c.step()) busy = true;
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
