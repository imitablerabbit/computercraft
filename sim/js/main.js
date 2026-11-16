// Boot the simulator in the browser: fetch the repo's lua files from
// serve.py, build the simulation, the 3D view and the panels, then run
// the frame loop.

import { Simulation } from './simulation.js';
import { SCENARIOS } from './scenarios.js';
import { View3D } from './view3d.js';
import { UI } from './ui.js';
import { loadScenarioFiles } from './scenariofile.js';

async function fetchText(url) {
  const r = await fetch(url, { cache: 'no-store' });
  if (!r.ok) throw new Error(`${url}: ${r.status}`);
  return r.text();
}

async function loadFiles() {
  const list = (await fetchText('/files.txt')).split('\n').map((s) => s.trim()).filter(Boolean);
  const files = new Map();
  await Promise.all(list.map(async (p) => files.set(p, await fetchText('/' + p))));
  return files;
}

// The .scn files named in sim/scenarios/index.json (the browser cannot
// list a folder). A missing index or a bad file only costs that file.
async function loadFileScenarios() {
  let names;
  try {
    names = JSON.parse(await fetchText('/sim/scenarios/index.json'));
  } catch (e) {
    console.warn('no scenario files:', e.message);
    return {};
  }
  const { scenarios, errors } = await loadScenarioFiles(names, (name) => fetchText(`/sim/scenarios/${name}`));
  for (const e of errors) console.error(e.message);
  return scenarios;
}

async function main() {
  const status = document.getElementById('status');
  status.textContent = 'loading files...';
  if (!window.fengari) { status.textContent = 'fengari failed to load (no internet for the CDN?)'; return; }
  const [files, biosSource, fileScenarios] = await Promise.all([loadFiles(), fetchText('/sim/lua/bios.lua'), loadFileScenarios()]);
  // Scenario files are listed after the built-in ones, which win a
  // clash of names.
  const scenarios = { ...SCENARIOS };
  for (const [k, s] of Object.entries(fileScenarios)) if (!scenarios[k]) scenarios[k] = s;
  const sim = new Simulation({ fengari: window.fengari, files, biosSource });
  const view = new View3D(document.getElementById('view3d'), sim, (id) => ui.selectTurtle(id));
  const ui = new UI(sim, scenarios, view);
  // ?scenario=quarry picks the world; ?run=quarry 3 3 2 replaces what the
  // first turtle runs at boot so a test can be started from the address bar.
  const params = new URLSearchParams(location.search);
  const key = params.get('scenario');
  const initial = key && scenarios[key] ? key : 'control';
  document.getElementById('scenario').value = initial;
  ui.loadScenario(initial, params.get('run'));

  let last = performance.now();
  function frame(now) {
    const dt = Math.min(0.1, (now - last) / 1000);
    last = now;
    try {
      sim.advance(dt);
    } catch (e) {
      console.error(e);
      sim.log({ computer: '-', text: `simulator error: ${e.message}`, level: 'error' });
      sim.paused = true;
    }
    view.update();
    ui.update(now);
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
  window.sim = sim; // handy in the devtools console
}

main().catch((e) => {
  console.error(e);
  document.getElementById('status').textContent = `failed to start: ${e.message}`;
});
