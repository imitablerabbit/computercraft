// Scenario files: simulator worlds written as plain text, so a new
// scenario needs no JavaScript. parseScenario turns the text of a .scn
// file into the same kind of object scenarios.js holds (name,
// description, build(world), computers, plus timeline and checks), and
// parseChecks reads the check blocks of a .check file. The format is
// described in full in the README ("Scenario files"); in short, one
// command per line, words separated by spaces, "double quotes" around
// words with spaces, key=value for named fields, and # starting a
// comment at the start of a line or after a space:
//
//   name Quarry
//   description One turtle with a chest on its left.
//   ground -6 -6 10 10 0 9                # corners x y, top z, depth
//   fill 0 0 1 2 2 3 air                  # box corners, block type
//   block -1 0 1 chest
//   items -1 0 1 coal*20 torch*5 _ stone_pickaxe*1@3
//   turtle 3 label=Miner pos=0,0,1 heading=north fuel=800
//     slots coal*20
//     peripheral left modem
//     autorun quarry 3 3 2
//   at 10 toggle 2 0 1
//
// Values that look like numbers become numbers and true / false
// become booleans, unless they are quoted. Block meta, peripheral
// fields, extra computer fields and timeline fields are passed on
// untouched, so new simulator features need no parser changes.

import { tree } from './world.js';

export const HEADING_NAMES = ['north', 'east', 'south', 'west'];

// Positional words of timeline actions, by action. Anything not listed
// here (and any extra words) is kept in the entry's args list.
// These match Simulation.runTimeline. type takes the rest of the line
// as the text to paste.
export const TIMELINE_ARGS = {
  toggle: ['x', 'y', 'z'],
  press: ['x', 'y', 'z'],
  step: ['x', 'y', 'z', 'seconds'],
  give: ['computer', 'item', 'count', 'slot'],
  place: ['x', 'y', 'z', 'block'],
  remove: ['x', 'y', 'z'],
  type: ['computer'],
  turnOn: ['computer'],
  shutdown: ['computer'],
  reboot: ['computer'],
};

export class ScenarioSyntaxError extends Error {
  constructor(file, line, message) {
    super(`${file || 'scenario'}:${line}: ${message}`);
    this.file = file;
    this.line = line;
  }
}

// The same ground and hill as scenarios.js, so converted scenarios
// build exactly the same world.
export function ground(world, x0, x1, y0, y1, top, depth, { ores = true, pockets = true, seed: start = 7 } = {}) {
  let seed = start;
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

export function hill(world, x0, x1, y0, y1, base, height) {
  for (let x = x0; x <= x1; x++) {
    for (let y = y0; y <= y1; y++) {
      for (let z = base; z < base + height; z++) {
        world.setBlock(x, y, z, z === base + height - 1 ? 'grass' : 'dirt');
      }
    }
  }
}

export function monitorBlocks(x, y, z, blocksW, blocksH) {
  const blocks = [];
  for (let i = 0; i < blocksW; i++) for (let j = 0; j < blocksH; j++) blocks.push({ x: x + i, y, z: z + j });
  return blocks;
}

// Split a line into words. Each word is { text, quoted, eq } where
// quoted says some of it was in quotes and eq is the index of a
// key=value's = when it came before any quote.
export function tokenize(line) {
  const words = [];
  let cur = null;
  let inQuote = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (inQuote) {
      if (ch === '"') inQuote = false;
      else if (ch === '\\' && i + 1 < line.length) cur.text += line[++i];
      else cur.text += ch;
      continue;
    }
    if (/\s/.test(ch)) { if (cur) { words.push(cur); cur = null; } continue; }
    if (ch === '#' && !cur) break; // comment
    if (!cur) cur = { text: '', quoted: false, eq: -1 };
    if (ch === '"') { inQuote = true; cur.quoted = true; continue; }
    if (ch === '=' && cur.eq < 0 && !cur.quoted) cur.eq = cur.text.length;
    cur.text += ch;
  }
  if (inQuote) throw new Error('unclosed quote');
  if (cur) words.push(cur);
  return words;
}

// A word as a value: numbers and booleans unless quoted.
export function value(word) {
  const text = typeof word === 'string' ? word : word.text;
  if (typeof word !== 'string' && word.quoted) return text;
  if (/^[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$/.test(text)) return Number(text);
  if (text === 'true') return true;
  if (text === 'false') return false;
  if (text === 'null' || text === 'nil') return null;
  return text;
}

// The line without its comment: from a # that starts a word, outside
// quotes.
export function stripComment(line) {
  let inQuote = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') inQuote = !inQuote;
    else if (ch === '\\' && inQuote) i++;
    else if (ch === '#' && !inQuote && (i === 0 || /\s/.test(line[i - 1]))) return line.slice(0, i);
  }
  return line;
}

const isKeyValue = (w) => w.eq > 0 && /^[A-Za-z_][\w.-]*$/.test(w.text.slice(0, w.eq));

// Split words into plain words and a key=value object.
function splitFields(words) {
  const plain = [];
  const fields = {};
  for (const w of words) {
    if (isKeyValue(w)) {
      const raw = w.text.slice(w.eq + 1);
      fields[w.text.slice(0, w.eq)] = value({ text: raw, quoted: w.quoted });
    } else {
      plain.push(w);
    }
  }
  return { plain, fields };
}

// minecraft:coal*20, coal*20 (minecraft: is assumed), stone_pickaxe*1@3
// (damage 3), or _ for an empty slot.
export function parseItem(text) {
  if (text === '_' || text === '-' || text === 'empty') return null;
  const m = /^([^*@]+)(?:\*(\d+))?(?:@(\d+))?$/.exec(text);
  if (!m) throw new Error(`bad item "${text}" (want name*count, e.g. minecraft:coal*20)`);
  const name = m[1].includes(':') ? m[1] : `minecraft:${m[1]}`;
  const item = { name, count: m[2] ? parseInt(m[2], 10) : 1 };
  if (m[3]) item.damage = parseInt(m[3], 10);
  return item;
}

function parseHeading(v) {
  if (typeof v === 'number') return v;
  const i = HEADING_NAMES.indexOf(String(v).toLowerCase());
  if (i < 0) throw new Error(`bad heading "${v}" (0-3 or north, east, south, west)`);
  return i;
}

// "x,y,z" or three words.
function parsePos(v) {
  const parts = Array.isArray(v) ? v : String(v).split(',');
  const nums = parts.map((p) => Number(typeof p === 'object' ? p.text : p));
  if (nums.length !== 3 || nums.some((n) => !Number.isFinite(n))) throw new Error(`bad position "${parts.map((p) => p.text ?? p).join(' ')}" (want x y z or x,y,z)`);
  return { x: nums[0], y: nums[1], z: nums[2] };
}

function numbers(words, count, what) {
  if (words.length < count) throw new Error(`${what} needs ${count} numbers`);
  const nums = words.slice(0, count).map((w) => Number(w.text));
  if (nums.some((n) => !Number.isFinite(n))) throw new Error(`${what}: expected numbers, got "${words.slice(0, count).map((w) => w.text).join(' ')}"`);
  return nums;
}

const blockType = (text) => (['air', 'none', 'null', '_'].includes(text) ? null : text);
const rest = (words) => words.map((w) => w.text).join(' ');

// Computer definition fields given as key=value on the header or a set
// line. pos and heading are parsed; everything else is passed on.
function setFields(def, fields) {
  for (const [k, v] of Object.entries(fields)) {
    if (k === 'pos') def.pos = parsePos(v);
    else if (k === 'heading') def.heading = parseHeading(v);
    else if (k === 'label') def.label = v == null ? null : String(v);
    else if (k === 'autorun') def.autorun = v == null ? '' : String(v);
    else def[k] = v;
  }
}

function peripheralDef(type, fields) {
  const p = { type, ...fields };
  if (type === 'monitor' && p.advanced === undefined) p.advanced = true;
  if (typeof p.size === 'string') {
    const m = /^(\d+)x(\d+)$/.exec(p.size);
    if (!m) throw new Error(`bad monitor size "${p.size}" (want WxH, e.g. 3x2)`);
    p.blocksW = parseInt(m[1], 10);
    p.blocksH = parseInt(m[2], 10);
    delete p.size;
  }
  if (p.at !== undefined) {
    const at = parsePos(p.at);
    p.blocks = monitorBlocks(at.x, at.y, at.z, p.blocksW || 1, p.blocksH || 1);
    if (p.blocksW === undefined) { p.blocksW = 1; p.blocksH = 1; }
    delete p.at;
  }
  return p;
}

// One expect line of a check, after the word expect.
const OPS = ['=', '==', '!=', '<', '<=', '>', '>='];
function parseCompare(words, what) {
  if (words.length === 0) return { op: '>=', value: 1 };
  if (words.length !== 2 || !OPS.includes(words[0].text) || !Number.isFinite(Number(words[1].text))) {
    throw new Error(`${what}: want a comparison such as ">= 10" or "= 0"`);
  }
  return { op: words[0].text === '==' ? '=' : words[0].text, value: Number(words[1].text) };
}

function parseExpect(words) {
  let negate = false;
  if (words[0] && words[0].text === 'not') { negate = true; words = words.slice(1); }
  const kind = words[0] && words[0].text;
  const w = words.slice(1);
  const itemName = (t) => (t.includes(':') ? t : `minecraft:${t}`);
  switch (kind) {
    case 'turtle': {
      const id = Number(w[0] && w[0].text);
      const what = w[1] && w[1].text;
      if (!Number.isFinite(id)) throw new Error('expect turtle <id> ...');
      if (what === 'pos') return { kind: 'turtle-pos', id, pos: parsePos(w.slice(2)) };
      if (what === 'heading') return { kind: 'turtle-heading', id, heading: parseHeading(value(w[2] || { text: '' })) };
      if (what === 'fuel') return { kind: 'turtle-fuel', id, ...parseCompare(w.slice(2), 'expect turtle fuel') };
      if (what === 'item' && w[2]) return { kind: 'turtle-item', id, item: itemName(w[2].text), ...parseCompare(w.slice(3), 'expect turtle item') };
      if (what === 'items') return { kind: 'turtle-items', id, ...parseCompare(w.slice(2), 'expect turtle items') };
      throw new Error('expect turtle <id> pos|heading|fuel|item|items ...');
    }
    case 'chest': {
      const [x, y, z] = numbers(w, 3, 'expect chest');
      const what = w[3] && w[3].text;
      if (what === 'item' && w[4]) return { kind: 'chest-item', pos: { x, y, z }, item: itemName(w[4].text), ...parseCompare(w.slice(5), 'expect chest item') };
      if (what === 'items') return { kind: 'chest-items', pos: { x, y, z }, ...parseCompare(w.slice(4), 'expect chest items') };
      throw new Error('expect chest <x> <y> <z> item <name> <op> <n> | items <op> <n>');
    }
    case 'block': {
      const [x, y, z] = numbers(w, 3, 'expect block');
      if (!w[3]) throw new Error('expect block <x> <y> <z> <type|air>');
      return { kind: 'block', pos: { x, y, z }, type: blockType(w[3].text), negate };
    }
    case 'blocks': {
      const [x0, y0, z0, x1, y1, z1] = numbers(w, 6, 'expect blocks');
      if (!w[6]) throw new Error('expect blocks <x0> <y0> <z0> <x1> <y1> <z1> <type|air> [<op> <n>]');
      const e = { kind: 'blocks', from: { x: x0, y: y0, z: z0 }, to: { x: x1, y: y1, z: z1 }, type: blockType(w[6].text) };
      if (w.length > 7) Object.assign(e, parseCompare(w.slice(7), 'expect blocks'));
      return e;
    }
    case 'screen': {
      const id = Number(w[0] && w[0].text);
      if (!Number.isFinite(id) || w.length < 2) throw new Error('expect screen <id> <text>');
      return { kind: 'screen', id, text: rest(w.slice(1)), negate };
    }
    case 'log':
      if (!w.length) throw new Error('expect log <text>');
      return { kind: 'log', text: rest(w), negate };
    case 'no-error':
      return { kind: 'no-error', id: w[0] ? Number(w[0].text) : null };
    default:
      throw new Error(`unknown expectation "${kind}" (turtle, chest, block, blocks, screen, log, no-error)`);
  }
}

// One line of a check block. Returns false when it is not a check line.
function checkLine(check, cmd, args) {
  switch (cmd) {
    case 'scenario': check.scenario = args[0] && args[0].text; return true;
    case 'run': check.run = rest(args); return true;
    case 'on': check.on = Number(args[0] && args[0].text); return true;
    case 'seconds': check.seconds = Number(args[0] && args[0].text); return true;
    case 'until': check.until = rest(args); return true;
    case 'expect': check.expects.push({ ...parseExpect(args), line: check.currentLine }); return true;
    default: return false;
  }
}

function newCheck(name, file, line) {
  return { name, file, line, scenario: null, run: undefined, on: null, seconds: 60, until: null, expects: [] };
}

// Parse a .scn file. key names it (the file name without .scn); file is
// used in error messages. Throws ScenarioSyntaxError on a bad line.
export function parseScenario(text, { key = null, file = null } = {}) {
  const ops = [];          // world building steps, in file order
  const computers = [];
  const byId = new Map();
  const laterPeripherals = [];
  const timeline = [];
  const checks = [];
  let name = key;
  const description = [];
  let current = null;      // computer being defined
  let check = null;        // check block being read

  const lines = text.split(/\r?\n/);
  for (let n = 0; n < lines.length; n++) {
    const lineNo = n + 1;
    let words;
    try { words = tokenize(lines[n]); } catch (e) { throw new ScenarioSyntaxError(file, lineNo, e.message); }
    if (!words.length) continue;
    const cmd = words[0].text;
    const args = words.slice(1);
    const rawRest = stripComment(lines[n]).trim().slice(cmd.length).trim();
    try {
      if (cmd === 'check') {
        check = newCheck(rest(args) || `check ${checks.length + 1}`, file, lineNo);
        check.scenario = key;
        checks.push(check);
        continue;
      }
      if (check) {
        check.currentLine = lineNo;
        if (!checkLine(check, cmd, args)) throw new Error(`"${cmd}" is not a check line (scenario, run, on, seconds, until, expect)`);
        continue;
      }
      switch (cmd) {
        case 'name': name = rawRest; break;
        case 'description': description.push(rawRest); break;
        case 'ground': {
          const { plain, fields } = splitFields(args);
          const [x0, y0, x1, y1, top, depth] = numbers(plain, 6, 'ground x0 y0 x1 y1 top depth');
          ops.push((world) => ground(world, Math.min(x0, x1), Math.max(x0, x1), Math.min(y0, y1), Math.max(y0, y1), top, depth, fields));
          break;
        }
        case 'hill': {
          const [x0, y0, x1, y1, base, height] = numbers(args, 6, 'hill x0 y0 x1 y1 base height');
          ops.push((world) => hill(world, Math.min(x0, x1), Math.max(x0, x1), Math.min(y0, y1), Math.max(y0, y1), base, height));
          break;
        }
        case 'fill':
        case 'clear': {
          const { plain, fields } = splitFields(args);
          const [x0, y0, z0, x1, y1, z1] = numbers(plain, 6, `${cmd} x0 y0 z0 x1 y1 z1`);
          let type = null;
          if (cmd === 'fill') {
            if (!plain[6]) throw new Error('fill x0 y0 z0 x1 y1 z1 <type|air> [key=value...]');
            type = blockType(plain[6].text);
          }
          const meta = Object.keys(fields).length ? fields : undefined;
          ops.push((world) => {
            for (let x = Math.min(x0, x1); x <= Math.max(x0, x1); x++) {
              for (let y = Math.min(y0, y1); y <= Math.max(y0, y1); y++) {
                for (let z = Math.min(z0, z1); z <= Math.max(z0, z1); z++) world.setBlock(x, y, z, type, meta);
              }
            }
          });
          break;
        }
        case 'block': {
          const { plain, fields } = splitFields(args);
          const [x, y, z] = numbers(plain, 3, 'block x y z');
          if (!plain[3]) throw new Error('block x y z <type|air> [key=value...]');
          const type = blockType(plain[3].text);
          const meta = Object.keys(fields).length ? fields : undefined;
          ops.push((world) => world.setBlock(x, y, z, type, meta));
          break;
        }
        case 'items': {
          const [x, y, z] = numbers(args, 3, 'items x y z');
          const items = args.slice(3).map((w) => parseItem(w.text));
          ops.push((world) => world.fillContainer(x, y, z, items));
          break;
        }
        case 'tree': {
          const [x, y, base] = numbers(args, 3, 'tree x y base');
          ops.push((world) => tree(world, x, y, base));
          break;
        }
        case 'turtle':
        case 'computer':
        case 'pocket': {
          const { plain, fields } = splitFields(args);
          const id = Number(plain[0] && plain[0].text);
          if (!Number.isInteger(id)) throw new Error(`${cmd} <id> [key=value...]`);
          if (byId.has(id)) throw new Error(`computer ${id} is defined twice`);
          current = { id, label: null, kind: cmd, advanced: true, peripherals: {}, autorun: '' };
          if (cmd === 'turtle') Object.assign(current, { pos: { x: 0, y: 0, z: 1 }, heading: 0, fuel: 1000, slots: [] });
          if (plain.length > 1) current.label = rest(plain.slice(1));
          setFields(current, fields);
          current.line = lineNo;
          computers.push(current);
          byId.set(id, current);
          break;
        }
        case 'at': {
          const t = Number(args[0] && args[0].text);
          if (!Number.isFinite(t) || !args[1]) throw new Error('at <seconds> <action> [words...] [key=value...]');
          const { plain, fields } = splitFields(args.slice(2));
          const entry = { at: t, action: args[1].text };
          const names = TIMELINE_ARGS[entry.action] || [];
          const extra = [];
          plain.forEach((w, i) => { if (i < names.length) entry[names[i]] = value(w); else extra.push(value(w)); });
          if (entry.action === 'type' && extra.length) entry.text = plain.slice(names.length).map((w) => w.text).join(' ');
          else if (extra.length) entry.args = extra;
          Object.assign(entry, fields);
          timeline.push(entry);
          break;
        }
        case 'peripheral': {
          // peripheral [id] <side> <type> [key=value...]
          const { plain, fields } = splitFields(args);
          let target = current;
          let i = 0;
          if (plain[0] && /^\d+$/.test(plain[0].text)) {
            target = Number(plain[0].text);
            i = 1;
          }
          if (!plain[i] || !plain[i + 1]) throw new Error('peripheral [id] <side> <type> [key=value...]');
          const p = peripheralDef(plain[i + 1].text, fields);
          if (typeof target === 'number') laterPeripherals.push({ id: target, side: plain[i].text, p, line: lineNo });
          else if (target) target.peripherals[plain[i].text] = p;
          else throw new Error('peripheral before any turtle, computer or pocket (give the computer id first)');
          break;
        }
        default: {
          if (!current) throw new Error(`unknown command "${cmd}"`);
          switch (cmd) {
            case 'label': current.label = rawRest === '' || rawRest === 'none' ? null : rawRest; break;
            case 'pos': current.pos = parsePos(args.length === 1 ? args[0].text : args); break;
            case 'heading': current.heading = parseHeading(value(args[0] || { text: '' })); break;
            case 'fuel': current.fuel = value(args[0] || { text: '' }); break;
            case 'advanced': current.advanced = value(args[0] || { text: 'true' }) !== false; break;
            case 'autorun': current.autorun = rawRest; break;
            case 'slots': current.slots = args.map((w) => parseItem(w.text)); break;
            case 'slot': {
              const slot = Number(args[0] && args[0].text);
              if (!Number.isInteger(slot) || slot < 1 || slot > 16 || !args[1]) throw new Error('slot <1-16> <item>');
              current.slots = current.slots || [];
              while (current.slots.length < slot - 1) current.slots.push(null);
              current.slots[slot - 1] = parseItem(args[1].text);
              break;
            }
            case 'set': {
              const { plain, fields } = splitFields(args);
              if (plain.length) throw new Error('set takes key=value words only');
              setFields(current, fields);
              break;
            }
            default:
              throw new Error(`unknown command "${cmd}"`);
          }
        }
      }
    } catch (e) {
      if (e instanceof ScenarioSyntaxError) throw e;
      throw new ScenarioSyntaxError(file, lineNo, e.message);
    }
  }

  for (const { id, side, p, line } of laterPeripherals) {
    const def = byId.get(id);
    if (!def) throw new ScenarioSyntaxError(file, line, `peripheral for computer ${id}, which is not defined`);
    def.peripherals[side] = p;
  }
  for (const def of computers) delete def.line;
  for (const c of checks) delete c.currentLine;
  timeline.sort((a, b) => a.at - b.at);

  return {
    key,
    file,
    name: name || key || 'Scenario',
    description: description.join(' '),
    build(world) { for (const op of ops) op(world); },
    computers,
    timeline,
    checks,
  };
}

// Parse a .check file: only check blocks, each naming its scenario.
export function parseChecks(text, { file = null } = {}) {
  const checks = [];
  let check = null;
  const lines = text.split(/\r?\n/);
  for (let n = 0; n < lines.length; n++) {
    const lineNo = n + 1;
    try {
      const words = tokenize(lines[n]);
      if (!words.length) continue;
      const cmd = words[0].text;
      const args = words.slice(1);
      if (cmd === 'check') {
        check = newCheck(rest(args) || `check ${checks.length + 1}`, file, lineNo);
        checks.push(check);
        continue;
      }
      if (!check) throw new Error(`"${cmd}" before the first check line`);
      check.currentLine = lineNo;
      if (!checkLine(check, cmd, args)) throw new Error(`"${cmd}" is not a check line (scenario, run, on, seconds, until, expect)`);
    } catch (e) {
      throw new ScenarioSyntaxError(file, lineNo, e.message);
    }
  }
  for (const c of checks) {
    delete c.currentLine;
    if (!c.scenario) throw new ScenarioSyntaxError(file, c.line, `check "${c.name}" names no scenario`);
  }
  return checks;
}

// Load scenario files given their names (e.g. "quarry-file.scn") and
// a function that reads one by name. Returns { key: scenario } in the
// given order and a list of errors; a bad file is skipped, not fatal.
export async function loadScenarioFiles(names, readText) {
  const scenarios = {};
  const errors = [];
  for (const fileName of names) {
    if (!fileName.endsWith('.scn')) continue;
    const key = fileName.replace(/^.*\//, '').replace(/\.scn$/, '');
    try {
      scenarios[key] = parseScenario(await readText(fileName), { key, file: fileName });
    } catch (e) {
      errors.push(e);
    }
  }
  return { scenarios, errors };
}
