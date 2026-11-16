// Peripherals a computer can reach: what is on each of its sides (the
// static ones from its definition, such as a modem or monitor, or else
// the block there: a chest, a disk drive, another computer ...), and
// through a wired modem everything on that modem's network, under
// names like minecraft:chest_0, drive_1 or turtle_5. Each entry has a
// name, its types (peripheral.getType returns them all) and methods
// that take the Lua arguments and return a list of results.

import { BLOCKS, SIDES, sideOffset, itemDetail, insertInto, ENERGY_CAPACITY } from './world.js';

// An error a program sees, like a LuaException in the game.
export class PeripheralError extends Error {}

const luaType = (v) => (v == null ? 'nil' : typeof v === 'object' ? 'table' : typeof v);
function argNumber(args, i, optional) {
  const v = args[i];
  if (v == null && optional) return null;
  if (typeof v !== 'number') throw new PeripheralError(`bad argument #${i + 1} (number expected, got ${luaType(v)})`);
  return Math.floor(v);
}
function argString(args, i, optional) {
  const v = args[i];
  if (v == null && optional) return null;
  if (typeof v !== 'string') throw new PeripheralError(`bad argument #${i + 1} (string expected, got ${luaType(v)})`);
  return v;
}

function staticEntry(st, name) {
  if (st.type === 'monitor') return { name, types: ['monitor'], kind: 'monitor', static: st };
  if (st.type === 'modem') {
    const wired = !!st.def.wired;
    return { name, types: wired ? ['modem', 'peripheral_hub'] : ['modem'], kind: 'modem', wired, network: wired ? (st.def.network || 'default') : null };
  }
  return { name, types: [st.type], kind: 'other', static: st };
}

// The peripheral a block (or turtle) at x, y, z offers to a computer at
// `from` on side `side`, or null.
function blockEntry(sim, x, y, z, side, from) {
  const world = sim.world;
  const t = world.turtleAt(x, y, z);
  if (t) {
    const c = sim.computers.get(t.id);
    return c ? { name: side, types: ['turtle'], kind: 'computer', computer: c } : null;
  }
  const b = world.getBlock(x, y, z);
  if (!b) return null;
  const def = BLOCKS[b] || {};
  if (def.computer) {
    const c = sim.computerAt(x, y, z);
    return c ? { name: side, types: ['computer'], kind: 'computer', computer: c } : null;
  }
  if (def.modem) {
    const m = world.getMeta(x, y, z) || {};
    const a = m.attached;
    if (from && a && a[0] === from[0] && a[1] === from[1] && a[2] === from[2]) {
      return { name: side, types: ['modem'], kind: 'modem', wired: false, network: null, at: [x, y, z] };
    }
    return null;
  }
  if (def.peripheral) return { name: side, types: [...def.peripheral], kind: 'block', block: b, x, y, z };
  return null;
}

// Everything on a wired network except the computer looking.
export function networkEntries(sim, self, network) {
  const out = [];
  const world = sim.world;
  for (const k of world.networks.get(network) || []) {
    const [x, y, z] = k.split(',').map(Number);
    const e = blockEntry(sim, x, y, z, null, null);
    if (e && e.kind === 'block') { e.name = world.netName(x, y, z); e.scope = network; out.push(e); }
  }
  for (const c of sim.computers.values()) {
    if (c === self) {
      // a networked monitor set up for this computer (monitor_0 ...)
      for (const st of c.peripherals) {
        if (!SIDES.includes(st.name)) { const e = staticEntry(st, st.name); e.scope = network; out.push(e); }
      }
    } else if (c.wiredNetworks().includes(network)) {
      out.push({ name: c.netName(), types: [c.kind === 'turtle' ? 'turtle' : 'computer'], kind: 'computer', computer: c, scope: network });
    }
  }
  return out;
}

// Entries a computer sees, in peripheral.getNames order: each side in
// redstone.getSides order, followed by what a wired modem there reaches,
// then any networked monitor not already listed.
export function peripheralEntries(sim, c) {
  const out = [];
  const pos = c.position();
  for (const side of SIDES) {
    const st = c.peripherals.find((p) => p.name === side);
    let e = null;
    if (st) e = staticEntry(st, side);
    else if (pos) {
      const o = sideOffset(pos.heading, side);
      e = blockEntry(sim, pos.x + o[0], pos.y + o[1], pos.z + o[2], side, [pos.x, pos.y, pos.z]);
    }
    if (!e) continue;
    e.scope = 'local';
    out.push(e);
    if (e.kind === 'modem' && e.wired) {
      for (const r of networkEntries(sim, c, e.network)) if (!out.some((o) => o.name === r.name)) out.push(r);
    }
  }
  for (const st of c.peripherals) {
    if (SIDES.includes(st.name) || out.some((e) => e.name === st.name)) continue;
    const e = staticEntry(st, st.name);
    e.scope = 'local';
    out.push(e);
  }
  return out;
}

// The slots behind an inventory entry (a chest, or a turtle as a
// pushItems target), with a callback for after they change.
function inventoryOf(sim, e) {
  if (!e) return null;
  if (e.kind === 'block') {
    const slots = sim.world.getContainer(e.x, e.y, e.z);
    return slots ? { slots, changed: () => sim.world.version++ } : null;
  }
  if (e.kind === 'computer' && e.computer.kind === 'turtle') {
    const t = sim.world.turtles.get(e.computer.id);
    return t ? { slots: t.slots, changed: () => sim.world._inventoryChanged(t) } : null;
  }
  return null;
}

function checkSlot(slot, size, what) {
  if (slot < 1 || slot > size) throw new PeripheralError(`${what} out of range (between 1 and ${size})`);
}

function moveItems(from, fromSlot, to, toSlot, limit) {
  checkSlot(fromSlot, from.slots.length, 'From slot');
  if (toSlot != null) checkSlot(toSlot, to.slots.length, 'To slot');
  if (limit != null && limit <= 0) return 0;
  const s = from.slots[fromSlot - 1];
  if (!s) return 0;
  const n = Math.min(s.count, limit == null ? 64 : limit);
  let order = toSlot != null ? [toSlot - 1] : to.slots.map((_, i) => i);
  if (from.slots === to.slots) order = order.filter((i) => i !== fromSlot - 1);
  const moved = insertInto(to.slots, s, n, order);
  if (!moved) return 0;
  s.count -= moved;
  if (s.count === 0) from.slots[fromSlot - 1] = null;
  from.changed();
  to.changed();
  return moved;
}

// The methods of one entry, as seen by computer c.
export function methodsFor(sim, c, e) {
  const world = sim.world;
  const m = {};
  // another peripheral this one can reach by name: one on the same side
  // set (local) or on the same wired network
  const reach = (name) => peripheralEntries(sim, c).find((o) => o.name === name && o.scope === e.scope) || null;
  const target = (name) => {
    const o = reach(name);
    if (!o) throw new PeripheralError(`Target '${name}' does not exist`);
    const inv = inventoryOf(sim, o);
    if (!inv) throw new PeripheralError(`Target '${name}' is not an inventory`);
    return inv;
  };
  if (e.kind === 'block' && BLOCKS[e.block].container) {
    const inv = () => inventoryOf(sim, e);
    m.size = () => [inv().slots.length];
    m.list = () => {
      const out = new Map();
      inv().slots.forEach((s, i) => { if (s) { const d = itemDetail(s, false); delete d.damage; out.set(i + 1, d); } });
      return [out];
    };
    m.getItemDetail = (a) => {
      const slot = argNumber(a, 0); const slots = inv().slots;
      checkSlot(slot, slots.length, 'Slot');
      return [slots[slot - 1] ? itemDetail(slots[slot - 1], true) : null];
    };
    m.getItemLimit = (a) => { const slot = argNumber(a, 0); checkSlot(slot, inv().slots.length, 'Slot'); return [64]; };
    m.pushItems = (a) => {
      const to = argString(a, 0); const fromSlot = argNumber(a, 1); const limit = argNumber(a, 2, true); const toSlot = argNumber(a, 3, true);
      return [moveItems(inv(), fromSlot, target(to), toSlot, limit)];
    };
    m.pullItems = (a) => {
      const from = argString(a, 0); const fromSlot = argNumber(a, 1); const limit = argNumber(a, 2, true); const toSlot = argNumber(a, 3, true);
      return [moveItems(target(from), fromSlot, inv(), toSlot, limit)];
    };
  } else if (e.kind === 'block' && e.block === 'energy_cell') {
    m.getEnergy = () => [world.energyAt(e.x, e.y, e.z)];
    m.getEnergyCapacity = () => [ENERGY_CAPACITY];
  } else if (e.kind === 'block' && e.block === 'tank') {
    m.tanks = () => [[{ name: 'minecraft:lava', amount: world.tankAt(e.x, e.y, e.z) }]];
  } else if (e.kind === 'block' && e.block === 'disk_drive') {
    const meta = () => world.getMeta(e.x, e.y, e.z) || {};
    const disk = () => meta().disk || null;
    m.isDiskPresent = () => [!!disk()];
    m.getDiskLabel = () => [disk() ? disk().data.label : null];
    m.setDiskLabel = (a) => { const l = argString(a, 0, true); if (disk()) { disk().data.label = l; world.version++; } return []; };
    m.hasData = () => [!!disk()];
    m.getMountPath = () => { const mt = c.mounts().find((x) => x.entryName === e.name); return [mt ? mt.path : null]; };
    m.hasAudio = () => [false];
    m.getAudioTitle = () => [null];
    m.playAudio = () => [];
    m.stopAudio = () => [];
    m.ejectDisk = () => {
      if (disk()) { meta().disk = null; world.version++; world.log('world', `a disk was ejected from the drive at ${e.x},${e.y},${e.z} (lost)`); }
      return [];
    };
    m.getDiskID = () => [disk() ? disk().data.diskId : null];
  } else if (e.kind === 'computer') {
    const other = e.computer;
    m.turnOn = () => { if (other.state !== 'running') sim.schedule(0, () => { if (other.state !== 'running') other.boot(); }); return []; };
    m.shutdown = () => { sim.schedule(0, () => { if (other.state !== 'off') other.shutdown(); }); return []; };
    m.reboot = () => { sim.schedule(0, () => other.reboot()); return []; };
    m.getID = () => [other.id];
    m.isOn = () => [other.state === 'running'];
    m.getLabel = () => [other.label];
  } else if (e.kind === 'modem') {
    const chans = () => {
      if (!c.modemChannels.has(e.name)) c.modemChannels.set(e.name, new Set());
      return c.modemChannels.get(e.name);
    };
    const channel = (a, i) => {
      const ch = argNumber(a, i);
      if (ch < 0 || ch > 65535) throw new PeripheralError('Expected number in range 0-65535');
      return ch;
    };
    m.open = (a) => {
      const ch = channel(a, 0);
      if (!chans().has(ch) && chans().size >= 128) throw new PeripheralError('Too many open channels');
      chans().add(ch);
      return [];
    };
    m.isOpen = (a) => [chans().has(channel(a, 0))];
    m.close = (a) => { chans().delete(channel(a, 0)); return []; };
    m.closeAll = () => { chans().clear(); return []; };
    // the bios serialises the message before it gets here
    m.transmit = (a) => { sim.transmit(c, e, channel(a, 0), channel(a, 1), a[2]); return []; };
    m.isWireless = () => [!e.wired];
    if (e.wired) {
      const remote = () => networkEntries(sim, c, e.network);
      const find = (name) => remote().find((o) => o.name === name) || null;
      m.getNamesRemote = () => [remote().map((o) => o.name)];
      m.isPresentRemote = (a) => [!!find(argString(a, 0))];
      m.getTypeRemote = (a) => { const o = find(argString(a, 0)); return o ? o.types : [null]; };
      m.hasTypeRemote = (a) => { const o = find(argString(a, 0)); const ty = argString(a, 1); return [o ? o.types.includes(ty) : null]; };
      m.getMethodsRemote = (a) => { const o = find(argString(a, 0)); return [o ? methodNames(sim, c, o) : null]; };
      m.callRemote = (a) => {
        const name = argString(a, 0); const method = argString(a, 1);
        const o = find(name);
        if (!o) throw new PeripheralError(`No peripheral attached`);
        return callEntry(sim, c, o, method, a.slice(2));
      };
      m.getNameLocal = () => [c.netName()];
    }
  }
  return m;
}

export function methodNames(sim, c, e) {
  if (e.kind === 'monitor') return MONITOR_METHODS;
  return Object.keys(methodsFor(sim, c, e)).sort();
}

export function callEntry(sim, c, e, method, args) {
  const fn = methodsFor(sim, c, e)[method];
  if (!fn) throw new PeripheralError(`No such method ${method}`);
  return fn(args);
}

const MONITOR_METHODS = ['blit', 'clear', 'clearLine', 'getBackgroundColor', 'getBackgroundColour', 'getCursorBlink', 'getCursorPos',
  'getPaletteColor', 'getPaletteColour', 'getSize', 'getTextColor', 'getTextColour', 'getTextScale', 'isColor', 'isColour',
  'scroll', 'setBackgroundColor', 'setBackgroundColour', 'setCursorBlink', 'setCursorPos', 'setPaletteColor',
  'setPaletteColour', 'setTextColor', 'setTextColour', 'setTextScale', 'write'];
