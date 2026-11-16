// Boot the simulator in the browser: fetch the repo's lua files from
// serve.py, build the simulation, the 3D view and the panels, then run
// the frame loop.

import { Simulation } from './simulation.js';
import { SCENARIOS } from './scenarios.js';
import { View3D } from './view3d.js';
import { UI } from './ui.js';

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

async function main() {
  const status = document.getElementById('status');
  status.textContent = 'loading files...';
  if (!window.fengari) { status.textContent = 'fengari failed to load (no internet for the CDN?)'; return; }
  const [files, biosSource] = await Promise.all([loadFiles(), fetchText('/sim/lua/bios.lua')]);
  const sim = new Simulation({ fengari: window.fengari, files, biosSource });
  const view = new View3D(document.getElementById('view3d'), sim, (id) => ui.selectTurtle(id));
  const ui = new UI(sim, SCENARIOS, view);
  // ?scenario=quarry picks the world; ?run=quarry 3 3 2 replaces what the
  // first turtle runs at boot so a test can be started from the address bar.
  const params = new URLSearchParams(location.search);
  const key = params.get('scenario');
  const initial = key && SCENARIOS[key] ? key : 'control';
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
