// The side panels: screens with keyboard and mouse, the turtle inventory
// and the log. Plus the top bar controls.

import { itemDisplayName, HEADING_NAMES, ITEMS } from './world.js';

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
      this.sim.world.give(this.selectedTurtle, giveItem.value, count);
    });
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

  buildTabs() {
    const tabs = this.$('tabs');
    tabs.innerHTML = '';
    let firstTerminal = null, firstComputer = null;
    for (const c of this.sim.computers.values()) {
      for (const [side, t] of c.terminals) {
        const b = document.createElement('button');
        const who = c.label ? `${c.label} #${c.id}` : `${c.kind} #${c.id}`;
        b.textContent = side === 'native' ? who : `monitor (${who})`;
        b.dataset.id = c.id; b.dataset.side = side;
        b.addEventListener('click', () => { this.showTerminal(c, t, b); this.canvas.focus(); });
        tabs.appendChild(b);
        if (!firstTerminal) { firstTerminal = t; firstComputer = c; }
      }
    }
    // prefer a monitor if there is one: that is what the user set up to watch
    let chosen = null;
    for (const b of tabs.children) if (b.dataset.side !== 'native' && !chosen) chosen = b;
    if (!chosen) chosen = tabs.firstElementChild;
    if (chosen) chosen.click();
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
        d.className = 'slot' + (i + 1 === t.selected ? ' selected' : '');
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
