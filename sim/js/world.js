// The voxel world the turtles live in: blocks, chests and the turtles
// themselves, plus the rules for every turtle action. Coordinates: x is
// east (heading 1), y is north (heading 0, the way a turtle faces when
// placed), z is up. Headings turn clockwise: 0 north, 1 east, 2 south,
// 3 west.

export const BLOCKS = {
  grass:        { color: '#5f9d3a', drops: 'minecraft:dirt', name: 'minecraft:grass_block' },
  dirt:         { color: '#8a5a32', drops: 'minecraft:dirt' },
  stone:        { color: '#8a8a8a', drops: 'minecraft:cobblestone' },
  cobblestone:  { color: '#777777', drops: 'minecraft:cobblestone' },
  sand:         { color: '#dbd3a0', drops: 'minecraft:sand', falls: true },
  gravel:       { color: '#857d7a', drops: 'minecraft:gravel', falls: true },
  coal_ore:     { color: '#4a4a4a', drops: 'minecraft:coal' },
  iron_ore:     { color: '#b89a7a', drops: 'minecraft:raw_iron' },
  bedrock:      { color: '#2b2b2b', drops: null, unbreakable: true },
  log:          { color: '#6b4f2a', drops: 'minecraft:oak_log', name: 'minecraft:oak_log' },
  leaves:       { color: '#3d7a2a', drops: 'minecraft:oak_leaves', name: 'minecraft:oak_leaves' },
  planks:       { color: '#b08d55', drops: 'minecraft:oak_planks', name: 'minecraft:oak_planks' },
  chest:        { color: '#a67c3b', drops: 'minecraft:chest', container: 27 },
  torch:        { color: '#ffd96b', drops: 'minecraft:torch', passable: true },
  sapling:      { color: '#7fcc5a', drops: 'minecraft:oak_sapling', name: 'minecraft:oak_sapling', grows: true },
  computer:     { color: '#c8c8c8', drops: 'computercraft:computer_advanced', name: 'computercraft:computer_advanced' },
  monitor:      { color: '#2c2c3a', drops: 'computercraft:monitor_advanced', name: 'computercraft:monitor_advanced' },
  water:        { color: '#3b6fd6', drops: null, passable: true },
  // the nether, and the atomic reconstructor that turns netherrack into
  // ores when a redstone pulse reaches it (reconstructs: weighted results)
  netherrack:   { color: '#6e2c2c', drops: 'minecraft:netherrack', name: 'minecraft:netherrack',
                  reconstructs: [['nether_quartz_ore', 3000], ['nether_gold_ore', 500], ['ancient_debris', 1]] },
  nether_quartz_ore: { color: '#8f6b6b', drops: 'minecraft:quartz', name: 'minecraft:nether_quartz_ore' },
  nether_gold_ore:   { color: '#a07a4a', drops: 'minecraft:gold_nugget', name: 'minecraft:nether_gold_ore' },
  ancient_debris:    { color: '#4d3b36', drops: 'minecraft:ancient_debris', name: 'minecraft:ancient_debris' },
  redstone_wire: { color: '#c0291a', drops: 'minecraft:redstone', name: 'minecraft:redstone_wire', passable: true, wire: true },
  reconstructor: { color: '#3f8f9f', drops: 'actuallyadditions:atomic_reconstructor', name: 'actuallyadditions:atomic_reconstructor', machine: true },
};

// How far a reconstructor's laser reaches and how many wire blocks a
// pulse travels through.
export const LASER_RANGE = 10;
export const WIRE_RANGE = 15;

export const ITEMS = {
  'minecraft:dirt':          { displayName: 'Dirt', block: 'dirt', groups: ['Natural Blocks'], tags: ['minecraft:dirt'] },
  'minecraft:cobblestone':   { displayName: 'Cobblestone', block: 'cobblestone', groups: ['Building Blocks'], tags: ['minecraft:stone_crafting_materials', 'minecraft:stone_tool_materials'] },
  'minecraft:stone':         { displayName: 'Stone', block: 'stone', groups: ['Building Blocks'] },
  'minecraft:sand':          { displayName: 'Sand', block: 'sand', groups: ['Natural Blocks'], tags: ['minecraft:sand'] },
  'minecraft:gravel':        { displayName: 'Gravel', block: 'gravel', groups: ['Natural Blocks'] },
  'minecraft:coal':          { displayName: 'Coal', fuel: 80, groups: ['Ingredients'], tags: ['minecraft:coals'] },
  'minecraft:charcoal':      { displayName: 'Charcoal', fuel: 80, groups: ['Ingredients'], tags: ['minecraft:coals'] },
  'minecraft:raw_iron':      { displayName: 'Raw Iron', groups: ['Ingredients'] },
  'minecraft:iron_ingot':    { displayName: 'Iron Ingot', groups: ['Ingredients'] },
  'minecraft:oak_log':       { displayName: 'Oak Log', block: 'log', fuel: 15, groups: ['Natural Blocks'], tags: ['minecraft:logs', 'minecraft:oak_logs'] },
  'minecraft:oak_leaves':    { displayName: 'Oak Leaves', block: 'leaves', groups: ['Natural Blocks'], tags: ['minecraft:leaves'] },
  'minecraft:oak_planks':    { displayName: 'Oak Planks', block: 'planks', fuel: 15, groups: ['Building Blocks'], tags: ['minecraft:planks'] },
  'minecraft:oak_sapling':   { displayName: 'Oak Sapling', block: 'sapling', fuel: 5, groups: ['Natural Blocks'], tags: ['minecraft:saplings'] },
  'minecraft:torch':         { displayName: 'Torch', block: 'torch', groups: ['Functional Blocks'] },
  'minecraft:chest':         { displayName: 'Chest', block: 'chest', groups: ['Functional Blocks'] },
  'minecraft:stone_pickaxe': { displayName: 'Stone Pickaxe', maxCount: 1, maxDamage: 131, groups: ['Tools & Utilities'] },
  'minecraft:bucket':        { displayName: 'Bucket', maxCount: 16, groups: ['Tools & Utilities'] },
  'minecraft:lava_bucket':   { displayName: 'Lava Bucket', maxCount: 1, fuel: 1000, groups: ['Tools & Utilities'] },
  'minecraft:netherrack':    { displayName: 'Netherrack', block: 'netherrack', groups: ['Natural Blocks'] },
  'minecraft:quartz':        { displayName: 'Nether Quartz', groups: ['Ingredients'] },
  'minecraft:gold_nugget':   { displayName: 'Gold Nugget', groups: ['Ingredients'] },
  'minecraft:ancient_debris': { displayName: 'Ancient Debris', block: 'ancient_debris', groups: ['Natural Blocks'] },
  'minecraft:redstone':      { displayName: 'Redstone Dust', block: 'redstone_wire', groups: ['Redstone Blocks'] },
  'actuallyadditions:atomic_reconstructor': { displayName: 'Atomic Reconstructor', block: 'reconstructor', groups: ['Actually Additions'] },
  'computercraft:computer_advanced': { displayName: 'Advanced Computer', block: 'computer' },
  'computercraft:monitor_advanced':  { displayName: 'Advanced Monitor', block: 'monitor' },
};

export const HEADINGS = [[0, 1], [1, 0], [0, -1], [-1, 0]];
export const HEADING_NAMES = ['north', 'east', 'south', 'west'];

const key = (x, y, z) => `${x},${y},${z}`;

// Simulated seconds for a planted sapling to become a tree.
export const GROW_TIME = 45;

// A four block oak trunk with a blob of leaves; existing blocks stay.
export function tree(world, x, y, base) {
  for (let z = base; z < base + 4; z++) world.setBlock(x, y, z, 'log');
  for (let dx = -2; dx <= 2; dx++) for (let dy = -2; dy <= 2; dy++) for (let dz = 2; dz <= 4; dz++) {
    if (Math.abs(dx) + Math.abs(dy) + (dz - 2) <= 3 && !(dx === 0 && dy === 0 && dz < 4)) {
      if (!world.getBlock(x + dx, y + dy, base + dz)) world.setBlock(x + dx, y + dy, base + dz, 'leaves');
    }
  }
}

function itemInfo(name) {
  return ITEMS[name] || { displayName: name.replace(/^[^:]+:/, '').replace(/_/g, ' ') };
}

export class World {
  constructor() {
    this.blocks = new Map();
    this.containers = new Map();
    this.planted = new Map(); // sapling key -> time planted
    this.meta = new Map();    // block key -> extra state, e.g. { facing } for a machine
    this.turtles = new Map();
    this.version = 0;
    this.onLog = null;
    this.onInventory = null; // (turtleId) => void
    this.actionDelay = 0.4;  // sim seconds a move or dig takes
    this.now = 0;
  }

  log(turtleId, text) { if (this.onLog) this.onLog({ turtle: turtleId, text, at: this.now }); }

  // Blocks

  getBlock(x, y, z) { return this.blocks.get(key(x, y, z)) || null; }

  setBlock(x, y, z, type, meta) {
    const k = key(x, y, z);
    if (type) {
      this.blocks.set(k, type);
      if (meta) this.meta.set(k, { ...meta }); else if (!BLOCKS[type] || !BLOCKS[type].machine) this.meta.delete(k);
      if (BLOCKS[type] && BLOCKS[type].container && !this.containers.has(k)) {
        this.containers.set(k, new Array(BLOCKS[type].container).fill(null));
      }
      if (BLOCKS[type] && BLOCKS[type].grows) this.planted.set(k, this.now); else this.planted.delete(k);
    } else {
      this.blocks.delete(k);
      this.containers.delete(k);
      this.planted.delete(k);
      this.meta.delete(k);
    }
    this.version++;
  }

  // Put items in a chest at a position (for scenarios).
  fillContainer(x, y, z, items) {
    const slots = this.containers.get(key(x, y, z));
    if (!slots) return;
    items.forEach((it, i) => { if (i < slots.length) slots[i] = it ? { ...it } : null; });
    this.version++;
  }

  getContainer(x, y, z) { return this.containers.get(key(x, y, z)) || null; }

  getMeta(x, y, z) { return this.meta.get(key(x, y, z)) || null; }

  // Redstone

  // A turtle's output on one of its sides went on. The block against
  // that side is powered, and so is anything a run of redstone wire
  // from there touches. Every reconstructor among them fires.
  redstonePulse(turtleId, side) {
    const t = this.turtles.get(turtleId);
    if (!t) return;
    const [fx, fy] = HEADINGS[t.heading];
    const offsets = {
      front: [fx, fy, 0], back: [-fx, -fy, 0], top: [0, 0, 1], bottom: [0, 0, -1],
      left: [...HEADINGS[(t.heading + 3) % 4], 0], right: [...HEADINGS[(t.heading + 1) % 4], 0],
    };
    const o = offsets[side];
    if (!o) return;
    const start = [t.x + o[0], t.y + o[1], t.z + o[2]];
    const powered = new Map([[key(...start), start]]);
    const wires = [];
    if ((BLOCKS[this.getBlock(...start)] || {}).wire) wires.push(start);
    const seen = new Set(wires.map((w) => key(...w)));
    while (wires.length && seen.size <= WIRE_RANGE) {
      const [x, y, z] = wires.shift();
      for (const [dx, dy, dz] of [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]) {
        const p = [x + dx, y + dy, z + dz];
        const k = key(...p);
        powered.set(k, p);
        if ((BLOCKS[this.getBlock(...p)] || {}).wire && !seen.has(k)) { seen.add(k); wires.push(p); }
      }
    }
    let fired = 0;
    for (const p of powered.values()) {
      if ((BLOCKS[this.getBlock(...p)] || {}).machine) { this.fireMachine(...p); fired++; }
    }
    if (!fired) this.log(turtleId, `pulsed redstone ${side}, nothing there to fire`);
  }

  // A reconstructor shoots along its facing and changes the first block
  // it reaches, picking the result by weight.
  fireMachine(x, y, z) {
    const facing = (this.getMeta(x, y, z) || {}).facing ?? 0;
    const [dx, dy] = HEADINGS[facing];
    for (let i = 1; i <= LASER_RANGE; i++) {
      const bx = x + dx * i, by = y + dy * i;
      const b = this.getBlock(bx, by, z);
      if (!b) continue;
      const table = (BLOCKS[b] || {}).reconstructs;
      if (!table) { this.log('world', `the reconstructor at ${x},${y},${z} hit ${b}, which it cannot change`); return; }
      const total = table.reduce((n, [, w]) => n + w, 0);
      let r = Math.random() * total;
      let result = table[table.length - 1][0];
      for (const [name, w] of table) { r -= w; if (r < 0) { result = name; break; } }
      this.setBlock(bx, by, z, result);
      this.log('world', `the reconstructor turned ${b} into ${result}`);
      return;
    }
    this.log('world', `the reconstructor at ${x},${y},${z} fired at nothing`);
  }

  // Saplings planted long enough ago become trees, if a turtle is not
  // standing where the trunk goes.
  grow() {
    for (const [k, at] of this.planted) {
      if (this.now - at < GROW_TIME) continue;
      const [x, y, z] = k.split(',').map(Number);
      if (this.turtleAt(x, y, z) || this.turtleAt(x, y, z + 1)) continue;
      this.planted.delete(k);
      tree(this, x, y, z);
      this.log(null, `a sapling at ${k} grew into a tree`);
    }
  }

  turtleAt(x, y, z) {
    for (const t of this.turtles.values()) if (t.x === x && t.y === y && t.z === z) return t;
    return null;
  }

  isFree(x, y, z) {
    const b = this.getBlock(x, y, z);
    if (b && !(BLOCKS[b] && BLOCKS[b].passable)) return false;
    return !this.turtleAt(x, y, z);
  }

  // Sand and gravel above a removed block fall into the gap.
  settle(x, y, z) {
    let zz = z;
    while (true) {
      const above = this.getBlock(x, y, zz + 1);
      if (!above || !BLOCKS[above] || !BLOCKS[above].falls) return;
      if (this.getBlock(x, y, zz) || this.turtleAt(x, y, zz)) return;
      this.blocks.delete(key(x, y, zz + 1));
      this.blocks.set(key(x, y, zz), above);
      this.version++;
      zz++;
    }
  }

  // Turtles

  addTurtle({ id, label, x, y, z, heading = 0, fuel = 1000, fuelLimit = 20000, slots = [], advanced = true }) {
    const t = {
      id, label: label || `Turtle ${id}`, x, y, z, heading, fuel, fuelLimit, advanced,
      selected: 1,
      slots: new Array(16).fill(null),
      // animation state for the 3D view
      anim: { fromX: x, fromY: y, fromZ: z, fromHeading: heading, start: 0, duration: 0 },
    };
    slots.forEach((s, i) => { if (s && i < 16) t.slots[i] = { name: s.name, count: s.count, damage: s.damage }; });
    this.turtles.set(id, t);
    this.version++;
    return t;
  }

  _animate(t, duration) {
    t.anim.start = this.now;
    t.anim.duration = duration;
  }

  _snapshot(t) {
    t.anim.fromX = t.x; t.anim.fromY = t.y; t.anim.fromZ = t.z; t.anim.fromHeading = t.heading;
  }

  _inventoryChanged(t) {
    this.version++;
    if (this.onInventory) this.onInventory(t.id);
  }

  _facing(t, dir) {
    if (dir === 'up') return [t.x, t.y, t.z + 1];
    if (dir === 'down') return [t.x, t.y, t.z - 1];
    const [dx, dy] = HEADINGS[t.heading];
    return [t.x + dx, t.y + dy, t.z];
  }

  // Add items to the inventory like the game does: from the selected
  // slot on, the first slot that is empty or holds the same item takes
  // them, so an empty selected slot gets them even when a matching stack
  // sits elsewhere. Returns how many did not fit.
  _addItems(t, name, count, damage) {
    const info = itemInfo(name);
    const max = info.maxCount || 64;
    for (let n = 0; n < 16 && count > 0; n++) {
      const i = (t.selected - 1 + n) % 16;
      const s = t.slots[i];
      if (!s) {
        const take = Math.min(max, count);
        t.slots[i] = { name, count: take, damage };
        count -= take;
      } else if (s.name === name && s.damage === damage && s.count < max) {
        const take = Math.min(max - s.count, count);
        s.count += take; count -= take;
      }
    }
    this._inventoryChanged(t);
    return count;
  }

  _move(t, dir) {
    let nx, ny, nz;
    if (dir === 'back') {
      const [dx, dy] = HEADINGS[t.heading];
      nx = t.x - dx; ny = t.y - dy; nz = t.z;
    } else {
      [nx, ny, nz] = this._facing(t, dir);
    }
    if (t.fuel !== 'unlimited' && t.fuel <= 0) return { ok: false, reason: 'Out of fuel' };
    if (!this.isFree(nx, ny, nz)) return { ok: false, reason: 'Movement obstructed' };
    this._snapshot(t);
    t.x = nx; t.y = ny; t.z = nz;
    if (t.fuel !== 'unlimited') t.fuel -= 1;
    this._animate(t, this.actionDelay);
    this.version++;
    return { ok: true };
  }

  _turn(t, right) {
    this._snapshot(t);
    t.heading = (t.heading + (right ? 1 : 3)) % 4;
    this._animate(t, this.actionDelay);
    this.version++;
    return { ok: true };
  }

  _dig(t, dir) {
    const [x, y, z] = this._facing(t, dir);
    const b = this.getBlock(x, y, z);
    if (!b) return { ok: false, reason: 'Nothing to dig here' };
    const def = BLOCKS[b] || {};
    if (def.unbreakable) return { ok: false, reason: 'Unbreakable block detected' };
    this.setBlock(x, y, z, null);
    if (def.drops) {
      const left = this._addItems(t, def.drops, 1);
      if (left) this.log(t.id, `inventory full, ${def.drops} dropped on the ground`);
    }
    this.settle(x, y, z);
    this.log(t.id, `dug ${b} ${dir === 'forward' ? 'ahead' : dir}`);
    return { ok: true };
  }

  _place(t, dir) {
    const s = t.slots[t.selected - 1];
    if (!s) return { ok: false, reason: 'No items to place' };
    const info = itemInfo(s.name);
    if (!info.block) return { ok: false, reason: 'Cannot place item here' };
    const [x, y, z] = this._facing(t, dir);
    if (this.getBlock(x, y, z) || this.turtleAt(x, y, z)) return { ok: false, reason: 'Cannot place block here' };
    this.setBlock(x, y, z, info.block);
    s.count -= 1;
    if (s.count === 0) t.slots[t.selected - 1] = null;
    this._inventoryChanged(t);
    this.log(t.id, `placed ${info.block}`);
    return { ok: true };
  }

  _drop(t, dir, count) {
    const s = t.slots[t.selected - 1];
    if (!s) return { ok: false, reason: 'No items to drop' };
    const n = Math.min(count == null ? s.count : count, s.count);
    const [x, y, z] = this._facing(t, dir);
    const slots = this.getContainer(x, y, z);
    if (slots) {
      let left = n;
      const max = itemInfo(s.name).maxCount || 64;
      for (let i = 0; i < slots.length && left > 0; i++) {
        const c = slots[i];
        if (c && c.name === s.name && c.count < max) { const take = Math.min(max - c.count, left); c.count += take; left -= take; }
      }
      for (let i = 0; i < slots.length && left > 0; i++) {
        if (!slots[i]) { const take = Math.min(max, left); slots[i] = { name: s.name, count: take }; left -= take; }
      }
      const moved = n - left;
      if (moved === 0) return { ok: false, reason: 'No space for items' };
      s.count -= moved;
      if (s.count === 0) t.slots[t.selected - 1] = null;
      this._inventoryChanged(t);
      this.log(t.id, `put ${moved} ${s.name} in the chest`);
      return { ok: true };
    }
    if (this.getBlock(x, y, z) && !(BLOCKS[this.getBlock(x, y, z)] || {}).passable) return { ok: false, reason: 'No space for items' };
    s.count -= n;
    if (s.count === 0) t.slots[t.selected - 1] = null;
    this._inventoryChanged(t);
    this.log(t.id, `dropped ${n} ${s.name} on the ground (lost)`);
    return { ok: true };
  }

  _suck(t, dir, count) {
    const [x, y, z] = this._facing(t, dir);
    const slots = this.getContainer(x, y, z);
    if (!slots) return { ok: false, reason: 'No items to take' };
    const i = slots.findIndex((c) => c);
    if (i < 0) return { ok: false, reason: 'No items to take' };
    const c = slots[i];
    const n = Math.min(count == null ? 64 : count, c.count);
    const left = this._addItems(t, c.name, n, c.damage);
    const moved = n - left;
    if (moved === 0) return { ok: false, reason: 'No space for items' };
    c.count -= moved;
    if (c.count === 0) slots[i] = null;
    this.version++;
    this.log(t.id, `took ${moved} ${c.name} from the chest`);
    return { ok: true };
  }

  // Actions that take time in the game. The result is known at once but
  // the caller delivers it after actionDelay.
  turtleAction(id, action, arg) {
    const t = this.turtles.get(id);
    if (!t) return { ok: false, reason: 'no such turtle' };
    switch (action) {
      case 'forward': case 'back': case 'up': case 'down': return this._move(t, action);
      case 'turnLeft': return this._turn(t, false);
      case 'turnRight': return this._turn(t, true);
      case 'dig': return this._dig(t, 'forward');
      case 'digUp': return this._dig(t, 'up');
      case 'digDown': return this._dig(t, 'down');
      case 'place': return this._place(t, 'forward');
      case 'placeUp': return this._place(t, 'up');
      case 'placeDown': return this._place(t, 'down');
      case 'drop': return this._drop(t, 'forward', arg);
      case 'dropUp': return this._drop(t, 'up', arg);
      case 'dropDown': return this._drop(t, 'down', arg);
      case 'suck': return this._suck(t, 'forward', arg);
      case 'suckUp': return this._suck(t, 'up', arg);
      case 'suckDown': return this._suck(t, 'down', arg);
      case 'attack': case 'attackUp': case 'attackDown': return { ok: false, reason: 'Nothing to attack here' };
      default: return { ok: false, reason: `unknown action ${action}` };
    }
  }

  // Instant queries and inventory operations.
  turtleQuery(id, q, a, b) {
    const t = this.turtles.get(id);
    if (!t) return null;
    switch (q) {
      case 'detect': case 'detectUp': case 'detectDown': {
        const [x, y, z] = this._facing(t, q === 'detect' ? 'forward' : q === 'detectUp' ? 'up' : 'down');
        const blk = this.getBlock(x, y, z);
        return !!(blk && !(BLOCKS[blk] || {}).passable);
      }
      case 'inspect': case 'inspectUp': case 'inspectDown': {
        const [x, y, z] = this._facing(t, q === 'inspect' ? 'forward' : q === 'inspectUp' ? 'up' : 'down');
        const blk = this.getBlock(x, y, z);
        if (!blk) return [false, 'No block to inspect'];
        return [true, { name: (BLOCKS[blk] || {}).name || `minecraft:${blk}`, state: {}, tags: {} }];
      }
      case 'getSelectedSlot': return t.selected;
      case 'select': {
        const slot = Math.floor(a);
        if (slot < 1 || slot > 16) return [false, 'Slot number 1-16 expected'];
        t.selected = slot; this.version++; return [true];
      }
      case 'getItemCount': { const s = t.slots[(a || t.selected) - 1]; return s ? s.count : 0; }
      case 'getItemSpace': { const s = t.slots[(a || t.selected) - 1]; return s ? (itemInfo(s.name).maxCount || 64) - s.count : 64; }
      case 'getItemDetail': {
        const s = t.slots[(a || t.selected) - 1];
        if (!s) return null;
        const info = itemInfo(s.name);
        const d = { name: s.name, count: s.count };
        if (s.damage != null) d.damage = s.damage;
        if (b) {
          d.displayName = info.displayName;
          d.maxCount = info.maxCount || 64;
          if (info.maxDamage) { d.maxDamage = info.maxDamage; d.damage = s.damage || 0; }
          d.tags = {};
          for (const tag of info.tags || []) d.tags[tag] = true;
          d.itemGroups = (info.groups || []).map((g) => ({ id: g.toLowerCase().replace(/[^a-z]+/g, '_'), displayName: g }));
        }
        return d;
      }
      case 'getFuelLevel': return t.fuel;
      case 'getFuelLimit': return t.fuelLimit;
      case 'refuel': {
        const s = t.slots[t.selected - 1];
        if (!s) return [false, 'No items to combust'];
        const info = itemInfo(s.name);
        if (!info.fuel) return [false, 'Items not combustible'];
        const n = a == null ? s.count : Math.floor(a);
        if (n === 0) return [true];
        if (t.fuel === 'unlimited') return [true];
        const burn = Math.min(n, s.count, Math.max(1, Math.ceil((t.fuelLimit - t.fuel) / info.fuel)));
        t.fuel = Math.min(t.fuelLimit, t.fuel + burn * info.fuel);
        s.count -= burn;
        if (s.count === 0) t.slots[t.selected - 1] = null;
        this._inventoryChanged(t);
        this.log(t.id, `burnt ${burn} ${s.name}, fuel ${t.fuel}`);
        return [true];
      }
      case 'transferTo': {
        const from = t.slots[t.selected - 1];
        const to = Math.floor(a);
        if (!from || to < 1 || to > 16) return false;
        const n = b == null ? from.count : Math.min(b, from.count);
        const dest = t.slots[to - 1];
        if (dest && (dest.name !== from.name || dest.damage !== from.damage)) return false;
        const max = itemInfo(from.name).maxCount || 64;
        const moved = Math.min(n, max - (dest ? dest.count : 0));
        if (moved <= 0) return false;
        if (dest) dest.count += moved; else t.slots[to - 1] = { name: from.name, count: moved, damage: from.damage };
        from.count -= moved;
        if (from.count === 0) t.slots[t.selected - 1] = null;
        this._inventoryChanged(t);
        return true;
      }
      case 'compare': case 'compareUp': case 'compareDown': {
        const [x, y, z] = this._facing(t, q === 'compare' ? 'forward' : q === 'compareUp' ? 'up' : 'down');
        const blk = this.getBlock(x, y, z);
        const s = t.slots[t.selected - 1];
        return !!(blk && s && itemInfo(s.name).block === blk);
      }
      default: return null;
    }
  }

  // Put items into a turtle from outside, like a player would. With a
  // slot the items go into that slot only, if it is empty or holds the
  // same item. Returns how many fitted.
  give(id, name, count, slot) {
    const t = this.turtles.get(id);
    if (!t) return 0;
    let fitted;
    if (slot) {
      const max = itemInfo(name).maxCount || 64;
      const s = t.slots[slot - 1];
      if (s && s.name !== name) { this.log(id, `slot ${slot} holds ${s.name}, nothing given`); return 0; }
      fitted = Math.min(count, max - (s ? s.count : 0));
      if (fitted <= 0) { this.log(id, `slot ${slot} is full, nothing given`); return 0; }
      if (s) s.count += fitted; else t.slots[slot - 1] = { name, count: fitted };
      this._inventoryChanged(t);
    } else {
      fitted = count - this._addItems(t, name, count);
    }
    this.log(id, `was given ${fitted} ${name}${slot ? ' in slot ' + slot : ''}`);
    return fitted;
  }

  // Place or remove a block by hand. Returns false when a turtle is in
  // the way.
  edit(x, y, z, type, meta) {
    if (type && this.turtleAt(x, y, z)) return false;
    if (type && !BLOCKS[type]) return false;
    this.setBlock(x, y, z, type, meta);
    if (!type) this.settle(x, y, z);
    const facing = meta && meta.facing != null ? ` facing ${HEADING_NAMES[meta.facing]}` : '';
    this.log('world', type ? `${type} placed at ${x},${y},${z}${facing}` : `block removed at ${x},${y},${z}`);
    return true;
  }

  // Interpolated position and heading for drawing.
  turtlePose(t, now) {
    const a = t.anim;
    let f = a.duration > 0 ? (now - a.start) / a.duration : 1;
    f = Math.max(0, Math.min(1, f));
    let dh = t.heading - a.fromHeading;
    if (dh > 2) dh -= 4; if (dh < -2) dh += 4;
    return {
      x: a.fromX + (t.x - a.fromX) * f,
      y: a.fromY + (t.y - a.fromY) * f,
      z: a.fromZ + (t.z - a.fromZ) * f,
      heading: a.fromHeading + dh * f,
    };
  }
}

export function itemDisplayName(name) { return itemInfo(name).displayName; }
