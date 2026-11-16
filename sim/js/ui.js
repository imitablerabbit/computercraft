// The side panels: screens with keyboard and mouse, the turtle inventory
// and the log. Plus the top bar controls.

import { itemDisplayName, HEADING_NAMES, ITEMS, BLOCKS } from './world.js';

// KeyboardEvent.code -> ComputerCraft key code (GLFW numbering).
const KEYS = {
  Space: 32, Quote: 39, Comma: 44, Minus: 45, Period: 46, Slash: 47, Semicolon: 59, Equal: 61,
  BracketLeft: 91, Backslash: 92, BracketRight: 93, Backquote: 96,
  Enter: 257, NumpadEnter: 257, Tab: 258, Backspace: 259, Insert: 260, Delete: 261,
  ArrowRight: 262, ArrowLeft: 263, ArrowDown: 264, ArrowUp: 265, PageUp: 266, PageDown: 267, Home: 268, End: 269,
  CapsLock: 280, ShiftLeft: 340, ControlLeft: 341, AltLeft: 342, ShiftRight: 344, ControlRight: 345, AltRight: 346,
};
for (let i = 0; i < 26; i++) KEYS['Key' + String.fromCharCode(65 + i)] = 65 + i;
for (let i = 0; i < 10; i++) KEYS['Digit' + i] = 48 + i;
for (let i = 1; i <= 12; i++) KEYS['F' + i] = 289 + i;

export class UI {
  constructor(sim, scenarios, view) {
    this.sim = sim;
    this.scenarios = scenarios;
    this.view = view;
    this.$ = (id) => document.getElementById(id);
    this.activeTerminal = null;
    this.activeComputer = null;
    this.selectedTurtle = null;
    this.giveSlot = null; // inventory slot Give puts items in, or null for any
    this.zoom = 'fit';
    this.blinkOn = true;
    this.lastBlink = 0;
    this.renderedVersion = -1;
    this.logCount = 0;
    this.canvas = this.$('screen');
    this.ctx = this.canvas.getContext('2d');
    this._wire();
  }

  _wire() {
    const sel = this.$('scenario');
    for (const [key, s] of Object.entries(this.scenarios)) {
      const o = document.createElement('option');
      o.value = key; o.textContent = s.name;
      sel.appendChild(o);
    }
    sel.addEventListener('change', () => this.loadScenario(sel.value));
    this.$('reset').addEventListener('click', () => this.loadScenario(sel.value));
    this.$('pause').addEventListener('click', () => {
      this.sim.paused = !this.sim.paused;
      this.$('pause').textContent = this.sim.paused ? 'Resume' : 'Pause';
    });
    this.$('speed').addEventListener('change', (e) => { this.sim.speed = parseFloat(e.target.value); });
    this.$('zoom').addEventListener('change', (e) => { this.zoom = e.target.value === 'fit' ? 'fit' : parseFloat(e.target.value); this.renderedVersion = -1; });
    this.$('follow').addEventListener('change', (e) => { this.view.follow = e.target.checked; });
    this.$('terminate').addEventListener('click', () => { if (this.activeComputer) this.activeComputer.terminate(); this.canvas.focus(); });
    this.$('reboot').addEventListener('click', () => { if (this.activeComputer) this.activeComputer.reboot(); this.canvas.focus(); });
    this.$('turtle-select').addEventListener('change', (e) => this.selectTurtle(parseInt(e.target.value, 10)));
    const giveItem = this.$('give-item');
    for (const name of Object.keys(ITEMS)) {
      const o = document.createElement('option');
      o.value = name; o.textContent = itemDisplayName(name);
      giveItem.appendChild(o);
    }
    giveItem.value = 'minecraft:coal';
    this.$('give').addEventListener('click', () => {
      if (this.selectedTurtle == null) return;
      const count = Math.max(1, Math.min(64, parseInt(this.$('give-count').value, 10) || 1));
      this.sim.world.give(this.selectedTurtle, giveItem.value, count, this.giveSlot);
    });

    // Block tool in the 3D view
    const blockType = this.$('block-type');
    for (const type of Object.keys(BLOCKS)) {
      if (type === 'computer' || type === 'monitor') continue; // devices come from their own tools
      const o = document.createElement('option');
      o.value = type; o.textContent = type.replace(/_/g, ' ');
      blockType.appendChild(o);
    }
    blockType.value = 'stone';
    blockType.addEventListener('change', () => { this.view.placeType = blockType.value; });
    const hints = {
      select: 'drag to orbit, wheel to zoom, right drag to pan',
      place: 'click a block face to put the chosen block against it; a reconstructor aims at the block it is placed against',
      turtle: 'click a block face to put a turtle against it; it boots to a shell',
      computer: 'click a block face to put a computer against it (it has a modem on top)',
      monitor: 'click a block face to stand the monitor against it; touching a computer attaches it to that computer, otherwise it joins the one chosen in On',
      remove: 'click a block, turtle, computer or monitor to take it away',
    };
    const runOptions = {
      turtle: ['', 'turtleagent', 'inventorygui'],
      computer: ['', 'turtlecontrol', 'registrylistener', 'form', 'files', 'todo', 'layout', 'button', 'input'],
    };
    const showAddForm = (tool) => {
      const kind = tool;
      this.$('add-form').style.display = ['turtle', 'computer', 'monitor'].includes(kind) ? '' : 'none';
      this.$('add-label-wrap').style.display = kind === 'monitor' ? 'none' : '';
      this.$('add-fuel-wrap').style.display = kind === 'turtle' ? '' : 'none';
      this.$('add-run-wrap').style.display = kind === 'monitor' ? 'none' : '';
      this.$('add-on-wrap').style.display = kind === 'monitor' ? '' : 'none';
      this.$('add-on-wrap').title = 'the computer a monitor joins when it does not touch one';
      this.$('add-size-wrap').style.display = kind === 'monitor' ? '' : 'none';
      if (runOptions[kind]) {
        const run = this.$('add-run');
        run.innerHTML = '';
        for (const r of runOptions[kind]) {
          const o = document.createElement('option');
          o.value = r; o.textContent = r || 'nothing (shell)';
          run.appendChild(o);
        }
      }
      if (kind === 'monitor') this.fillComputerSelect();
    };
    this.$('tool').addEventListener('change', (e) => {
      this.view.tool = e.target.value;
      this.$('world-hint').textContent = hints[e.target.value];
      this.$('block-picker').style.display = e.target.value === 'place' ? '' : 'none';
      showAddForm(e.target.value);
    });
    this.$('block-picker').style.display = 'none';
    showAddForm('select');
    this.view.onEdit = (edit) => this.edit(edit);
    this.$('log-clear').addEventListener('click', () => { this.sim.logs.length = 0; this.$('log-lines').innerHTML = ''; this.logCount = 0; });
    this.$('log-net').addEventListener('change', () => this.redrawLog());
    this.$('log-print').addEventListener('change', () => this.redrawLog());

    // Screen input
    this.canvas.addEventListener('mousedown', (e) => {
      e.preventDefault();
      this.canvas.focus();
      if (!this.activeTerminal) return;
      const cell = this.cellAt(e);
      if (cell) this.sim.click(this.activeTerminal, cell.x, cell.y, e.button === 2 ? 2 : e.button === 1 ? 3 : 1);
    });
    this.canvas.addEventListener('contextmenu', (e) => e.preventDefault());
    this.canvas.addEventListener('keydown', (e) => {
      if (!this.activeComputer) return;
      if (e.ctrlKey && !e.altKey) {
        if (e.code === 'KeyT') { e.preventDefault(); this.activeComputer.terminate(); return; }
        if (e.code === 'KeyR') { e.preventDefault(); this.activeComputer.reboot(); return; }
        if (e.code === 'KeyS') { e.preventDefault(); this.activeComputer.shutdown(); return; }
        if (e.code === 'KeyV') return; // paste event follows
      }
      const code = KEYS[e.code];
      if (code === undefined && e.key.length !== 1) return;
      e.preventDefault();
      if (code !== undefined) this.activeComputer.pushEvent(['key', code, e.repeat]);
      if (e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey) this.activeComputer.pushEvent(['char', e.key]);
    });
    this.canvas.addEventListener('keyup', (e) => {
      const code = KEYS[e.code];
      if (code !== undefined && this.activeComputer) this.activeComputer.pushEvent(['key_up', code]);
    });
    this.canvas.addEventListener('paste', (e) => {
      const text = (e.clipboardData || window.clipboardData).getData('text');
      if (text && this.activeComputer) this.activeComputer.pushEvent(['paste', text.split('\n')[0]]);
      e.preventDefault();
    });
  }

  // The list of computers a new monitor can be attached to.
  fillComputerSelect() {
    const sel = this.$('add-computer');
    const previous = sel.value;
    sel.innerHTML = '';
    for (const c of this.sim.computers.values()) {
      if (c.kind === 'turtle') continue;
      const o = document.createElement('option');
      o.value = c.id; o.textContent = c.label ? `${c.label} #${c.id}` : `computer #${c.id}`;
      sel.appendChild(o);
    }
    if (previous && [...sel.options].some((o) => o.value === previous)) sel.value = previous;
  }

  // A click in the 3D view with a tool other than select.
  edit(e) {
    const world = this.sim.world;
    const fail = (text) => this.sim.log({ computer: 'world', text, level: 'error' });
    if (e.tool === 'remove') {
      if (e.turtleId != null) { this.sim.removeComputer(e.turtleId); this.afterDevicesChanged(); return; }
      const mon = this.sim.monitorAt(e.x, e.y, e.z);
      if (mon) { this.sim.removeMonitor(mon.computer, mon.name); this.afterDevicesChanged(); return; }
      const comp = this.sim.computerAt(e.x, e.y, e.z);
      if (comp) { this.sim.removeComputer(comp.id); this.afterDevicesChanged(); return; }
      world.edit(e.x, e.y, e.z, null);
      return;
    }
    if (e.tool === 'place') {
      // a machine aims at the block it was placed against
      let meta;
      if (BLOCKS[this.view.placeType] && BLOCKS[this.view.placeType].machine) {
        const facings = { '1,0': 3, '-1,0': 1, '0,1': 2, '0,-1': 0 };
        meta = { facing: facings[`${e.normal.x},${e.normal.y}`] ?? 0 };
      }
      if (!world.edit(e.x, e.y, e.z, this.view.placeType, meta)) fail(`cannot place at ${e.x},${e.y},${e.z}: a turtle is there`);
      return;
    }
    if (!world.isFree(e.x, e.y, e.z)) { fail(`${e.x},${e.y},${e.z} is not free`); return; }
    const label = this.$('add-label').value.trim() || null;
    const run = this.$('add-run').value;
    if (e.tool === 'turtle') {
      // face away from the block it was placed against
      const headings = { '1,0': 1, '-1,0': 3, '0,1': 0, '0,-1': 2 };
      const heading = headings[`${e.normal.x},${e.normal.y}`] || 0;
      const c = this.sim.addComputer({
        kind: 'turtle', label, advanced: true, pos: { x: e.x, y: e.y, z: e.z }, heading,
        fuel: Math.max(0, parseInt(this.$('add-fuel').value, 10) || 0), slots: [],
        peripherals: { left: { type: 'modem' } }, autorun: run,
      });
      this.afterDevicesChanged();
      this.selectTurtle(c.id);
    } else if (e.tool === 'computer') {
      this.sim.addComputer({
        kind: 'computer', label, advanced: true, pos: { x: e.x, y: e.y, z: e.z },
        peripherals: { top: { type: 'modem' } }, autorun: run,
      });
      this.afterDevicesChanged();
    } else if (e.tool === 'monitor') {
      const computer = this.sim.computers.get(parseInt(this.$('add-computer').value, 10));
      if (!computer && !this.sim.adjacentComputer([{ x: e.x, y: e.y, z: e.z }])) { fail('add a computer first, then a monitor for it'); return; }
      const w = Math.max(1, Math.min(8, parseInt(this.$('add-mw').value, 10) || 1));
      const h = Math.max(1, Math.min(6, parseInt(this.$('add-mh').value, 10) || 1));
      // the array runs sideways along the wall it stands against, and up
      const step = e.normal.x !== 0 ? { x: 0, y: 1 } : { x: 1, y: 0 };
      const blocks = [];
      for (let i = 0; i < w; i++) for (let j = 0; j < h; j++) blocks.push({ x: e.x + i * step.x, y: e.y + i * step.y, z: e.z + j });
      if (!blocks.every((b) => world.isFree(b.x, b.y, b.z))) { fail('not enough room for a ' + w + 'x' + h + ' monitor there'); return; }
      // a monitor touching a computer belongs to it, whatever On says
      const adjacent = this.sim.adjacentComputer(blocks);
      if (adjacent) this.sim.addMonitor(adjacent.computer, blocks, w, h, adjacent.side);
      else this.sim.addMonitor(computer, blocks, w, h);
      this.afterDevicesChanged();
    }
  }

  // Tabs, turtle list and computer list after a device came or went.
  afterDevicesChanged() {
    const active = this.activeComputer ? { id: this.activeComputer.id, side: this.activeTerminal === this.activeComputer.terminal ? 'native' : [...this.activeComputer.terminals].find(([, t]) => t === this.activeTerminal)?.[0] } : null;
    this.buildTabs(active);
    this.fillComputerSelect();
    const t = this.sim.world.turtles.get(this.selectedTurtle);
    this.selectTurtle(t ? t.id : (this.sim.world.turtles.keys().next().value ?? null));
  }

  loadScenario(key, run) {
    let scenario = this.scenarios[key];
    if (run) {
      const computers = scenario.computers.map((c) => ({ ...c }));
      const turtle = computers.find((c) => c.kind === 'turtle') || computers[0];
      if (turtle) turtle.autorun = run;
      scenario = { ...scenario, computers };
    }
    this.sim.load(scenario);
    this.$('description').textContent = scenario.description;
    this.view.reset();
    this.buildTabs();
    const first = this.sim.world.turtles.keys().next();
    this.selectTurtle(first.done ? null : first.value);
    this.$('log-lines').innerHTML = '';
    this.logCount = 0;
    this.renderedVersion = -1;
  }

  // Screens

  // keep is {id, side} of the tab to stay on, when it still exists.
  buildTabs(keep) {
    const tabs = this.$('tabs');
    tabs.innerHTML = '';
    for (const c of this.sim.computers.values()) {
      for (const [side, t] of c.terminals) {
        const b = document.createElement('button');
        const who = c.label ? `${c.label} #${c.id}` : `${c.kind} #${c.id}`;
        b.textContent = side === 'native' ? who : `${side} (${who})`;
        b.dataset.id = c.id; b.dataset.side = side;
        b.addEventListener('click', () => { this.showTerminal(c, t, b); this.canvas.focus(); });
        tabs.appendChild(b);
      }
    }
    let chosen = null;
    if (keep) chosen = [...tabs.children].find((b) => b.dataset.id === String(keep.id) && b.dataset.side === keep.side) || null;
    // otherwise prefer a monitor: that is what the user set up to watch
    if (!chosen) for (const b of tabs.children) if (b.dataset.side !== 'native' && !chosen) chosen = b;
    if (!chosen) chosen = tabs.firstElementChild;
    if (chosen) chosen.click();
    else { this.activeComputer = null; this.activeTerminal = null; }
  }

  showTerminal(computer, terminal, button) {
    this.activeComputer = computer;
    this.activeTerminal = terminal;
    for (const b of this.$('tabs').children) b.classList.toggle('active', b === button);
    this.renderedVersion = -1;
    if (computer.kind === 'turtle') this.selectTurtle(computer.id);
  }

  // Cells are 8x13 pixels at 1x. "fit" picks the largest zoom (up to 2x)
  // at which the whole screen is visible in the panel.
  cellSize() {
    let zoom = this.zoom;
    if (zoom === 'fit') {
      const avail = (this.canvas.parentElement.clientWidth || 400) - 10;
      zoom = this.activeTerminal ? Math.min(2, avail / (this.activeTerminal.width * 8)) : 1.5;
      zoom = Math.max(0.5, Math.floor(zoom * 4) / 4);
    }
    return { w: Math.round(8 * zoom), h: Math.round(13 * zoom) };
  }

  cellAt(e) {
    const rect = this.canvas.getBoundingClientRect();
    const { w, h } = this.cellSize();
    const x = Math.floor((e.clientX - rect.left) / w) + 1;
    const y = Math.floor((e.clientY - rect.top) / h) + 1;
    if (x < 1 || y < 1 || x > this.activeTerminal.width || y > this.activeTerminal.height) return null;
    return { x, y };
  }

  renderScreen(now) {
    const t = this.activeTerminal;
    if (!t) return;
    if (now - this.lastBlink > 400) { this.blinkOn = !this.blinkOn; this.lastBlink = now; if (t.cursorBlink) this.renderedVersion = -1; }
    if (t.version === this.renderedVersion) return;
    const { w, h } = this.cellSize();
    const pw = t.width * w, ph = t.height * h;
    if (this.canvas.width !== pw || this.canvas.height !== ph) { this.canvas.width = pw; this.canvas.height = ph; }
    t.render(this.ctx, w, h, this.blinkOn);
    this.renderedVersion = t.version;
    for (const b of this.$('tabs').children) {
      const c = this.sim.computers.get(parseInt(b.dataset.id, 10));
      b.classList.toggle('dead', !!c && c.state !== 'running');
    }
  }

  // Turtle panel

  selectTurtle(id) {
    if (id !== this.selectedTurtle) this.setGiveSlot(null);
    this.selectedTurtle = id;
    this.view.setSelected(id);
    const sel = this.$('turtle-select');
    sel.innerHTML = '';
    for (const t of this.sim.world.turtles.values()) {
      const o = document.createElement('option');
      o.value = t.id; o.textContent = `${t.label} #${t.id}`;
      if (t.id === id) o.selected = true;
      sel.appendChild(o);
    }
    this.inventoryVersion = -1;
  }

  setGiveSlot(slot) {
    this.giveSlot = slot;
    this.$('give-target').textContent = slot ? `into slot ${slot} (click it again for any slot)` : 'to any slot (click a slot to choose)';
    this.inventoryVersion = -1;
  }

  renderTurtle() {
    const world = this.sim.world;
    const t = world.turtles.get(this.selectedTurtle);
    if (world.version === this.inventoryVersion) return;
    this.inventoryVersion = world.version;
    const info = this.$('turtle-info');
    const inv = this.$('inventory');
    if (!t) { info.textContent = 'no turtles in this scenario'; inv.innerHTML = ''; }
    else {
      const c = this.sim.computers.get(t.id);
      info.textContent = `at (${t.x}, ${t.y}, ${t.z}) facing ${HEADING_NAMES[t.heading]}  fuel ${t.fuel} / ${t.fuelLimit}  slot ${t.selected}` + (c ? `  ${c.state}` : '');
      inv.innerHTML = '';
      t.slots.forEach((s, i) => {
        const d = document.createElement('div');
        d.className = 'slot' + (i + 1 === t.selected ? ' selected' : '') + (i + 1 === this.giveSlot ? ' target' : '');
        d.title = 'click to make this the slot Give fills';
        d.addEventListener('click', () => this.setGiveSlot(this.giveSlot === i + 1 ? null : i + 1));
        let html = `<span class="n">${i + 1}</span>`;
        if (s) {
          const def = ITEMS[s.name] || {};
          html += `<span class="name" title="${s.name}">${itemDisplayName(s.name)}</span><span class="count">${s.count}</span>`;
          if (def.fuel) html += `<span class="fuel">F</span>`;
        }
        d.innerHTML = html;
        inv.appendChild(d);
      });
    }
    const cont = this.$('containers');
    cont.innerHTML = '';
    for (const [k, slots] of world.containers) {
      const items = slots.filter(Boolean);
      const d = document.createElement('div');
      d.className = 'chest';
      d.innerHTML = `<strong>chest ${k}</strong> ` + (items.length ? items.map((s) => `${itemDisplayName(s.name)} x${s.count}`).join(', ') : '<span class="muted">empty</span>');
      cont.appendChild(d);
    }
  }

  // Log

  logLine(entry) {
    if (entry.level === 'net' && !this.$('log-net').checked) return null;
    if (!entry.level && entry.text && !this.$('log-print').checked && !/^(dug|placed|put|took|dropped|burnt|inventory)/.test(entry.text)) return null;
    const d = document.createElement('div');
    if (entry.level) d.className = entry.level;
    d.innerHTML = `<span class="time">${entry.at.toFixed(1).padStart(6)}</span> <span class="who">#${entry.computer}</span> ${escapeHtml(entry.text)}`;
    return d;
  }

  redrawLog() {
    const box = this.$('log-lines');
    box.innerHTML = '';
    for (const e of this.sim.logs) { const d = this.logLine(e); if (d) box.appendChild(d); }
    this.logCount = this.sim.logs.length;
    box.scrollTop = box.scrollHeight;
  }

  renderLog() {
    const logs = this.sim.logs;
    if (logs.length === this.logCount) return;
    const box = this.$('log-lines');
    if (logs.length < this.logCount) { this.redrawLog(); return; }
    const atBottom = box.scrollHeight - box.scrollTop - box.clientHeight < 40;
    for (let i = this.logCount; i < logs.length; i++) { const d = this.logLine(logs[i]); if (d) box.appendChild(d); }
    while (box.children.length > 400) box.removeChild(box.firstChild);
    this.logCount = logs.length;
    if (atBottom) box.scrollTop = box.scrollHeight;
  }

  update(now) {
    this.renderScreen(now);
    this.renderTurtle();
    this.renderLog();
    this.$('clock').textContent = `${this.sim.clock.toFixed(1)} s`;
    const running = [...this.sim.computers.values()].filter((c) => c.state === 'running').length;
    this.$('status').textContent = `${running}/${this.sim.computers.size} computers running`;
  }
}

function escapeHtml(s) { return String(s).replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c])); }
