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

function tree(world, x, y, base) {
  for (let z = base; z < base + 4; z++) world.setBlock(x, y, z, 'log');
  for (let dx = -2; dx <= 2; dx++) for (let dy = -2; dy <= 2; dy++) for (let dz = 2; dz <= 4; dz++) {
    if (Math.abs(dx) + Math.abs(dy) + (dz - 2) <= 3 && !(dx === 0 && dy === 0 && dz < 4)) {
      if (!world.getBlock(x + dx, y + dy, base + dz)) world.setBlock(x + dx, y + dy, base + dz, 'leaves');
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
const torches = (n) => ({ name: 'minecraft:torch', count: n });

export const SCENARIOS = {
  control: {
    name: 'Turtle control',
    description: 'A computer with a 3x2 advanced monitor running turtlecontrol, and two turtles running turtleagent. Touch the monitor panel to drive them.',
    build(world) {
      ground(world, -10, 12, -8, 12, 0, 8);
      world.setBlock(-1, 0, 1, 'chest');
      world.setBlock(-1, 4, 1, 'chest');
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
    ],
  },

  quarry: {
    name: 'Quarry',
    description: 'One turtle on the ground with a chest on its left. Type a command in its screen, for example: quarry 4 4 3',
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
    description: 'A turtle underground with a chest behind it. Try: stripmine 3 2 12 true 5',
    build(world) {
      ground(world, -8, 24, -8, 24, 6, 12);
      for (let y = -1; y <= 1; y++) for (let x = -2; x <= 2; x++) for (let z = 1; z <= 2; z++) world.setBlock(x, y, z, null);
      world.setBlock(0, -2, 1, 'chest');
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
