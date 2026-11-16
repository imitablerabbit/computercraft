// Run a scenario without a browser and print what happened.
//
//   cd sim && npm install          (once, fetches fengari)
//   node headless.mjs quarry "quarry 3 3 2" 90
//
// Arguments: scenario key, command to run on the first turtle (optional,
// "" for none), simulated seconds to run (default 60). Prints every
// screen, the turtles and chests, and the log.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import fengari from 'fengari';
import { Simulation } from './js/simulation.js';
import { SCENARIOS } from './js/scenarios.js';
import { HEADING_NAMES } from './js/world.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..');

function loadFiles() {
  const files = new Map();
  const walk = (dir) => {
    for (const name of fs.readdirSync(dir)) {
      if (name.startsWith('.') || name === 'sim' || name === '__pycache__') continue;
      const full = path.join(dir, name);
      if (fs.statSync(full).isDirectory()) walk(full);
      else if (name.endsWith('.lua')) files.set(path.relative(repo, full).split(path.sep).join('/'), fs.readFileSync(full, 'latin1'));
    }
  };
  walk(repo);
  return files;
}

const [key = 'quarry', run, secondsArg] = process.argv.slice(2);
const scenario = SCENARIOS[key];
if (!scenario) {
  console.error(`unknown scenario ${key}; one of: ${Object.keys(SCENARIOS).join(', ')}`);
  process.exit(1);
}
const seconds = parseFloat(secondsArg || '60');
const computers = scenario.computers.map((c) => ({ ...c }));
if (run !== undefined) {
  const turtle = computers.find((c) => c.kind === 'turtle') || computers[0];
  turtle.autorun = run;
}

const sim = new Simulation({ fengari, files: loadFiles(), biosSource: fs.readFileSync(path.join(here, 'lua/bios.lua'), 'latin1') });
sim.load({ ...scenario, computers });
sim.runUntil(seconds);

for (const c of sim.computers.values()) {
  for (const [side, t] of c.terminals) {
    console.log(`=== ${side === 'native' ? '' : 'monitor ' + side + ' of '}${c.label || c.kind} #${c.id} (${t.width}x${t.height}) ${c.state}${c.error ? ': ' + c.error : ''} ===`);
    console.log(t.dump().split('\n').map((l) => '|' + l + '|').join('\n'));
  }
}
for (const t of sim.world.turtles.values()) {
  const items = t.slots.map((s, i) => s && `${i + 1}:${s.name.replace(/^minecraft:/, '')}x${s.count}`).filter(Boolean).join(' ');
  console.log(`turtle #${t.id} ${t.label} at (${t.x}, ${t.y}, ${t.z}) facing ${HEADING_NAMES[t.heading]}, fuel ${t.fuel}, slot ${t.selected}: ${items || 'empty'}`);
}
for (const [k, slots] of sim.world.containers) {
  console.log(`chest ${k}: ${slots.filter(Boolean).map((s) => `${s.name.replace(/^minecraft:/, '')}x${s.count}`).join(' ') || 'empty'}`);
}
console.log('--- log ---');
for (const l of sim.logs) console.log(`${l.at.toFixed(1).padStart(6)} #${l.computer} ${l.text}`);
