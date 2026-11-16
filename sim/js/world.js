// The voxel world the turtles live in: blocks, chests and the turtles
// themselves, plus the rules for every turtle action. Coordinates: x is
// east (heading 1), y is north (heading 0, the way a turtle faces when
// placed), z up. Headings turn clockwise: 0 north, 1 east, 2 south,
// 3 west. Minecraft's own coordinates (x east, y up, z south) are
// (x, z, -y) of ours; gps and anything else the game shows use those.

export const BLOCKS = {
  grass:        { color: '#5f9d3a', drops: 'minecraft:dirt', name: 'minecraft:grass_block' },
  dirt:         { color: '#8a5a32', drops: 'minecraft:dirt' },
  stone:        { color: '#8a8a8a', drops: 'minecraft:cobblestone' },
  cobblestone:  { color: '#777777', drops: 'minecraft:cobblestone' },
  stone_bricks: { color: '#7d7d7d', drops: 'minecraft:stone_bricks', name: 'minecraft:stone_bricks' },
  glass:        { color: '#cfe6ee', drops: null, name: 'minecraft:glass' },
  sand:         { color: '#dbd3a0', drops: 'minecraft:sand', falls: true },
  gravel:       { color: '#857d7a', drops: 'minecraft:gravel', falls: true },
  coal_ore:     { color: '#4a4a4a', drops: 'minecraft:coal' },
  iron_ore:     { color: '#b89a7a', drops: 'minecraft:raw_iron' },
  bedrock:      { color: '#2b2b2b', drops: null, unbreakable: true },
  log:          { color: '#6b4f2a', drops: 'minecraft:oak_log', name: 'minecraft:oak_log' },
  leaves:       { color: '#3d7a2a', drops: 'minecraft:oak_leaves', name: 'minecraft:oak_leaves', soft: true },
  planks:       { color: '#b08d55', drops: 'minecraft:oak_planks', name: 'minecraft:oak_planks' },
  chest:        { color: '#a67c3b', drops: 'minecraft:chest', container: 27, peripheral: ['minecraft:chest', 'inventory'] },
  torch:        { color: '#ffd96b', drops: 'minecraft:torch', passable: true },
  sapling:      { color: '#7fcc5a', drops: 'minecraft:oak_sapling', name: 'minecraft:oak_sapling', grows: true, soft: true },
  computer:     { color: '#c8c8c8', drops: 'computercraft:computer_advanced', name: 'computercraft:computer_advanced', computer: true },
  computer_normal: { color: '#a9a9a9', drops: 'computercraft:computer_normal', name: 'computercraft:computer_normal', computer: true },
  monitor:      { color: '#2c2c3a', drops: 'computercraft:monitor_advanced', name: 'computercraft:monitor_advanced' },
  // A wireless modem stuck to the block it was placed against (meta
  // attached: [x, y, z]); a computer there has it on that side.
  wireless_modem: { color: '#d8d8c0', drops: 'computercraft:wireless_modem_normal', name: 'computercraft:wireless_modem_normal', modem: true },
  disk_drive:   { color: '#9a9a9a', drops: 'computercraft:disk_drive', name: 'computercraft:disk_drive', peripheral: ['drive'], netPrefix: 'drive' },
  // Liquids: turtles move through them, cannot dig them, and an empty
  // bucket picks up a source block (meta level 0).
  water:        { color: '#3b6fd6', drops: null, passable: true, liquid: true, bucket: 'minecraft:water_bucket' },
  lava:         { color: '#e0601a', drops: null, passable: true, liquid: true, bucket: 'minecraft:lava_bucket' },
  // farming: crops sit on farmland and age 0..7 (meta age)
  farmland:     { color: '#5b3b1f', drops: 'minecraft:dirt', name: 'minecraft:farmland' },
  wheat:        { color: '#c9b44a', name: 'minecraft:wheat', crop: { seed: 'minecraft:wheat_seeds', produce: 'minecraft:wheat' }, soft: true },
  carrots:      { color: '#e08a2a', name: 'minecraft:carrots', crop: { seed: 'minecraft:carrot', produce: 'minecraft:carrot' }, soft: true },
  potatoes:     { color: '#c8a85a', name: 'minecraft:potatoes', crop: { seed: 'minecraft:potato', produce: 'minecraft:potato' }, soft: true },
  rail:         { color: '#8c7a5b', drops: 'minecraft:rail', name: 'minecraft:rail', needsSupport: true },
  // the nether, and the atomic reconstructor that turns netherrack into
  // ores when a redstone pulse reaches it (reconstructs: weighted results)
  netherrack:   { color: '#6e2c2c', drops: 'minecraft:netherrack', name: 'minecraft:netherrack',
                  reconstructs: [['nether_quartz_ore', 3000], ['nether_gold_ore', 500], ['ancient_debris', 1]] },
  nether_quartz_ore: { color: '#8f6b6b', drops: 'minecraft:quartz', name: 'minecraft:nether_quartz_ore' },
  nether_gold_ore:   { color: '#a07a4a', drops: 'minecraft:gold_nugget', name: 'minecraft:nether_gold_ore' },
  ancient_debris:    { color: '#4d3b36', drops: 'minecraft:ancient_debris', name: 'minecraft:ancient_debris' },
  // redstone: sources (lever, button, plate, sensor, block), wire, and
  // things that react to power (lamp, door, reconstructor)
  redstone_wire: { color: '#c0291a', drops: 'minecraft:redstone', name: 'minecraft:redstone_wire', passable: true, wire: true, redstone: 'wire' },
  lever:        { color: '#9a8058', drops: 'minecraft:lever', name: 'minecraft:lever', redstone: 'lever' },
  button:       { color: '#9c9c9c', drops: 'minecraft:stone_button', name: 'minecraft:stone_button', redstone: 'button' },
  pressure_plate: { color: '#a3a3a3', drops: 'minecraft:stone_pressure_plate', name: 'minecraft:stone_pressure_plate', redstone: 'plate' },
  daylight_sensor: { color: '#d8c89a', drops: 'minecraft:daylight_detector', name: 'minecraft:daylight_detector', redstone: 'daylight' },
  redstone_block: { color: '#a01810', drops: 'minecraft:redstone_block', name: 'minecraft:redstone_block', redstone: 'block' },
  redstone_lamp: { color: '#6b4a2a', drops: 'minecraft:redstone_lamp', name: 'minecraft:redstone_lamp', redstone: 'lamp' },
  door:         { color: '#c4c4c4', drops: 'minecraft:iron_door', name: 'minecraft:iron_door', redstone: 'door' },
  cable:        { color: '#d6d6d6', drops: 'computercraft:cable', name: 'computercraft:cable' },
  bundled_cable: { color: '#5a4a8a', drops: 'projectred_transmission:bundled_cable', name: 'projectred_transmission:bundled_cable', bundled: true },
  reconstructor: { color: '#3f8f9f', drops: 'actuallyadditions:atomic_reconstructor', name: 'actuallyadditions:atomic_reconstructor', machine: true, redstone: 'machine' },
  // modded machines seen through CC: Tweaked's generic peripherals
  energy_cell:  { color: '#b03a3a', drops: 'thermal:energy_cell', name: 'thermal:energy_cell', peripheral: ['thermal:energy_cell', 'energy_storage'] },
  tank:         { color: '#7a8a9a', drops: 'create:fluid_tank', name: 'create:fluid_tank', peripheral: ['create:fluid_tank', 'fluid_storage'] },
};

// How far a reconstructor's laser reaches and how many wire blocks a
// pulse travels through (redstone loses one level per wire block).
export const LASER_RANGE = 10;
export const WIRE_RANGE = 15;

// Simulated seconds between a crop's age steps (0..7), how long a
// button stays pressed and how long a plate stays down after a step.
export const CROP_GROW_TIME = 5;
export const BUTTON_TIME = 1;
export const PLATE_TIME = 1;

// Generic peripherals: an energy cell's stored energy and a tank's lava
// swing slowly between nearly empty and nearly full over these periods.
export const ENERGY_CAPACITY = 1000000;
export const ENERGY_PERIOD = 240;
export const TANK_CAPACITY = 16000;
export const TANK_PERIOD = 180;

export const ITEMS = {
  'minecraft:dirt':          { displayName: 'Dirt', block: 'dirt', groups: ['Natural Blocks'], tags: ['minecraft:dirt'] },
  'minecraft:cobblestone':   { displayName: 'Cobblestone', block: 'cobblestone', groups: ['Building Blocks'], tags: ['minecraft:stone_crafting_materials', 'minecraft:stone_tool_materials'] },
  'minecraft:stone':         { displayName: 'Stone', block: 'stone', groups: ['Building Blocks'] },
  'minecraft:stone_bricks':  { displayName: 'Stone Bricks', block: 'stone_bricks', groups: ['Building Blocks'], tags: ['minecraft:stone_bricks'] },
  'minecraft:glass':         { displayName: 'Glass', block: 'glass', groups: ['Building Blocks'] },
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
  'minecraft:rail':          { displayName: 'Rail', block: 'rail', groups: ['Redstone Blocks'], tags: ['minecraft:rails'] },
  'minecraft:stone_pickaxe': { displayName: 'Stone Pickaxe', maxCount: 1, maxDamage: 131, groups: ['Tools & Utilities'] },
  'minecraft:diamond_pickaxe': { displayName: 'Diamond Pickaxe', maxCount: 1, maxDamage: 1561, groups: ['Tools & Utilities'], tool: 'pickaxe' },
  'minecraft:diamond_axe':   { displayName: 'Diamond Axe', maxCount: 1, maxDamage: 1561, groups: ['Tools & Utilities'], tool: 'axe' },
  'minecraft:diamond_shovel': { displayName: 'Diamond Shovel', maxCount: 1, maxDamage: 1561, groups: ['Tools & Utilities'], tool: 'shovel' },
  'minecraft:diamond_hoe':   { displayName: 'Diamond Hoe', maxCount: 1, maxDamage: 1561, groups: ['Tools & Utilities'], tool: 'hoe' },
  'minecraft:diamond_sword': { displayName: 'Diamond Sword', maxCount: 1, maxDamage: 1561, groups: ['Combat'], tool: 'sword' },
  'minecraft:crafting_table': { displayName: 'Crafting Table', fuel: 15, groups: ['Functional Blocks'], tool: 'crafting' },
  'minecraft:stick':         { displayName: 'Stick', fuel: 5, groups: ['Ingredients'] },
  'minecraft:furnace':       { displayName: 'Furnace', groups: ['Functional Blocks'] },
  'minecraft:ladder':        { displayName: 'Ladder', fuel: 15, groups: ['Functional Blocks'] },
  'minecraft:bucket':        { displayName: 'Bucket', maxCount: 16, groups: ['Tools & Utilities'] },
  'minecraft:lava_bucket':   { displayName: 'Lava Bucket', maxCount: 1, fuel: 1000, remainder: 'minecraft:bucket', liquid: 'lava', groups: ['Tools & Utilities'] },
  'minecraft:water_bucket':  { displayName: 'Water Bucket', maxCount: 1, remainder: 'minecraft:bucket', liquid: 'water', groups: ['Tools & Utilities'] },
  'minecraft:wheat_seeds':   { displayName: 'Wheat Seeds', plant: 'wheat', groups: ['Natural Blocks'], tags: ['minecraft:villager_plantable_seeds'] },
  'minecraft:wheat':         { displayName: 'Wheat', groups: ['Ingredients'] },
  'minecraft:carrot':        { displayName: 'Carrot', plant: 'carrots', groups: ['Food & Drinks'], tags: ['minecraft:villager_plantable_seeds'] },
  'minecraft:potato':        { displayName: 'Potato', plant: 'potatoes', groups: ['Food & Drinks'], tags: ['minecraft:villager_plantable_seeds'] },
  'minecraft:poisonous_potato': { displayName: 'Poisonous Potato', groups: ['Food & Drinks'] },
  'minecraft:netherrack':    { displayName: 'Netherrack', block: 'netherrack', groups: ['Natural Blocks'] },
  'minecraft:quartz':        { displayName: 'Nether Quartz', groups: ['Ingredients'] },
  'minecraft:gold_nugget':   { displayName: 'Gold Nugget', groups: ['Ingredients'] },
  'minecraft:ancient_debris': { displayName: 'Ancient Debris', block: 'ancient_debris', groups: ['Natural Blocks'] },
  'minecraft:redstone':      { displayName: 'Redstone Dust', block: 'redstone_wire', groups: ['Redstone Blocks'] },
  'minecraft:lever':         { displayName: 'Lever', block: 'lever', groups: ['Redstone Blocks'] },
  'minecraft:stone_button':  { displayName: 'Stone Button', block: 'button', groups: ['Redstone Blocks'], tags: ['minecraft:buttons'] },
  'minecraft:stone_pressure_plate': { displayName: 'Stone Pressure Plate', block: 'pressure_plate', groups: ['Redstone Blocks'] },
  'minecraft:daylight_detector': { displayName: 'Daylight Detector', block: 'daylight_sensor', groups: ['Redstone Blocks'] },
  'minecraft:redstone_block': { displayName: 'Block of Redstone', block: 'redstone_block', groups: ['Redstone Blocks'] },
  'minecraft:redstone_lamp': { displayName: 'Redstone Lamp', block: 'redstone_lamp', groups: ['Redstone Blocks'] },
  'minecraft:iron_door':     { displayName: 'Iron Door', block: 'door', groups: ['Redstone Blocks'], tags: ['minecraft:doors'] },
  'projectred_transmission:bundled_cable': { displayName: 'Bundled Cable', block: 'bundled_cable', groups: ['Project Red'] },
  'actuallyadditions:atomic_reconstructor': { displayName: 'Atomic Reconstructor', block: 'reconstructor', groups: ['Actually Additions'] },
  'thermal:energy_cell':     { displayName: 'Energy Cell', block: 'energy_cell', groups: ['Thermal'] },
  'create:fluid_tank':       { displayName: 'Fluid Tank', block: 'tank', groups: ['Create'] },
  'computercraft:computer_normal': { displayName: 'Computer', computer: 'normal', groups: ['ComputerCraft'] },
  'computercraft:computer_advanced': { displayName: 'Advanced Computer', block: 'computer', computer: 'advanced', groups: ['ComputerCraft'] },
  'computercraft:monitor_advanced':  { displayName: 'Advanced Monitor', block: 'monitor', groups: ['ComputerCraft'] },
  'computercraft:wireless_modem_normal': { displayName: 'Wireless Modem', modem: 'normal', tool: 'modem', groups: ['ComputerCraft'] },
  'computercraft:wireless_modem_advanced': { displayName: 'Ender Modem', modem: 'advanced', tool: 'modem', groups: ['ComputerCraft'] },
  'computercraft:cable':     { displayName: 'Networking Cable', block: 'cable', groups: ['ComputerCraft'] },
  'computercraft:disk_drive': { displayName: 'Disk Drive', block: 'disk_drive', groups: ['ComputerCraft'] },
  'computercraft:disk':      { displayName: 'Floppy Disk', maxCount: 1, disk: true, groups: ['ComputerCraft'] },
};

export const HEADINGS = [[0, 1], [1, 0], [0, -1], [-1, 0]];
export const HEADING_NAMES = ['north', 'east', 'south', 'west'];
export const SIDES = ['top', 'bottom', 'left', 'right', 'front', 'back'];
const DIRS6 = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]];

const key = (x, y, z) => `${x},${y},${z}`;
const unkey = (k) => k.split(',').map(Number);

// Where a side of something facing `heading` points, and the reverse.
export function sideOffset(heading, side) {
  const [fx, fy] = HEADINGS[heading];
  switch (side) {
    case 'front': return [fx, fy, 0];
    case 'back': return [-fx, -fy, 0];
    case 'left': { const [lx, ly] = HEADINGS[(heading + 3) % 4]; return [lx, ly, 0]; }
    case 'right': { const [rx, ry] = HEADINGS[(heading + 1) % 4]; return [rx, ry, 0]; }
    case 'top': return [0, 0, 1];
    case 'bottom': return [0, 0, -1];
    default: return null;
  }
}
export function sideToward(heading, dx, dy, dz) {
  for (const s of SIDES) {
    const o = sideOffset(heading, s);
    if (o[0] === dx && o[1] === dy && o[2] === dz) return s;
  }
  return null;
}

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

export function itemInfo(name) {
  return ITEMS[name] || { displayName: name.replace(/^[^:]+:/, '').replace(/_/g, ' ') };
}

export function maxStack(stack) { return stack.data ? 1 : (itemInfo(stack.name).maxCount || 64); }

// Two stacks merge when they are the same item and neither carries its
// own data (a floppy's files, a labelled computer).
export function sameItem(a, b) {
  return a.name === b.name && (a.damage ?? null) === (b.damage ?? null) && !a.data && !b.data;
}

// A slot entry from a scenario or Give: { name, count, damage }, plus
// for a floppy { files: { path: text }, label } which becomes its data.
export function makeStack(s) {
  if (!s) return null;
  const out = { name: s.name, count: s.count == null ? 1 : s.count };
  if (s.damage != null) out.damage = s.damage;
  if (s.data) out.data = s.data;
  else if (s.files || s.label != null || itemInfo(s.name).disk) {
    out.data = { files: new Map(Object.entries(s.files || {})), dirs: new Set(), label: s.label ?? null, diskId: null };
  }
  return out;
}

// Put up to n of stack into slots, visiting slot indexes in order: each
// takes as many as fit, empty or holding the same item. Returns how many
// went in.
export function insertInto(slots, stack, n, order) {
  const max = maxStack(stack);
  let left = n;
  for (const i of order) {
    if (left <= 0) break;
    const s = slots[i];
    if (!s) {
      const take = Math.min(max, left);
      slots[i] = { name: stack.name, count: take };
      if (stack.damage != null) slots[i].damage = stack.damage;
      if (stack.data) slots[i].data = stack.data;
      left -= take;
    } else if (sameItem(s, stack) && s.count < max) {
      const take = Math.min(max - s.count, left);
      s.count += take; left -= take;
    }
  }
  return n - left;
}

// What a crafty turtle can craft here: a few vanilla recipes. A shaped
// recipe's pattern is its rows (spaces are empty), matched wherever it
// sits in the grid and mirrored too; a key letter may stand for several
// items. A shapeless one lists its items.
const PLANKS = ['minecraft:oak_planks'];
const COALS = ['minecraft:coal', 'minecraft:charcoal'];
export const RECIPES = [
  { items: ['minecraft:oak_log'], out: 'minecraft:oak_planks', count: 4 },
  { pattern: ['P', 'P'], key: { P: PLANKS }, out: 'minecraft:stick', count: 4 },
  { pattern: ['C', 'S'], key: { C: COALS, S: ['minecraft:stick'] }, out: 'minecraft:torch', count: 4 },
  { pattern: ['PP', 'PP'], key: { P: PLANKS }, out: 'minecraft:crafting_table', count: 1 },
  { pattern: ['PPP', 'P P', 'PPP'], key: { P: PLANKS }, out: 'minecraft:chest', count: 1 },
  { pattern: ['CCC', 'C C', 'CCC'], key: { C: ['minecraft:cobblestone'] }, out: 'minecraft:furnace', count: 1 },
  { pattern: ['CCC', ' S ', ' S '], key: { C: ['minecraft:cobblestone'], S: ['minecraft:stick'] }, out: 'minecraft:stone_pickaxe', count: 1 },
  { pattern: ['S S', 'SSS', 'S S'], key: { S: ['minecraft:stick'] }, out: 'minecraft:ladder', count: 3 },
  { pattern: ['I I', 'ISI', 'I I'], key: { I: ['minecraft:iron_ingot'], S: ['minecraft:stick'] }, out: 'minecraft:rail', count: 16 },
];

// The recipe a 3x3 grid of item names (null for empty) makes, or null.
export function matchRecipe(grid) {
  const used = [];
  for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) if (grid[r][c]) used.push([r, c]);
  if (!used.length) return null;
  const r0 = Math.min(...used.map((u) => u[0])); const r1 = Math.max(...used.map((u) => u[0]));
  const c0 = Math.min(...used.map((u) => u[1])); const c1 = Math.max(...used.map((u) => u[1]));
  const rows = [];
  for (let r = r0; r <= r1; r++) rows.push(grid[r].slice(c0, c1 + 1));
  for (const recipe of RECIPES) {
    if (recipe.items) {
      const have = used.map(([r, c]) => grid[r][c]).sort();
      const want = [...recipe.items].sort();
      if (have.length === want.length && have.every((n, i) => n === want[i])) return recipe;
      continue;
    }
    const p = recipe.pattern;
    if (p.length !== rows.length || p[0].length !== rows[0].length) continue;
    const fits = (mirror) => rows.every((row, r) => row.every((name, c) => {
      const ch = p[r][mirror ? row.length - 1 - c : c];
      return ch === ' ' ? !name : !!name && recipe.key[ch].includes(name);
    }));
    if (fits(false) || fits(true)) return recipe;
  }
  return null;
}

// The detail table turtle.getItemDetail and inventory peripherals give.
export function itemDetail(s, detailed) {
  const info = itemInfo(s.name);
  const d = { name: s.name, count: s.count };
  if (s.damage != null) d.damage = s.damage;
  if (s.data) d.nbt = (s.data.diskId != null ? 'disk' + s.data.diskId : 'data').padEnd(32, '0');
  if (detailed) {
    d.displayName = s.data && s.data.label ? s.data.label : info.displayName;
    d.maxCount = maxStack(s);
    if (info.maxDamage) { d.maxDamage = info.maxDamage; d.damage = s.damage || 0; }
    d.tags = {};
    for (const tag of info.tags || []) d.tags[tag] = true;
    d.itemGroups = (info.groups || []).map((g) => ({ id: g.toLowerCase().replace(/[^a-z]+/g, '_'), displayName: g }));
  }
  return d;
}

// A small deterministic hash of a position, for jitter and phases.
function hashPos(x, y, z) {
  let h = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791);
  h = Math.imul(h ^ (h >>> 13), 0x5bd1e995);
  return ((h ^ (h >>> 15)) >>> 0) / 4294967296;
}

// Block state as turtle.inspect reports it, Minecraft style.
const MC_FACING = ['north', 'east', 'south', 'west'];

export class World {
  constructor() {
    this.blocks = new Map();
    this.containers = new Map();
    this.planted = new Map(); // sapling key -> time planted
    this.meta = new Map();    // block key -> extra state, e.g. { facing } for a machine
    this.crops = new Set();   // keys of crop blocks
    this.redstoneKeys = new Set(); // keys of redstone sources, wire, lamps, doors, machines, cables
    this.networks = new Map();     // wired network name -> Set of block keys on it
    this.netCounters = {};         // peripheral name prefix -> next number
    this.netNames = new Map();     // block key -> its name on its network
    this.devices = new Map();      // computer id -> redstone device (see Simulation)
    this.turtles = new Map();
    this.version = 0;
    this.redstoneDirty = false;
    this.onLog = null;
    this.onInventory = null; // (turtleId) => void
    this.host = null;        // the Simulation, for placing and digging computers
    this.actionDelay = 0.4;  // sim seconds a move or dig takes
    this.now = 0;
    this.seed = 20261116;
    this.nextDiskId = 0;
  }

  log(turtleId, text) { if (this.onLog) this.onLog({ turtle: turtleId, text, at: this.now }); }

  // Deterministic random numbers for drops, so runs repeat.
  random() {
    this.seed = (Math.imul(this.seed, 1103515245) + 12345) & 0x7fffffff;
    return this.seed / 0x7fffffff;
  }

  // Blocks

  getBlock(x, y, z) { return this.blocks.get(key(x, y, z)) || null; }

  setBlock(x, y, z, type, meta) {
    const k = key(x, y, z);
    const old = this.blocks.get(k);
    if (old && BLOCKS[old] && BLOCKS[old].peripheral) this._leaveNetwork(k);
    if (type) {
      const def = BLOCKS[type] || {};
      this.blocks.set(k, type);
      if (meta) this.meta.set(k, { ...meta });
      else if (def.machine && this.meta.has(k)) { /* a machine keeps its facing */ }
      else if (def.redstone || def.crop || def.liquid || def.bundled || def.peripheral || def.modem || def.computer) this.meta.set(k, {});
      else this.meta.delete(k);
      if (def.container && !this.containers.has(k)) {
        this.containers.set(k, new Array(def.container).fill(null));
      } else if (!def.container) this.containers.delete(k);
      if (def.grows) this.planted.set(k, this.now); else this.planted.delete(k);
      const m = this.meta.get(k);
      if (def.crop) {
        m.age = Math.max(0, Math.min(7, Math.floor(m.age || 0)));
        // crops grow out of step with each other, as random ticks do
        if (m.since == null) m.since = this.now - hashPos(x, y, z) * CROP_GROW_TIME;
        this.crops.add(k);
      } else this.crops.delete(k);
      if (def.liquid && m.level == null) m.level = 0;
      if (def.redstone || def.bundled) this.redstoneKeys.add(k); else this.redstoneKeys.delete(k);
      if (def.peripheral && m.network) this._joinNetwork(k, type, m);
    } else {
      this.blocks.delete(k);
      this.containers.delete(k);
      this.planted.delete(k);
      this.meta.delete(k);
      this.crops.delete(k);
      this.redstoneKeys.delete(k);
    }
    // a crop without farmland under it breaks
    if (old === 'farmland' && type !== 'farmland') {
      const above = this.getBlock(x, y, z + 1);
      if (above && BLOCKS[above].crop) { this.setBlock(x, y, z + 1, null); this.log('world', `the ${above} at ${x},${y},${z + 1} broke`); }
    }
    this.redstoneDirty = true;
    this.version++;
  }

  // A peripheral block with meta network joins that wired network under
  // a name like minecraft:chest_0 (numbered per type in the order they
  // join), or the meta's own netName if it has one.
  _joinNetwork(k, type, m) {
    let name = m.netName;
    if (!name) {
      const prefix = BLOCKS[type].netPrefix || BLOCKS[type].peripheral[0];
      const n = this.netCounters[prefix] || 0;
      this.netCounters[prefix] = n + 1;
      name = `${prefix}_${n}`;
    }
    this.netNames.set(k, name);
    if (!this.networks.has(m.network)) this.networks.set(m.network, new Set());
    this.networks.get(m.network).add(k);
  }

  _leaveNetwork(k) {
    for (const members of this.networks.values()) members.delete(k);
    this.netNames.delete(k);
  }

  // The name a block goes by on its wired network, or null.
  netName(x, y, z) { return this.netNames.get(key(x, y, z)) || null; }

  // Put items in a chest at a position (for scenarios).
  fillContainer(x, y, z, items) {
    const slots = this.containers.get(key(x, y, z));
    if (!slots) return;
    items.forEach((it, i) => { if (i < slots.length) slots[i] = makeStack(it); });
    this.version++;
  }

  getContainer(x, y, z) { return this.containers.get(key(x, y, z)) || null; }

  getMeta(x, y, z) { return this.meta.get(key(x, y, z)) || null; }

  isPassable(x, y, z) {
    const b = this.getBlock(x, y, z);
    return !b || !!(BLOCKS[b] && BLOCKS[b].passable);
  }

  // What turtle.inspect shows for a block: name, state and tags.
  blockInfo(x, y, z) {
    const blk = this.getBlock(x, y, z);
    if (!blk) return null;
    const def = BLOCKS[blk] || {};
    const m = this.getMeta(x, y, z) || {};
    const state = {};
    const tags = {};
    const facing = MC_FACING[m.facing ?? 0];
    if (def.crop) {
      state.age = m.age;
      tags['minecraft:crops'] = true; tags['minecraft:bee_growables'] = true; tags['minecraft:maintains_farmland'] = true;
    } else if (def.liquid) state.level = m.level || 0;
    else if (blk === 'farmland') state.moisture = 7;
    else if (blk === 'grass' || blk === 'dirt') tags['minecraft:dirt'] = true;
    else if (blk === 'log') { state.axis = 'y'; tags['minecraft:logs'] = true; tags['minecraft:oak_logs'] = true; }
    else if (blk === 'leaves') { tags['minecraft:leaves'] = true; state.persistent = false; state.distance = 1; }
    else if (blk === 'rail') { state.shape = m.shape || 'north_south'; state.waterlogged = false; tags['minecraft:rails'] = true; }
    else if (blk === 'redstone_lamp') state.lit = !!m.lit;
    else if (blk === 'door') { state.open = !!m.open; state.powered = !!m.open; state.facing = facing; state.half = 'lower'; state.hinge = 'left'; tags['minecraft:doors'] = true; }
    else if (blk === 'lever' || blk === 'button') { state.powered = !!m.on; state.face = 'floor'; state.facing = facing; }
    else if (blk === 'pressure_plate') state.powered = !!m.on;
    else if (blk === 'daylight_sensor') { state.power = this.daylightLevel(); state.inverted = false; }
    else if (blk === 'redstone_wire') state.power = m.power || 0;
    else if (blk === 'chest') { state.facing = facing; state.type = 'single'; state.waterlogged = false; }
    else if (def.computer) { state.facing = facing; state.state = m.on ? 'on' : 'off'; }
    else if (blk === 'disk_drive') { state.facing = facing; state.state = m.disk ? 'full' : 'empty'; }
    let name = def.name || `minecraft:${blk}`;
    if (blk === 'wireless_modem') { state.facing = 'north'; if (m.advanced) name = 'computercraft:wireless_modem_advanced'; }
    return { name, state, tags };
  }

  // Generic peripheral values that drift with time, the same for every
  // run: a slow sine wave with a phase from the block's position.
  energyAt(x, y, z) {
    const f = 0.5 + 0.45 * Math.sin(2 * Math.PI * (this.now / ENERGY_PERIOD + hashPos(x, y, z)));
    return Math.round(ENERGY_CAPACITY * f);
  }
  tankAt(x, y, z) {
    const f = 0.5 + 0.45 * Math.sin(2 * Math.PI * (this.now / TANK_PERIOD + hashPos(x, y, z)));
    return Math.round(TANK_CAPACITY * f);
  }

  // Redstone

  // Daylight sensor output for the time of day os.time reports (a day
  // is 1200 simulated seconds, noon brightest).
  daylightLevel() {
    const t = (this.now / 50) % 24;
    if (t < 6 || t > 18) return 0;
    return Math.round(15 * Math.sin(Math.PI * (t - 6) / 12));
  }

  deviceAt(x, y, z) {
    for (const d of this.devices.values()) {
      const p = d.pos();
      if (p && p.x === x && p.y === y && p.z === z) return d;
    }
    return null;
  }

  // The redstone level the thing at n sends into the neighbouring
  // position p: a computer's or turtle's output on that side, a source
  // block, or powered wire.
  _emission(n, p, wires) {
    const d = this.deviceAt(n[0], n[1], n[2]);
    if (d) {
      const pos = d.pos();
      const side = sideToward(pos.heading, p[0] - n[0], p[1] - n[1], p[2] - n[2]);
      return d.out[side] || 0;
    }
    const b = this.getBlock(n[0], n[1], n[2]);
    const def = b && BLOCKS[b];
    if (!def || !def.redstone) return 0;
    const m = this.getMeta(n[0], n[1], n[2]) || {};
    switch (def.redstone) {
      case 'lever': case 'button': case 'plate': return m.on ? 15 : 0;
      case 'block': return 15;
      case 'daylight': return this.daylightLevel();
      case 'wire': return wires.get(key(...n)) || 0;
      default: return 0;
    }
  }

  // Work out every wire's level and what each lamp, door, machine,
  // computer and turtle receives, and react to changes: lamps light,
  // doors open, a reconstructor fires when its power comes on, and a
  // device whose input changed gets a redstone event. Returns how many
  // reconstructors fired.
  updateRedstone() {
    this.redstoneDirty = false;
    const wires = new Map();
    const wireKeys = [];
    const cableKeys = [];
    for (const k of this.redstoneKeys) {
      const def = BLOCKS[this.blocks.get(k)] || {};
      if (def.redstone === 'wire') wireKeys.push(k);
      else if (def.bundled) cableKeys.push(k);
    }
    const isWire = (p) => (BLOCKS[this.getBlock(...p)] || {}).redstone === 'wire';
    // wire next to a source takes its level, then it spreads along the
    // wire losing one level per block
    for (const k of wireKeys) {
      const p = unkey(k);
      let lv = 0;
      for (const [dx, dy, dz] of DIRS6) {
        const n = [p[0] + dx, p[1] + dy, p[2] + dz];
        if (!isWire(n)) lv = Math.max(lv, this._emission(n, p, wires));
      }
      if (lv > 0) wires.set(k, lv);
    }
    for (let changed = true; changed;) {
      changed = false;
      for (const k of wireKeys) {
        const p = unkey(k);
        let cur = wires.get(k) || 0;
        for (const [dx, dy, dz] of DIRS6) {
          const l = (wires.get(key(p[0] + dx, p[1] + dy, p[2] + dz)) || 0) - 1;
          if (l > cur) { cur = l; wires.set(k, l); changed = true; }
        }
      }
    }
    const powerAt = (p) => {
      let lv = 0;
      for (const [dx, dy, dz] of DIRS6) lv = Math.max(lv, this._emission([p[0] + dx, p[1] + dy, p[2] + dz], p, wires));
      return lv;
    };
    let fired = 0;
    for (const k of this.redstoneKeys) {
      const type = this.blocks.get(k);
      const def = BLOCKS[type] || {};
      const m = this.meta.get(k);
      if (!m) continue;
      if (def.redstone === 'wire') { const lv = wires.get(k) || 0; if ((m.power || 0) !== lv) { m.power = lv; this.version++; } continue; }
      if (!['lamp', 'door', 'machine'].includes(def.redstone)) continue;
      const p = unkey(k);
      const on = powerAt(p) > 0;
      if (def.redstone === 'lamp' && !!m.lit !== on) { m.lit = on; this.version++; }
      if (def.redstone === 'door' && !!m.open !== on) { m.open = on; this.version++; this.log('world', `the door at ${k} ${on ? 'opened' : 'closed'}`); }
      if (def.redstone === 'machine') {
        if (on && !m.powered) { m.powered = true; this.fireMachine(...p); fired++; }
        else if (!on) m.powered = false;
      }
    }
    // bundled cables: each connected run carries the OR of the bundled
    // outputs of the devices touching it
    const nets = new Map(); // cable key -> net object { contributions: Map(deviceId -> mask) }
    for (const k of cableKeys) {
      if (nets.has(k)) continue;
      const net = { contributions: new Map() };
      const queue = [k];
      nets.set(k, net);
      while (queue.length) {
        const p = unkey(queue.shift());
        for (const [dx, dy, dz] of DIRS6) {
          const nk = key(p[0] + dx, p[1] + dy, p[2] + dz);
          if (!nets.has(nk) && (BLOCKS[this.blocks.get(nk)] || {}).bundled) { nets.set(nk, net); queue.push(nk); }
        }
      }
    }
    for (const d of this.devices.values()) {
      const pos = d.pos();
      if (!pos) continue;
      for (const side of SIDES) {
        const mask = d.bundledOut[side] || 0;
        if (!mask) continue;
        const o = sideOffset(pos.heading, side);
        const net = nets.get(key(pos.x + o[0], pos.y + o[1], pos.z + o[2]));
        if (net) net.contributions.set(d.id, (net.contributions.get(d.id) || 0) | mask);
      }
    }
    for (const d of this.devices.values()) {
      const pos = d.pos();
      if (!pos) continue;
      let changed = false;
      for (const side of SIDES) {
        const o = sideOffset(pos.heading, side);
        const n = [pos.x + o[0], pos.y + o[1], pos.z + o[2]];
        const lv = this._emission(n, [pos.x, pos.y, pos.z], wires);
        if ((d.in[side] || 0) !== lv) { d.in[side] = lv; changed = true; }
        let mask = 0;
        const net = nets.get(key(...n));
        if (net) { for (const [id, m] of net.contributions) if (id !== d.id) mask |= m; }
        else {
          const other = this.deviceAt(...n);
          if (other) {
            const op = other.pos();
            mask = other.bundledOut[sideToward(op.heading, -o[0], -o[1], -o[2])] || 0;
          }
        }
        if ((d.bundledIn[side] || 0) !== mask) { d.bundledIn[side] = mask; changed = true; }
      }
      if (changed && d.onInput) d.onInput();
    }
    return fired;
  }

  // A turtle's output on one of its sides went on (kept for callers of
  // the old pulse API): recompute redstone and say when nothing fired.
  redstonePulse(turtleId, side) {
    const fired = this.updateRedstone();
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

  // A player using a block: flip a lever, press a button, step on a
  // pressure plate (for `seconds`, or toggled on and off by 'toggle').
  // Returns false when there is nothing usable there.
  use(x, y, z, how = 'use', seconds) {
    const b = this.getBlock(x, y, z);
    const m = this.getMeta(x, y, z);
    if (!b || !m) return false;
    const where = `${x},${y},${z}`;
    if (b === 'lever') {
      m.on = how === 'on' ? true : how === 'off' ? false : !m.on;
      this.log('world', `the lever at ${where} was switched ${m.on ? 'on' : 'off'}`);
    } else if (b === 'button') {
      m.on = true; m.until = this.now + (seconds || BUTTON_TIME);
      this.log('world', `the button at ${where} was pressed`);
    } else if (b === 'pressure_plate') {
      if (how === 'toggle' || how === 'on' || how === 'off') {
        m.on = how === 'on' ? true : how === 'off' ? false : !m.on; delete m.until;
        this.log('world', `the pressure plate at ${where} is ${m.on ? 'held down' : 'released'}`);
      } else {
        m.on = true; m.until = this.now + (seconds || 0) + PLATE_TIME;
        this.log('world', `someone stepped on the pressure plate at ${where}`);
      }
    } else return false;
    this.redstoneDirty = true;
    this.version++;
    return true;
  }

  // Time passing: saplings grow, crops age, buttons and plates release,
  // daylight sensors follow the sun.
  tick() {
    this.grow();
    for (const k of this.crops) {
      const m = this.meta.get(k);
      const [x, y, z] = unkey(k);
      if (this.getBlock(x, y, z - 1) !== 'farmland') {
        const b = this.blocks.get(k);
        this.setBlock(x, y, z, null);
        this.log('world', `the ${b} at ${k} broke, it had no farmland`);
        continue;
      }
      let grew = false;
      while (m.age < 7 && this.now - m.since >= CROP_GROW_TIME) { m.age++; m.since += CROP_GROW_TIME; grew = true; }
      if (m.age >= 7) m.since = this.now;
      if (grew) this.version++;
    }
    let sensors = false;
    for (const k of this.redstoneKeys) {
      const m = this.meta.get(k);
      if (m && m.until != null && this.now >= m.until) { m.on = false; delete m.until; this.redstoneDirty = true; this.version++; }
      if (this.blocks.get(k) === 'daylight_sensor') sensors = true;
    }
    if (sensors) {
      const lv = this.daylightLevel();
      if (lv !== this._daylight) { this._daylight = lv; this.redstoneDirty = true; }
    }
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
    if (!this.isPassable(x, y, z)) return false;
    return !this.turtleAt(x, y, z);
  }

  // Sand and gravel above a removed block fall into the gap.
  settle(x, y, z) {
    let zz = z;
    while (true) {
      const above = this.getBlock(x, y, zz + 1);
      if (!above || !BLOCKS[above] || !BLOCKS[above].falls) return;
      const below = this.getBlock(x, y, zz);
      if ((below && !(BLOCKS[below] || {}).liquid) || this.turtleAt(x, y, zz)) return;
      this.blocks.delete(key(x, y, zz + 1));
      this.blocks.set(key(x, y, zz), above);
      this.meta.delete(key(x, y, zz));
      this.version++;
      zz++;
    }
  }

  // Turtles

  // equipped is { left, right } item names; a turtle without one is a
  // mining turtle (a diamond pickaxe on the right, as the scenarios
  // always assumed).
  addTurtle({ id, label, x, y, z, heading = 0, fuel = 1000, fuelLimit = 20000, slots = [], advanced = true, equipped }) {
    const t = {
      id, label: label || `Turtle ${id}`, x, y, z, heading, fuel, fuelLimit, advanced,
      selected: 1,
      slots: new Array(16).fill(null),
      equipped: { left: null, right: 'minecraft:diamond_pickaxe', ...(equipped || {}) },
      // animation state for the 3D view
      anim: { fromX: x, fromY: y, fromZ: z, fromHeading: heading, start: 0, duration: 0 },
    };
    slots.forEach((s, i) => { if (s && i < 16) t.slots[i] = makeStack(s); });
    this.turtles.set(id, t);
    this.redstoneDirty = true;
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

  _dirVector(t, dir) {
    if (dir === 'up') return [0, 0, 1];
    if (dir === 'down') return [0, 0, -1];
    const [dx, dy] = HEADINGS[t.heading];
    return [dx, dy, 0];
  }

  // Add items to the inventory like the game does: from the selected
  // slot on, the first slot that is empty or holds the same item takes
  // them, so an empty selected slot gets them even when a matching stack
  // sits elsewhere. Returns how many did not fit.
  _addItems(t, name, count, damage, data) {
    const order = [];
    for (let n = 0; n < 16; n++) order.push((t.selected - 1 + n) % 16);
    const moved = insertInto(t.slots, { name, damage, data }, count, order);
    this._inventoryChanged(t);
    return count - moved;
  }

  _takeOne(t) {
    const s = t.slots[t.selected - 1];
    s.count -= 1;
    if (s.count === 0) t.slots[t.selected - 1] = null;
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
    this.redstoneDirty = true;
    this.version++;
    return { ok: true };
  }

  _turn(t, right) {
    this._snapshot(t);
    t.heading = (t.heading + (right ? 1 : 3)) % 4;
    this._animate(t, this.actionDelay);
    this.redstoneDirty = true;
    this.version++;
    return { ok: true };
  }

  // What digging a block gives: crops by age, a drive its disk too.
  _drops(b, m) {
    const def = BLOCKS[b] || {};
    if (def.crop) {
      const extra = () => { let n = 0; for (let i = 0; i < 3; i++) if (this.random() < 0.5714) n++; return n; };
      if (m.age < 7) return [{ name: def.crop.seed, count: 1 }];
      if (b === 'wheat') return [{ name: 'minecraft:wheat', count: 1 }, { name: 'minecraft:wheat_seeds', count: 1 + extra() }];
      const out = [{ name: def.crop.produce, count: 1 + extra() }];
      if (b === 'potatoes' && this.random() < 0.02) out.push({ name: 'minecraft:poisonous_potato', count: 1 });
      return out;
    }
    if (b === 'wireless_modem') return [{ name: m.advanced ? 'computercraft:wireless_modem_advanced' : 'computercraft:wireless_modem_normal', count: 1 }];
    const out = def.drops ? [{ name: def.drops, count: 1 }] : [];
    if (b === 'disk_drive' && m.disk) out.push(m.disk);
    return out;
  }

  _give(t, stacks) {
    for (const s of stacks) {
      const left = this._addItems(t, s.name, s.count, s.damage, s.data);
      if (left) this.log(t.id, `inventory full, ${s.name} dropped on the ground`);
    }
  }

  // Tools the turtle digs with, left first as in CC: Tweaked.
  _tools(t, side) {
    const sides = side === 'left' || side === 'right' ? [side] : ['left', 'right'];
    return sides.map((s) => t.equipped[s]).filter((name) => name && itemInfo(name).tool && itemInfo(name).tool !== 'modem' && itemInfo(name).tool !== 'crafting');
  }

  _dig(t, dir, side) {
    const [x, y, z] = this._facing(t, dir);
    const b = this.getBlock(x, y, z);
    const def = BLOCKS[b] || {};
    if (!b || def.liquid) return { ok: false, reason: 'Nothing to dig here' };
    if (def.unbreakable) return { ok: false, reason: 'Unbreakable block detected' };
    const tools = this._tools(t, side);
    if (!tools.length) return { ok: false, reason: 'No tool to dig with' };
    let usable = false;
    for (const tool of tools) {
      const kind = itemInfo(tool).tool;
      // a hoe tills dirt in front of the turtle when there is air above,
      // the way a player's hoe does; from above the turtle is in the way
      if (kind === 'hoe' && (b === 'dirt' || b === 'grass')) {
        if (dir === 'forward' && !this.getBlock(x, y, z + 1)) {
          this.setBlock(x, y, z, 'farmland');
          this.log(t.id, `tilled ${b} into farmland`);
          return { ok: true };
        }
        continue;
      }
      if (kind === 'hoe' && !def.crop && !def.soft && b !== 'farmland') continue;
      if (kind === 'sword' && !def.soft) continue;
      usable = true;
      break;
    }
    if (!usable) return { ok: false, reason: 'Cannot break block with this tool' };
    if (def.computer) {
      const stacks = this.host ? this.host.digComputer(x, y, z) : null;
      if (stacks) { this._give(t, stacks); this.log(t.id, `dug ${b} ${dir === 'forward' ? 'ahead' : dir}`); return { ok: true }; }
    }
    const m = this.getMeta(x, y, z) || {};
    const drops = this._drops(b, m);
    this.setBlock(x, y, z, null);
    this._give(t, drops);
    this._dropUnsupported(x, y, z);
    this.settle(x, y, z);
    this.log(t.id, `dug ${b} ${dir === 'forward' ? 'ahead' : dir}`);
    return { ok: true };
  }

  // Modems stuck to a block that is gone are lost with it (in the game
  // they pop off as items; here they are logged and dropped).
  _dropUnsupported(x, y, z) {
    for (const [dx, dy, dz] of DIRS6) {
      const p = [x + dx, y + dy, z + dz];
      const m = this.getMeta(...p);
      if (this.getBlock(...p) === 'wireless_modem' && m && m.attached && m.attached[0] === x && m.attached[1] === y && m.attached[2] === z) {
        this.setBlock(...p, null);
        this.log('world', `the modem at ${p.join(',')} fell off`);
      }
    }
  }

  _place(t, dir) {
    const s = t.slots[t.selected - 1];
    if (!s) return { ok: false, reason: 'No items to place' };
    const info = itemInfo(s.name);
    const [x, y, z] = this._facing(t, dir);
    const here = this.getBlock(x, y, z);
    const hereDef = BLOCKS[here] || {};
    const replaceable = (!here || hereDef.liquid) && !this.turtleAt(x, y, z);
    const below = this.getBlock(x, y, z - 1);
    // an empty bucket scoops up a liquid source block
    if (s.name === 'minecraft:bucket') {
      const m = this.getMeta(x, y, z) || {};
      if (!hereDef.liquid || m.level) return { ok: false, reason: 'Cannot place item here' };
      this.setBlock(x, y, z, null);
      this._takeOne(t);
      this._give(t, [{ name: hereDef.bucket, count: 1 }]);
      this.log(t.id, `filled a bucket with ${here}`);
      return { ok: true };
    }
    if (info.liquid) {
      if (!replaceable) return { ok: false, reason: 'Cannot place item here' };
      this.setBlock(x, y, z, info.liquid, { level: 0 });
      t.slots[t.selected - 1] = { name: info.remainder, count: 1 };
      this._inventoryChanged(t);
      this.log(t.id, `poured out ${info.liquid}`);
      return { ok: true };
    }
    // seeds go on farmland only
    if (info.plant) {
      if (!replaceable || below !== 'farmland') return { ok: false, reason: 'Cannot place item here' };
      this.setBlock(x, y, z, info.plant, { age: 0 });
      this._takeOne(t);
      this._inventoryChanged(t);
      this.log(t.id, `planted ${info.plant}`);
      return { ok: true };
    }
    // a computer faces back at the turtle that placed it, starts off and
    // has an empty disk
    if (info.computer) {
      if (!replaceable) return { ok: false, reason: 'Cannot place block here' };
      if (!this.host) return { ok: false, reason: 'Cannot place item here' };
      const stack = { ...s, count: 1 };
      this._takeOne(t);
      this.host.placeComputer(x, y, z, (t.heading + 2) % 4, stack);
      this._inventoryChanged(t);
      this.log(t.id, `placed ${s.name}`);
      return { ok: true };
    }
    // a modem goes into the free space and sticks to the block beyond it
    if (info.modem) {
      if (!replaceable) return { ok: false, reason: 'Cannot place item here' };
      const [dx, dy, dz] = this._dirVector(t, dir);
      const beyond = [x + dx, y + dy, z + dz];
      const bb = this.getBlock(...beyond);
      if (!bb || (BLOCKS[bb] || {}).passable) return { ok: false, reason: 'Cannot place item here' };
      this.setBlock(x, y, z, 'wireless_modem', { attached: beyond, advanced: info.modem === 'advanced' });
      this._takeOne(t);
      this._inventoryChanged(t);
      this.log(t.id, `placed a wireless modem on the ${bb} at ${beyond.join(',')}`);
      return { ok: true };
    }
    if (!info.block) return { ok: false, reason: 'Cannot place item here' };
    if (!replaceable) return { ok: false, reason: 'Cannot place block here' };
    if (BLOCKS[info.block].needsSupport && (!below || (BLOCKS[below] || {}).passable || BLOCKS[below].needsSupport)) {
      return { ok: false, reason: 'Cannot place item here' };
    }
    const meta = {};
    if (['chest', 'door', 'lever', 'button', 'disk_drive'].includes(info.block)) meta.facing = (t.heading + 2) % 4;
    if (info.block === 'rail') meta.shape = t.heading % 2 === 0 ? 'north_south' : 'east_west';
    this.setBlock(x, y, z, info.block, Object.keys(meta).length ? meta : undefined);
    this._takeOne(t);
    this._inventoryChanged(t);
    this.log(t.id, `placed ${info.block}`);
    return { ok: true };
  }

  _drop(t, dir, count) {
    const s = t.slots[t.selected - 1];
    if (!s) return { ok: false, reason: 'No items to drop' };
    const n = Math.min(count == null ? s.count : count, s.count);
    const [x, y, z] = this._facing(t, dir);
    // a floppy goes into a disk drive
    if (this.getBlock(x, y, z) === 'disk_drive') {
      const m = this.getMeta(x, y, z);
      if (m.disk || !itemInfo(s.name).disk || n < 1) return { ok: false, reason: 'No space for items' };
      const disk = makeStack({ ...s, count: 1 });
      if (disk.data.diskId == null) disk.data.diskId = this.nextDiskId++;
      m.disk = disk;
      this._takeOne(t);
      this._inventoryChanged(t);
      this.log(t.id, `put ${s.name} in the disk drive`);
      return { ok: true };
    }
    const slots = this.getContainer(x, y, z);
    if (slots) {
      // like a hopper: stacks that are already there first, then empty slots
      const all = slots.map((_, i) => i);
      let moved = insertInto(slots, s, n, all.filter((i) => slots[i]));
      moved += insertInto(slots, s, n - moved, all);
      if (moved === 0) return { ok: false, reason: 'No space for items' };
      s.count -= moved;
      if (s.count === 0) t.slots[t.selected - 1] = null;
      this._inventoryChanged(t);
      this.log(t.id, `put ${moved} ${s.name} in the chest`);
      return { ok: true };
    }
    if (!this.isPassable(x, y, z)) return { ok: false, reason: 'No space for items' };
    s.count -= n;
    if (s.count === 0) t.slots[t.selected - 1] = null;
    this._inventoryChanged(t);
    this.log(t.id, `dropped ${n} ${s.name} on the ground (lost)`);
    return { ok: true };
  }

  _suck(t, dir, count) {
    const [x, y, z] = this._facing(t, dir);
    if (this.getBlock(x, y, z) === 'disk_drive') {
      const m = this.getMeta(x, y, z);
      if (!m.disk) return { ok: false, reason: 'No items to take' };
      if (this._addItems(t, m.disk.name, 1, m.disk.damage, m.disk.data)) return { ok: false, reason: 'No space for items' };
      m.disk = null;
      this.version++;
      this.log(t.id, 'took the disk from the disk drive');
      return { ok: true };
    }
    const slots = this.getContainer(x, y, z);
    if (!slots) return { ok: false, reason: 'No items to take' };
    const i = slots.findIndex((c) => c);
    if (i < 0) return { ok: false, reason: 'No items to take' };
    const c = slots[i];
    const n = Math.min(count == null ? 64 : count, c.count);
    const left = this._addItems(t, c.name, n, c.damage, c.data);
    const moved = n - left;
    if (moved === 0) return { ok: false, reason: 'No space for items' };
    c.count -= moved;
    if (c.count === 0) slots[i] = null;
    this.version++;
    this.log(t.id, `took ${moved} ${c.name} from the chest`);
    return { ok: true };
  }

  // turtle.craft: the grid is slots 1-3, 5-7 and 9-11, every other
  // slot must be empty, and a crafting table must be equipped. Crafts
  // up to limit times (0 only checks); the results go in from the
  // selected slot on, and what does not fit is dropped.
  _craft(t, limit) {
    if (t.equipped.left !== 'minecraft:crafting_table' && t.equipped.right !== 'minecraft:crafting_table') {
      return { ok: false, reason: 'No crafting table' };
    }
    const n = limit == null ? 64 : limit;
    if (n < 0 || n > 64) return { ok: false, reason: 'Crafting count must be between 0 and 64' };
    const gridSlots = [0, 1, 2, 4, 5, 6, 8, 9, 10];
    for (let i = 0; i < 16; i++) if (!gridSlots.includes(i) && t.slots[i]) return { ok: false, reason: 'No matching recipes' };
    const grid = [0, 1, 2].map((r) => [0, 1, 2].map((c) => (t.slots[gridSlots[r * 3 + c]] || {}).name || null));
    const recipe = matchRecipe(grid);
    if (!recipe) return { ok: false, reason: 'No matching recipes' };
    if (n === 0) return { ok: true };
    const k = Math.min(n, ...gridSlots.filter((i) => t.slots[i]).map((i) => t.slots[i].count));
    for (const i of gridSlots) {
      const s = t.slots[i];
      if (s) { s.count -= k; if (s.count === 0) t.slots[i] = null; }
    }
    const total = k * recipe.count;
    const order = [];
    for (let i = 0; i < 16; i++) order.push((t.selected - 1 + i) % 16);
    let moved = insertInto(t.slots, { name: recipe.out }, total, order.filter((i) => t.slots[i]));
    moved += insertInto(t.slots, { name: recipe.out }, total - moved, order);
    this._inventoryChanged(t);
    this.log(t.id, `crafted ${total} ${recipe.out}` + (moved < total ? ` (${total - moved} dropped, no room)` : ''));
    return { ok: true };
  }

  // Swap the selected slot with the upgrade on a side, like
  // turtle.equipLeft. Only tools, modems and a crafting table fit.
  _equip(t, side) {
    const s = t.slots[t.selected - 1];
    if (s && (!itemInfo(s.name).tool || s.count < 1)) return [false, 'Not a valid upgrade'];
    const old = t.equipped[side];
    if (s) { t.equipped[side] = s.name; this._takeOne(t); } else t.equipped[side] = null;
    if (old) this._give(t, [{ name: old, count: 1 }]);
    this._inventoryChanged(t);
    if (this.host) this.host.equipmentChanged(t.id, side, t.equipped[side]);
    this.log(t.id, `equipped ${t.equipped[side] || 'nothing'} on the ${side}`);
    return [true];
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
      case 'dig': return this._dig(t, 'forward', arg);
      case 'digUp': return this._dig(t, 'up', arg);
      case 'digDown': return this._dig(t, 'down', arg);
      case 'place': return this._place(t, 'forward');
      case 'placeUp': return this._place(t, 'up');
      case 'placeDown': return this._place(t, 'down');
      case 'drop': return this._drop(t, 'forward', arg);
      case 'dropUp': return this._drop(t, 'up', arg);
      case 'dropDown': return this._drop(t, 'down', arg);
      case 'suck': return this._suck(t, 'forward', arg);
      case 'suckUp': return this._suck(t, 'up', arg);
      case 'suckDown': return this._suck(t, 'down', arg);
      case 'craft': return this._craft(t, arg);
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
        return !this.isPassable(x, y, z);
      }
      case 'inspect': case 'inspectUp': case 'inspectDown': {
        const [x, y, z] = this._facing(t, q === 'inspect' ? 'forward' : q === 'inspectUp' ? 'up' : 'down');
        const info = this.blockInfo(x, y, z);
        if (!info) return [false, 'No block to inspect'];
        return [true, info];
      }
      case 'getSelectedSlot': return t.selected;
      case 'select': {
        const slot = Math.floor(a);
        if (slot < 1 || slot > 16) return [false, 'Slot number 1-16 expected'];
        t.selected = slot; this.version++; return [true];
      }
      case 'getItemCount': { const s = t.slots[(a || t.selected) - 1]; return s ? s.count : 0; }
      case 'getItemSpace': { const s = t.slots[(a || t.selected) - 1]; return s ? maxStack(s) - s.count : 64; }
      case 'getItemDetail': {
        const s = t.slots[(a || t.selected) - 1];
        return s ? itemDetail(s, b) : null;
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
        // a lava bucket leaves its bucket behind
        if (info.remainder) this._give(t, [{ name: info.remainder, count: burn }]);
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
        if (dest && !sameItem(dest, from)) return false;
        const moved = Math.min(n, maxStack(from) - (dest ? dest.count : 0));
        if (moved <= 0) return false;
        if (dest) dest.count += moved; else { t.slots[to - 1] = { name: from.name, count: moved, damage: from.damage }; if (from.data) t.slots[to - 1].data = from.data; }
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
      case 'equipLeft': return this._equip(t, 'left');
      case 'equipRight': return this._equip(t, 'right');
      case 'getEquippedLeft': case 'getEquippedRight': {
        const name = t.equipped[q === 'getEquippedLeft' ? 'left' : 'right'];
        return name ? itemDetail({ name, count: 1 }, true) : null;
      }
      default: return null;
    }
  }

  // Put items into a turtle from outside, like a player would. With a
  // slot the items go into that slot only, if it is empty or holds the
  // same item. Returns how many fitted. data is a floppy's contents.
  give(id, name, count, slot, data) {
    const t = this.turtles.get(id);
    if (!t) return 0;
    if (!data && itemInfo(name).disk) data = makeStack({ name }).data;
    let fitted;
    if (slot) {
      const fitted1 = insertInto(t.slots, { name, data }, count, [slot - 1]);
      if (fitted1 <= 0) { this.log(id, `slot ${slot} holds something else or is full, nothing given`); return 0; }
      fitted = fitted1;
      this._inventoryChanged(t);
    } else {
      fitted = count - this._addItems(t, name, count, undefined, data);
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
    if (!type) { this._dropUnsupported(x, y, z); this.settle(x, y, z); }
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
