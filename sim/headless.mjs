// Run a scenario without a browser and print what happened.
//
//   cd sim && npm install          (once, fetches fengari)
//   node headless.mjs quarry "quarry 3 3 2" 90
//
// Arguments: scenario key, command to run on the first turtle (optional,
// "" for none), simulated seconds to run (default 60). Prints every
// screen, the turtles and chests, and the log. The key is a built-in
// scenario, a scenario file's name in sim/scenarios (quarry-file for
// sim/scenarios/quarry-file.scn) or the path to a .scn file.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import fengari from 'fengari';
import { Simulation } from './js/simulation.js';
import { SCENARIOS } from './js/scenarios.js';
import { HEADING_NAMES } from './js/world.js';
import { parseScenario } from './js/scenariofile.js';

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
// A built-in scenario, else sim/scenarios/<key>.scn, else a .scn path.
function findScenario(k) {
  if (SCENARIOS[k]) return SCENARIOS[k];
  const file = [path.join(here, 'scenarios', `${k}.scn`), path.resolve(k)].find((f) => f.endsWith('.scn') && fs.existsSync(f));
  if (!file) return null;
  try {
    return parseScenario(fs.readFileSync(file, 'utf8'), { key: path.basename(file, '.scn'), file: path.relative(process.cwd(), file) });
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
}
const scenario = findScenario(key);
if (!scenario) {
  const files = fs.existsSync(path.join(here, 'scenarios')) ? fs.readdirSync(path.join(here, 'scenarios')).filter((f) => f.endsWith('.scn')).map((f) => f.slice(0, -4)) : [];
  console.error(`unknown scenario ${key}; one of: ${[...Object.keys(SCENARIOS), ...files].join(', ')}, or a .scn file`);
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
