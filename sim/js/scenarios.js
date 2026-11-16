import { tree } from './world.js';

// Ready made worlds. Each scenario builds the blocks and lists the
// computers to boot, with what they should run first.

function ground(world, x0, x1, y0, y1, top, depth, { ores = true, pockets = true } = {}) {
  let seed = 7;
  const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };
  for (let x = x0; x <= x1; x++) {
    for (let y = y0; y <= y1; y++) {
      for (let z = top; z > top - depth; z--) {
        let type = 'stone';
        const d = top - z;
        if (d === 0) type = 'grass';
        else if (d <= 2) type = 'dirt';
        else if (ores && rnd() < 0.08) type = 'coal_ore';
        else if (ores && d > 4 && rnd() < 0.04) type = 'iron_ore';
        else if (pockets && rnd() < 0.05) type = 'gravel';
        world.setBlock(x, y, z, type);
      }
      world.setBlock(x, y, top - depth, 'bedrock');
    }
  }
}

function hill(world, x0, x1, y0, y1, base, height) {
  for (let x = x0; x <= x1; x++) {
    for (let y = y0; y <= y1; y++) {
      for (let z = base; z < base + height; z++) {
        world.setBlock(x, y, z, z === base + height - 1 ? 'grass' : 'dirt');
      }
    }
  }
}


// A 3x2 monitor standing on the ground facing south at (x, y), with the
// computer beside it.
function monitorBlocks(x, y, z, blocksW, blocksH) {
  const blocks = [];
  for (let i = 0; i < blocksW; i++) for (let j = 0; j < blocksH; j++) blocks.push({ x: x + i, y, z: z + j });
  return blocks;
}

const coal = (n) => ({ name: 'minecraft:coal', count: n });

// GPS hosts' positions (ours: x east, y north, z up), far enough apart
// and not in one plane, so four answers fix a position.
const GPS_HOSTS = [[-6, -6, 6], [6, -6, 10], [-6, 6, 14], [6, 6, 3]];
const torches = (n) => ({ name: 'minecraft:torch', count: n });

export const SCENARIOS = {
  control: {
    name: 'Turtle control',
    description: 'A computer with a 3x2 advanced monitor running turtlecontrol and three turtles running turtleagent. Runner has almost no fuel: start it on a job, watch the alert, then Give it coal.',
    build(world) {
      ground(world, -10, 12, -8, 12, 0, 8);
      world.setBlock(-1, 0, 1, 'chest');
      world.setBlock(-1, 4, 1, 'chest');
      world.setBlock(-1, 8, 1, 'chest');
      tree(world, 8, 8, 1);
      tree(world, 10, 4, 1);
    },
    computers: [
      {
        id: 1, label: 'Control', kind: 'computer', advanced: true, pos: { x: -5, y: -4, z: 1 },
        peripherals: {
          right: { type: 'monitor', advanced: true, blocksW: 3, blocksH: 2, blocks: monitorBlocks(-4, -4, 1, 3, 2) },
          top: { type: 'modem' },
        },
        autorun: 'turtlecontrol',
      },
      {
        id: 7, label: 'Digger', kind: 'turtle', advanced: true, pos: { x: 0, y: 0, z: 1 }, heading: 0, fuel: 1200,
        slots: [coal(12), torches(32), { name: 'minecraft:oak_sapling', count: 4 }],
        peripherals: { left: { type: 'modem' } },
        autorun: 'turtleagent',
      },
      {
        id: 8, label: 'Lumber', kind: 'turtle', advanced: true, pos: { x: 0, y: 4, z: 1 }, heading: 0, fuel: 400,
        slots: [coal(5), { name: 'minecraft:oak_sapling', count: 16 }],
        peripherals: { left: { type: 'modem' } },
        autorun: 'turtleagent',
      },
      {
        id: 9, label: 'Runner', kind: 'turtle', advanced: true, pos: { x: 0, y: 8, z: 1 }, heading: 0, fuel: 6,
        slots: [],
        peripherals: { left: { type: 'modem' } },
        autorun: 'turtleagent',
      },
    ],
  },

  quarry: {
    name: 'Quarry',
    description: 'One turtle on the ground with a chest on its left. Type a command in its screen, for example: quarry 4 4 3   (or from the middle of the edge with the chest behind: quarry 5 4 3 behind middle, after moving the chest)',
    build(world) {
      ground(world, -6, 10, -6, 10, 0, 9);
      world.setBlock(-1, 0, 1, 'chest');
    },
    computers: [
      {
        id: 3, label: 'Miner', kind: 'turtle', advanced: true, pos: { x: 0, y: 0, z: 1 }, heading: 0, fuel: 800,
        slots: [coal(20)],
        peripherals: { left: { type: 'modem' } },
        autorun: '',
      },
    ],
  },

  reconstruct: {
    name: 'Reconstruct',
    description: 'A turtle with a chest of netherrack behind it, an empty chest on its right and redstone on its left leading to an atomic reconstructor aimed at the block in front of it. Try: reconstruct   (or reconstruct behind right left 2)',
    build(world) {
      ground(world, -6, 6, -6, 8, 0, 4, { ores: false, pockets: false });
      world.setBlock(0, -1, 1, 'chest');
      world.fillContainer(0, -1, 1, [{ name: 'minecraft:netherrack', count: 64 }, { name: 'minecraft:netherrack', count: 64 }, { name: 'minecraft:netherrack', count: 24 }]);
      world.setBlock(1, 0, 1, 'chest');
      world.setBlock(-1, 0, 1, 'redstone_wire');
      world.setBlock(-1, 1, 1, 'reconstructor', { facing: 1 });
    },
    computers: [
      {
        id: 5, label: 'Smelter', kind: 'turtle', advanced: true, pos: { x: 0, y: 0, z: 1 }, heading: 0, fuel: 100,
        slots: [],
        peripherals: { left: { type: 'modem' } },
        autorun: '',
      },
    ],
  },

  flatten: {
    name: 'Flatten',
    description: 'A hill in front of the turtle. Try: flatten 5 4 3',
    build(world) {
      ground(world, -6, 12, -6, 12, 0, 5, { ores: false, pockets: false });
      hill(world, 0, 4, 0, 3, 1, 3);
      world.setBlock(0, 0, 1, null);
      world.setBlock(-1, 0, 1, 'chest');
    },
    computers: [
      {
        id: 4, label: 'Leveller', kind: 'turtle', advanced: true, pos: { x: 0, y: 0, z: 1 }, heading: 0, fuel: 600,
        slots: [coal(8)],
        peripherals: {},
        autorun: '',
      },
    ],
  },

  stripmine: {
    name: 'Strip mine',
    description: 'A turtle underground with a chest behind it. Try: stripmine 3 2 12 true 5 behind',
    build(world) {
      ground(world, -8, 24, -8, 24, 6, 12);
      for (let y = -1; y <= 1; y++) for (let x = -2; x <= 2; x++) for (let z = 1; z <= 2; z++) world.setBlock(x, y, z, null);
      world.setBlock(0, -1, 1, 'chest');
    },
    computers: [
      {
        id: 5, label: 'Stripper', kind: 'turtle', advanced: true, pos: { x: 0, y: 0, z: 1 }, heading: 0, fuel: 1500,
        slots: [coal(16), torches(40)],
        peripherals: { left: { type: 'modem' } },
        autorun: '',
      },
    ],
  },

  inventory: {
    name: 'Inventory viewer',
    description: 'An advanced turtle with assorted items running inventorygui. Click slots on its screen.',
    build(world) {
      ground(world, -4, 4, -4, 4, 0, 3, { ores: false, pockets: false });
      world.setBlock(1, 0, 1, 'chest');
      world.fillContainer(1, 0, 1, [coal(30), { name: 'minecraft:oak_log', count: 10 }]);
    },
    computers: [
      {
        id: 6, label: 'Packrat', kind: 'turtle', advanced: true, pos: { x: 0, y: 0, z: 1 }, heading: 1, fuel: 350,
        slots: [coal(12), { name: 'minecraft:cobblestone', count: 64 }, { name: 'minecraft:stone_pickaxe', count: 1, damage: 3 }, null,
          torches(7), { name: 'minecraft:oak_log', count: 3 }, { name: 'minecraft:gravel', count: 20 }, null,
          null, null, null, null, null, null, null, { name: 'minecraft:iron_ingot', count: 3 }],
        peripherals: {},
        autorun: 'inventorygui',
      },
    ],
  },

  pocket: {
    name: 'Pocket control',
    description: 'An advanced pocket computer running turtlecontrol on its own 26x20 screen, with two agent turtles. Click its screen tab to drive them.',
    build(world) {
      ground(world, -8, 10, -6, 10, 0, 6);
      world.setBlock(-1, 0, 1, 'chest');
      world.setBlock(-1, 4, 1, 'chest');
    },
    computers: [
      { id: 12, label: 'Pocket', kind: 'pocket', advanced: true, peripherals: { back: { type: 'modem' } }, autorun: 'turtlecontrol' },
      { id: 7, label: 'Digger', kind: 'turtle', advanced: true, pos: { x: 0, y: 0, z: 1 }, heading: 0, fuel: 1200, slots: [coal(12), torches(32)], peripherals: { left: { type: 'modem' } }, autorun: 'turtleagent' },
      { id: 8, label: 'Lumber', kind: 'turtle', advanced: true, pos: { x: 0, y: 4, z: 1 }, heading: 0, fuel: 400, slots: [coal(5), { name: 'minecraft:oak_sapling', count: 16 }], peripherals: { left: { type: 'modem' } }, autorun: 'turtleagent' },
    ],
  },

  blank: {
    name: 'Blank',
    description: 'One advanced turtle with a modem on flat ground and a shell prompt.',
    build(world) {
      ground(world, -8, 8, -8, 8, 0, 4, { ores: false, pockets: false });
    },
    computers: [
      {
        id: 2, label: null, kind: 'turtle', advanced: true, pos: { x: 0, y: 0, z: 1 }, heading: 0, fuel: 1000,
        slots: [coal(10), { name: 'minecraft:cobblestone', count: 32 }],
        peripherals: { left: { type: 'modem' } },
        autorun: '',
      },
    ],
  },
};

// Scenarios for the newer parts of the simulator: inventories over a
// wired network, redstone in and out, crops, lava, gps and machines.

function flat(world, r, top = 0) {
  ground(world, -r, r, -r, r, top, 3, { ores: false, pockets: false });
}

// A row of networking cable blocks, only for looks: what joins a block
// to a wired network is its meta network.
function cableLine(world, x0, y0, x1, y1, z) {
  for (let x = Math.min(x0, x1); x <= Math.max(x0, x1); x++) {
    for (let y = Math.min(y0, y1); y <= Math.max(y0, y1); y++) if (!world.getBlock(x, y, z)) world.setBlock(x, y, z, 'cable');
  }
}

const item = (name, count) => ({ name: `minecraft:${name}`, count });

Object.assign(SCENARIOS, {
  storage: {
    name: 'Storage network',
    description: 'A computer with a wired modem on its back, networked to six chests of assorted items (minecraft:chest_0..5), an empty output chest (minecraft:chest_6) and a 3x2 monitor (monitor_0). Try peripheral.getNames() and pushItems between chests.',
    build(world) {
      flat(world, 8);
      const stock = [
        [item('cobblestone', 64), item('cobblestone', 40), item('dirt', 33), item('gravel', 12)],
        [item('coal', 50), item('charcoal', 9), item('oak_log', 24), item('oak_planks', 64)],
        [item('iron_ingot', 17), item('raw_iron', 30), item('gold_nugget', 8), item('quartz', 21)],
        [item('torch', 64), item('torch', 12), item('sand', 40), item('glass', 16)],
        [item('wheat_seeds', 20), item('wheat', 15), item('carrot', 7), item('potato', 11)],
        [item('redstone', 30), item('rail', 16), item('stone_bricks', 48), item('bucket', 3)],
      ];
      stock.forEach((items, i) => {
        world.setBlock(-3 + i, -3, 1, 'chest', { network: 'storage' });
        world.fillContainer(-3 + i, -3, 1, items);
      });
      world.setBlock(0, 3, 1, 'chest', { network: 'storage' });
      cableLine(world, 0, -1, 0, -2, 1);
      cableLine(world, -3, -2, 2, -2, 1);
      cableLine(world, 1, 0, 1, 2, 1);
    },
    computers: [
      {
        id: 1, label: 'Storage', kind: 'computer', advanced: true, pos: { x: 0, y: 0, z: 1 }, heading: 0,
        peripherals: {
          back: { type: 'modem', wired: true, network: 'storage' },
          monitor_0: { type: 'monitor', advanced: true, blocksW: 3, blocksH: 2, blocks: monitorBlocks(2, 2, 1, 3, 2) },
        },
        autorun: '',
      },
    ],
  },

  redstone: {
    name: 'Redstone',
    description: 'A computer with a lever on its left, a lamp on its right, an iron door behind, a button on top and wire in front to a far lamp; bundled cable under it runs to a second computer. A pressure plate beside the door opens it too. The timeline flips the lever at 5 s and 20 s, presses the button at 10 s and steps on the plate at 15 s. Use the Click control to do it yourself.',
    build(world) {
      flat(world, 7);
      world.setBlock(-1, 0, 1, 'lever');
      world.setBlock(1, 0, 1, 'redstone_lamp');
      world.setBlock(0, -1, 1, 'door', { facing: 2 });
      world.setBlock(0, 0, 2, 'button');
      world.setBlock(0, 1, 1, 'redstone_wire');
      world.setBlock(0, 2, 1, 'redstone_wire');
      world.setBlock(0, 3, 1, 'redstone_lamp');
      world.setBlock(-1, -1, 1, 'pressure_plate');
      for (let x = 0; x <= 4; x++) world.setBlock(x, 0, 0, 'bundled_cable');
    },
    computers: [
      { id: 1, label: 'Switchboard', kind: 'computer', advanced: true, pos: { x: 0, y: 0, z: 1 }, heading: 0, peripherals: {}, autorun: '' },
      { id: 2, label: 'Listener', kind: 'computer', advanced: true, pos: { x: 4, y: 0, z: 1 }, heading: 0, peripherals: {}, autorun: '' },
    ],
    timeline: [
      { at: 5, action: 'toggle', pos: { x: -1, y: 0, z: 1 } },
      { at: 10, action: 'press', pos: { x: 0, y: 0, z: 2 } },
      { at: 15, action: 'step', pos: { x: -1, y: -1, z: 1 }, seconds: 2 },
      { at: 20, action: 'toggle', pos: { x: -1, y: 0, z: 1 } },
    ],
  },

  farm: {
    name: 'Farm',
    description: 'A 9x9 field of wheat, carrots and potatoes at mixed ages around a water block, with a turtle hovering over the corner crop and a chest behind it. Crops age a step every 5 s; dig mature ones from above with digDown and replant with placeDown.',
    build(world) {
      flat(world, 7);
      const crops = ['wheat', 'carrots', 'potatoes'];
      for (let x = 1; x <= 9; x++) {
        for (let y = 1; y <= 9; y++) {
          world.setBlock(x - 5, y - 5, 0, 'farmland');
          if (x === 5 && y === 5) continue;
          world.setBlock(x - 5, y - 5, 1, crops[Math.floor((x - 1) / 3)], { age: (x * 3 + y * 5) % 8 });
        }
      }
      world.setBlock(0, 0, 0, 'water');
      world.setBlock(-4, -5, 1, 'stone');
      world.setBlock(-4, -5, 2, 'chest');
    },
    computers: [
      {
        id: 3, label: 'Farmer', kind: 'turtle', advanced: true, pos: { x: -4, y: -4, z: 2 }, heading: 0, fuel: 500,
        slots: [item('wheat_seeds', 32), item('carrot', 16), item('potato', 16), coal(16)],
        peripherals: { left: { type: 'modem' } },
        autorun: '',
      },
    ],
  },

  lava: {
    name: 'Lava',
    description: 'A 3x3 lava pool in front of a turtle with 16 empty buckets and next to no fuel. Move over the pool, turtle.placeDown() with a bucket to scoop a source, then turtle.refuel(): each lava bucket is 1000 fuel and leaves its bucket.',
    build(world) {
      flat(world, 6);
      for (let x = -1; x <= 1; x++) for (let y = 2; y <= 4; y++) world.setBlock(x, y, 0, 'lava');
    },
    computers: [
      {
        id: 4, label: 'Scooper', kind: 'turtle', advanced: true, pos: { x: 0, y: 1, z: 1 }, heading: 0, fuel: 20,
        slots: [item('bucket', 16)],
        peripherals: { left: { type: 'modem' } },
        autorun: '',
      },
    ],
  },

  gps: {
    name: 'GPS',
    description: 'Four computers on pillars at different heights, each with a wireless modem on top, running gps host with their own Minecraft coordinates (x, height, -y here). The turtle can gps locate: try gps locate in its shell.',
    build(world) {
      flat(world, 8);
      for (const [x, y, z] of GPS_HOSTS) for (let h = 1; h < z; h++) world.setBlock(x, y, h, 'stone_bricks');
    },
    computers: [
      ...GPS_HOSTS.map(([x, y, z], i) => ({
        id: 20 + i, label: `GPS ${i + 1}`, kind: 'computer', advanced: false, pos: { x, y, z }, heading: 0,
        peripherals: { top: { type: 'modem' } },
        // gps host takes Minecraft coordinates: x, height, south
        autorun: `gps host ${x} ${z} ${-y}`,
      })),
      { id: 2, label: 'Finder', kind: 'turtle', advanced: true, pos: { x: 0, y: 0, z: 1 }, heading: 0, fuel: 1000, slots: [coal(8)], peripherals: { left: { type: 'modem' } }, autorun: '' },
    ],
  },

  gpsdeploy: {
    name: 'GPS deploy',
    description: 'A turtle on open ground with 4 computers, 4 wireless modems, a disk drive and an empty floppy, nothing else. Computers it places start off with an empty disk and face it; a modem placed through a gap sticks to the computer behind it, a floppy dropped into a drive mounts as disk/ and the computer runs disk/startup.lua when turned on.',
    build(world) {
      flat(world, 8);
    },
    computers: [
      {
        id: 2, label: 'Deployer', kind: 'turtle', advanced: true, pos: { x: 0, y: 0, z: 1 }, heading: 0, fuel: 2000,
        slots: [
          { name: 'computercraft:computer_normal', count: 4 }, { name: 'computercraft:wireless_modem_normal', count: 4 },
          { name: 'computercraft:disk_drive', count: 1 }, { name: 'computercraft:disk', count: 1 },
        ],
        peripherals: { left: { type: 'modem' } },
        autorun: '',
      },
    ],
  },

  machines: {
    name: 'Machines',
    description: 'A computer with an energy cell on its left (energy_storage) and a wired modem on its back, networked to a lava tank (fluid_storage) and a second energy cell. Their contents drift slowly: try getEnergy(), getEnergyCapacity() and tanks().',
    build(world) {
      flat(world, 6);
      world.setBlock(-1, 0, 1, 'energy_cell');
      world.setBlock(-1, -3, 1, 'tank', { network: 'factory' });
      world.setBlock(1, -3, 1, 'energy_cell', { network: 'factory' });
      cableLine(world, 0, -1, 0, -3, 1);
    },
    computers: [
      {
        id: 1, label: 'Monitor', kind: 'computer', advanced: true, pos: { x: 0, y: 0, z: 1 }, heading: 0,
        peripherals: { back: { type: 'modem', wired: true, network: 'factory' } },
        autorun: '',
      },
    ],
  },
});
