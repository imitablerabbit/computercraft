// Run the repo's tests without a browser:
//
//   cd sim && npm install          (once, fetches fengari)
//   node test.mjs                  everything
//   node test.mjs quarry           only the tests whose name has "quarry"
//
// Three kinds of test run here:
//   - the Lua unit tests in tests/**/*_test.lua, by booting a simulated
//     computer that runs the `test` program and reading its summary
//     (with a filter, only the test files whose path has it);
//   - the scenario file format: every sim/scenarios/*.scn parses, is in
//     index.json, and the converted examples build the same world as
//     the scenarios.js originals;
//   - scenario checks: the check blocks in tests/scenarios/*.check and
//     in the .scn files. Each loads a scenario, runs a command on a
//     turtle for some simulated seconds and tests the end state.
// Prints ok or FAIL per test and a summary, and exits with 1 when
// anything failed.

import fs from 'node:fs';
import path from 'node:path';
import util from 'node:util';
import { fileURLToPath } from 'node:url';
import fengari from 'fengari';
import { Simulation } from './js/simulation.js';
import { SCENARIOS } from './js/scenarios.js';
import { World, HEADING_NAMES } from './js/world.js';
import { parseScenario, parseChecks } from './js/scenariofile.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..');
const scenarioDir = path.join(here, 'scenarios');
const checkDir = path.join(repo, 'tests', 'scenarios');
const rel = (f) => path.relative(repo, f).split(path.sep).join('/');

const filter = (process.argv[2] || '').toLowerCase();
const wanted = (name) => !filter || name.toLowerCase().includes(filter);
const colour = process.stdout.isTTY;
const paint = (code, s) => (colour ? `\x1b[${code}m${s}\x1b[0m` : s);

// The repo's lua files, as the simulator's file system.
function loadFiles() {
  const files = new Map();
  const walk = (dir) => {
    for (const name of fs.readdirSync(dir)) {
      if (name.startsWith('.') || name === 'sim' || name === '__pycache__' || name === 'node_modules') continue;
      const full = path.join(dir, name);
      if (fs.statSync(full).isDirectory()) walk(full);
      else if (name.endsWith('.lua')) files.set(rel(full), fs.readFileSync(full, 'latin1'));
    }
  };
  walk(repo);
  return files;
}

const files = loadFiles();
const biosSource = fs.readFileSync(path.join(here, 'lua/bios.lua'), 'latin1');

function newSim() {
  const sim = new Simulation({ fengari, files, biosSource });
  sim.maxLogs = 1e6;
  return sim;
}

// Run until the clock reaches seconds or done() is true, checking
// every simulated second.
function runSim(sim, seconds, done) {
  while (sim.clock < seconds) {
    sim.runUntil(Math.min(seconds, Math.floor(sim.clock) + 1));
    if (done && done()) break;
  }
}

const listFiles = (dir, ext) => (fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith(ext)).sort() : []);

// Every test is { name, run() } where run returns a list of failure
// messages (empty when it passed) and may set info.
const tests = [];

/*
 * Lua unit tests
 */

function luaTestFiles(dir = path.join(repo, 'tests'), found = []) {
  if (!fs.existsSync(dir)) return found;
  for (const name of fs.readdirSync(dir).sort()) {
    const full = path.join(dir, name);
    if (fs.statSync(full).isDirectory()) luaTestFiles(full, found);
    else if (name.endsWith('_test.lua')) found.push(rel(full));
  }
  return found;
}

{
  const all = luaTestFiles();
  const chosen = !filter || 'lua unit tests'.includes(filter) ? all : all.filter((f) => f.toLowerCase().includes(filter));
  if (chosen.length) {
    tests.push({
      name: `lua unit tests (${chosen.length === all.length ? 'all' : chosen.join(', ')})`,
      run() {
        const sim = newSim();
        const command = chosen.length === all.length ? 'test' : `test ${chosen.join(' ')}`;
        sim.load({ build() {}, computers: [{ id: 1, label: 'Tests', kind: 'computer', advanced: true, peripherals: {}, autorun: command }] });
        const summary = () => sim.logs.find((l) => /^tests: \d+ passed, \d+ failed/.test(l.text));
        runSim(sim, 120, summary);
        const line = summary();
        const computer = sim.computers.get(1);
        if (!line) {
          const tail = sim.logs.slice(-10).map((l) => `  | ${l.text}`).join('\n');
          return [`no summary from the test program (${computer.state}${computer.error ? ': ' + computer.error : ''})\n${tail}`];
        }
        this.info = line.text.replace(/^tests: /, '');
        const [, , failed] = /(\d+) passed, (\d+) failed/.exec(line.text).map(Number);
        if (!failed) return [];
        const start = sim.logs.findIndex((l) => l.text === 'Failures:');
        const end = sim.logs.indexOf(line);
        return [sim.logs.slice(start + 1, end).map((l) => l.text).join('\n')];
      },
    });
  }
}

/*
 * The scenario file format
 */

const scenarioFiles = listFiles(scenarioDir, '.scn');
const fileScenarios = {};
const parseErrors = {};
for (const f of scenarioFiles) {
  const key = f.slice(0, -4);
  try {
    fileScenarios[key] = parseScenario(fs.readFileSync(path.join(scenarioDir, f), 'utf8'), { key, file: `sim/scenarios/${f}` });
  } catch (e) {
    parseErrors[key] = e.message;
  }
}

for (const f of scenarioFiles) {
  const key = f.slice(0, -4);
  tests.push({
    name: `scenario file ${f} parses`,
    run() {
      if (parseErrors[key]) return [parseErrors[key]];
      if (SCENARIOS[key]) return [`${key} is also a built-in scenario, which hides it`];
      const s = fileScenarios[key];
      const failures = [];
      const ids = new Set();
      for (const c of s.computers) {
        if (ids.has(c.id)) failures.push(`computer id ${c.id} used twice`);
        ids.add(c.id);
      }
      try { s.build(new World()); } catch (e) { failures.push(`build failed: ${e.message}`); }
      return failures;
    },
  });
}

tests.push({
  name: 'scenario files are all in sim/scenarios/index.json',
  run() {
    let index;
    try { index = JSON.parse(fs.readFileSync(path.join(scenarioDir, 'index.json'), 'utf8')); } catch (e) { return [`index.json: ${e.message}`]; }
    const failures = [];
    for (const f of scenarioFiles) if (!index.includes(f)) failures.push(`${f} is missing from index.json (the browser will not list it)`);
    for (const f of index) if (!scenarioFiles.includes(f)) failures.push(`index.json lists ${f}, which does not exist`);
    return failures;
  },
});

// Everything about a built world and its computers, to compare two.
function snapshot(scenario) {
  const world = new World();
  scenario.build(world);
  const sorted = (m) => Object.fromEntries([...m.entries()].sort());
  return {
    blocks: sorted(world.blocks),
    containers: sorted(world.containers),
    meta: sorted(world.meta),
    computers: JSON.parse(JSON.stringify(scenario.computers)),
  };
}

function sameScenario(a, b) {
  const sa = snapshot(a);
  const sb = snapshot(b);
  const failures = [];
  for (const part of ['blocks', 'containers', 'meta', 'computers']) {
    if (!util.isDeepStrictEqual(sa[part], sb[part])) {
      let detail = '';
      if (part === 'computers') detail = `\n  file:     ${JSON.stringify(sa.computers)}\n  built-in: ${JSON.stringify(sb.computers)}`;
      else {
        const keys = new Set([...Object.keys(sa[part]), ...Object.keys(sb[part])]);
        const diff = [...keys].filter((k) => !util.isDeepStrictEqual(sa[part][k], sb[part][k])).slice(0, 5);
        detail = ` at ${diff.map((k) => `${k} (${JSON.stringify(sa[part][k])} vs ${JSON.stringify(sb[part][k])})`).join(', ')}`;
      }
      failures.push(`${part} differ${detail}`);
    }
  }
  return failures;
}

if (fileScenarios['quarry-file']) {
  tests.push({
    name: 'scenario file quarry-file builds the same world as the built-in quarry',
    run() { return sameScenario(fileScenarios['quarry-file'], SCENARIOS.quarry); },
  });
}

// The control scenario written out by hand: monitors, several
// computers, trees and labels on the header line.
const CONTROL_SCN = `
name Turtle control
ground -10 -8 12 12 0 8
block -1 0 1 chest
block -1 4 1 chest
block -1 8 1 chest
tree 8 8 1
tree 10 4 1
computer 1 Control
  pos -5 -4 1
  peripheral right monitor size=3x2 at=-4,-4,1
  peripheral top modem
  autorun turtlecontrol
turtle 7 label=Digger pos=0,0,1 heading=north fuel=1200
  slots coal*12 torch*32 oak_sapling*4
  peripheral left modem
  autorun turtleagent
turtle 8 label=Lumber pos=0,4,1 fuel=400
  slots coal*5 minecraft:oak_sapling*16
  autorun turtleagent
turtle 9 Runner # almost out of fuel
  pos 0,8,1
  fuel 6
  autorun turtleagent
peripheral 8 left modem
peripheral 9 left modem
`;

tests.push({
  name: 'scenario format: the control scenario written as a file matches the built-in',
  run() {
    const s = parseScenario(CONTROL_SCN, { key: 'control-inline', file: 'inline control' });
    return sameScenario(s, SCENARIOS.control);
  },
});

// Every other feature of the format.
const FEATURES_SCN = `
# a comment
name Features   # trailing comment
description First part,
description second part.
fill 0 0 0 2 0 0 stone facing=1 powered=false
clear 1 0 0 1 0 0
block 5 5 5 chest network=storage label="Main store"
items 5 5 5 coal*20 _ minecraft:stone_pickaxe*1@3 torch
block 6 5 5 air
pocket 12 label="Pocket PC" advanced=false
  peripheral back modem
turtle 2
  set fuelLimit=500 custom=hello
  slot 3 iron_ingot*2
  autorun stripmine 3 2 12 "true" 5
computer 4
  peripheral 4 back modem wired=true network=storage
at 20 give 2 minecraft:coal 8
at 10 toggle 2 0 1
at 30 explode 1 2 power=4 note="big bang"
`;

tests.push({
  name: 'scenario format: blocks, items, computers and the timeline',
  run() {
    const s = parseScenario(FEATURES_SCN, { key: 'features' });
    const world = new World();
    s.build(world);
    const failures = [];
    const want = (what, actual, expected) => {
      if (!util.isDeepStrictEqual(actual, expected)) failures.push(`${what}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
    };
    want('name', s.name, 'Features');
    want('description', s.description, 'First part, second part.');
    want('fill', [world.getBlock(0, 0, 0), world.getBlock(1, 0, 0), world.getBlock(2, 0, 0)], ['stone', null, 'stone']);
    want('fill meta', world.getMeta(2, 0, 0), { facing: 1, powered: false });
    want('block meta', world.getMeta(5, 5, 5), { network: 'storage', label: 'Main store' });
    want('items', world.getContainer(5, 5, 5).slice(0, 5), [
      { name: 'minecraft:coal', count: 20 }, null, { name: 'minecraft:stone_pickaxe', count: 1, damage: 3 }, { name: 'minecraft:torch', count: 1 }, null]);
    want('pocket', s.computers[0], { id: 12, label: 'Pocket PC', kind: 'pocket', advanced: false, peripherals: { back: { type: 'modem' } }, autorun: '' });
    want('turtle', s.computers[1], {
      id: 2, label: null, kind: 'turtle', advanced: true, peripherals: {}, autorun: 'stripmine 3 2 12 "true" 5',
      pos: { x: 0, y: 0, z: 1 }, heading: 0, fuel: 1000, slots: [null, null, { name: 'minecraft:iron_ingot', count: 2 }],
      fuelLimit: 500, custom: 'hello',
    });
    want('wired modem', s.computers[2].peripherals, { back: { type: 'modem', wired: true, network: 'storage' } });
    want('timeline', s.timeline, [
      { at: 10, action: 'toggle', x: 2, y: 0, z: 1 },
      { at: 20, action: 'give', computer: 2, item: 'minecraft:coal', count: 8 },
      { at: 30, action: 'explode', args: [1, 2], power: 4, note: 'big bang' },
    ]);
    for (const [bad, message] of [
      ['fill 0 0 0 1 1 stone', 'numbers'],
      ['slots coal*2', 'unknown command'],
      ['turtle x', 'turtle <id>'],
      ['turtle 1\nturtle 1', 'defined twice'],
      ['items 0 0 0 coal**2', 'bad item'],
      ['peripheral 9 left modem', 'not defined'],
      ['check c\nexpect turtle 1 fly', 'expect turtle'],
      ['label "unclosed', 'unclosed quote'],
    ]) {
      try {
        parseScenario(bad, { file: 'bad.scn' });
        failures.push(`no error for ${JSON.stringify(bad)}`);
      } catch (e) {
        if (!e.message.includes(message) || !/^bad\.scn:\d+: /.test(e.message)) failures.push(`for ${JSON.stringify(bad)}: unexpected error "${e.message}"`);
      }
    }
    return failures;
  },
});

/*
 * Scenario checks
 */

const checks = [];
for (const f of listFiles(checkDir, '.check')) {
  try {
    checks.push(...parseChecks(fs.readFileSync(path.join(checkDir, f), 'utf8'), { file: `tests/scenarios/${f}` }));
  } catch (e) {
    tests.push({ name: `check file ${f}`, run: () => [e.message] });
  }
}
for (const s of Object.values(fileScenarios)) checks.push(...s.checks);

const COMPARE = {
  '=': (a, b) => a === b, '!=': (a, b) => a !== b, '<': (a, b) => a < b,
  '<=': (a, b) => a <= b, '>': (a, b) => a > b, '>=': (a, b) => a >= b,
};
const compare = (actual, e) => COMPARE[e.op](actual, e.value);
const countItems = (slots, name) => (slots || []).reduce((n, s) => n + (s && (!name || s.name === name) ? s.count : 0), 0);
const ERROR_TEXT = /\.lua:\d+:|^Failed to load API|^No such program|^Error: /;
const squash = (s) => s.replace(/\s+/g, ' ').trim();

// The text of every screen of a computer, wrapped lines joined.
function screenText(computer) {
  const parts = [];
  for (const t of computer.terminals.values()) parts.push(t.dump().split('\n').map((l) => l.trimEnd()).join(' '));
  return squash(parts.join(' '));
}

// Why one expectation does not hold, or null.
function evaluate(sim, e) {
  const world = sim.world;
  const turtle = (id) => world.turtles.get(id);
  const where = (p) => `(${p.x}, ${p.y}, ${p.z})`;
  switch (e.kind) {
    case 'turtle-pos': case 'turtle-heading': case 'turtle-fuel': case 'turtle-item': case 'turtle-items': {
      const t = turtle(e.id);
      if (!t) return `there is no turtle ${e.id}`;
      if (e.kind === 'turtle-pos') return t.x === e.pos.x && t.y === e.pos.y && t.z === e.pos.z ? null : `turtle ${e.id} is at ${where(t)}, not ${where(e.pos)}`;
      if (e.kind === 'turtle-heading') return t.heading === e.heading ? null : `turtle ${e.id} faces ${HEADING_NAMES[t.heading]}, not ${HEADING_NAMES[e.heading]}`;
      if (e.kind === 'turtle-fuel') return compare(t.fuel, e) ? null : `turtle ${e.id} has ${t.fuel} fuel, wanted ${e.op} ${e.value}`;
      const n = countItems(t.slots, e.item);
      return compare(n, e) ? null : `turtle ${e.id} has ${n} ${e.item || 'items'}, wanted ${e.op} ${e.value}`;
    }
    case 'chest-item': case 'chest-items': {
      const slots = world.getContainer(e.pos.x, e.pos.y, e.pos.z);
      if (!slots) return `there is no chest at ${where(e.pos)}`;
      const n = countItems(slots, e.item);
      return compare(n, e) ? null : `the chest at ${where(e.pos)} has ${n} ${e.item || 'items'}, wanted ${e.op} ${e.value}`;
    }
    case 'block': {
      const b = world.getBlock(e.pos.x, e.pos.y, e.pos.z);
      const ok = (b === e.type) !== !!e.negate;
      return ok ? null : `block at ${where(e.pos)} is ${b || 'air'}, wanted ${e.negate ? 'anything but ' : ''}${e.type || 'air'}`;
    }
    case 'blocks': {
      let n = 0;
      let total = 0;
      let first = null;
      for (let x = Math.min(e.from.x, e.to.x); x <= Math.max(e.from.x, e.to.x); x++) {
        for (let y = Math.min(e.from.y, e.to.y); y <= Math.max(e.from.y, e.to.y); y++) {
          for (let z = Math.min(e.from.z, e.to.z); z <= Math.max(e.from.z, e.to.z); z++) {
            total++;
            const b = world.getBlock(x, y, z);
            if (b === e.type) n++;
            else if (!first) first = `${b} at ${where({ x, y, z })}`;
          }
        }
      }
      const box = `${where(e.from)}-${where(e.to)}`;
      if (e.op) return compare(n, e) ? null : `${n} ${e.type || 'air'} blocks in ${box}, wanted ${e.op} ${e.value}`;
      return n === total ? null : `${total - n} of ${total} blocks in ${box} are not ${e.type || 'air'}, e.g. ${first}`;
    }
    case 'screen': {
      const c = sim.computers.get(e.id);
      if (!c) return `there is no computer ${e.id}`;
      const text = screenText(c);
      const found = text.includes(squash(e.text));
      if (found !== !!e.negate) return null;
      return `computer ${e.id}'s screen ${e.negate ? 'shows' : 'does not show'} "${e.text}":\n    ${text.slice(-300)}`;
    }
    case 'log': {
      const found = sim.logs.some((l) => l.text.includes(e.text));
      return found !== !!e.negate ? null : `the log ${e.negate ? 'has' : 'has no'} "${e.text}"`;
    }
    case 'no-error': {
      const problems = [];
      for (const c of sim.computers.values()) {
        if (e.id != null && c.id !== e.id) continue;
        if (c.state === 'error') problems.push(`computer ${c.id} crashed: ${c.error}`);
        for (const l of sim.logs) if (l.computer === c.id && ERROR_TEXT.test(l.text)) problems.push(`computer ${c.id} at ${l.at.toFixed(1)}s: ${l.text}`);
      }
      return problems.length ? problems.slice(0, 5).join('\n    ') : null;
    }
    default:
      return `unknown expectation ${e.kind}`;
  }
}

function findScenario(key) {
  return SCENARIOS[key] || fileScenarios[key] || null;
}

for (const check of checks) {
  tests.push({
    name: `check ${check.scenario}: ${check.name}`,
    run() {
      const scenario = findScenario(check.scenario);
      if (!scenario) return [`${check.file}:${check.line}: unknown scenario ${check.scenario}`];
      const computers = scenario.computers.map((c) => ({ ...c }));
      if (check.run !== undefined) {
        const target = check.on != null ? computers.find((c) => c.id === check.on) : computers.find((c) => c.kind === 'turtle') || computers[0];
        if (!target) return [`${check.file}:${check.line}: no computer ${check.on} in ${check.scenario}`];
        target.autorun = check.run;
      }
      const sim = newSim();
      sim.load({ ...scenario, computers });
      runSim(sim, check.seconds, check.until ? () => sim.logs.some((l) => l.text.includes(check.until)) : null);
      this.info = `${sim.clock.toFixed(0)}s simulated`;
      const failures = [];
      if (check.until && !sim.logs.some((l) => l.text.includes(check.until))) failures.push(`"${check.until}" never appeared in ${check.seconds}s`);
      for (const e of check.expects) {
        const why = evaluate(sim, e);
        if (why) failures.push(`${check.file}:${e.line}: ${why}`);
      }
      return failures;
    },
  });
}

/*
 * Run
 */

const chosen = tests.filter((t) => t.name.startsWith('lua unit tests') || wanted(t.name));
if (!chosen.length) {
  console.log(`no tests match "${filter}"`);
  process.exit(1);
}
let passed = 0;
let failed = 0;
const started = Date.now();
for (const t of chosen) {
  const t0 = Date.now();
  let failures;
  try {
    failures = t.run();
  } catch (e) {
    failures = [`threw ${e && e.stack ? e.stack : e}`];
  }
  const ms = Date.now() - t0;
  const info = [t.info, `${ms}ms`].filter(Boolean).join(', ');
  if (failures.length) {
    failed++;
    console.log(`${paint(31, 'FAIL')} ${t.name} ${paint(90, `(${info})`)}`);
    for (const f of failures) console.log(`     ${f.split('\n').join('\n     ')}`);
  } else {
    passed++;
    console.log(`${paint(32, 'ok')}   ${t.name} ${paint(90, `(${info})`)}`);
  }
}
const summary = `${passed} passed, ${failed} failed in ${((Date.now() - started) / 1000).toFixed(1)}s`;
console.log(failed ? paint(31, summary) : paint(32, summary));
process.exit(failed ? 1 : 0);
