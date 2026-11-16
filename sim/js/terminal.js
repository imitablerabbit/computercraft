// A ComputerCraft terminal: a grid of characters with a text and a
// background colour each, the cursor, and the current colours. Both the
// computers' own screens and monitors are Terminals. Rendering to a
// canvas lives here too so the panels look like the game.

export const PALETTE = [
  '#f0f0f0', '#f2b233', '#e57fd8', '#99b2f2', '#dede6c', '#7fcc19', '#f2b2cc', '#4c4c4c',
  '#999999', '#4c99b2', '#b266e5', '#3366cc', '#7f664c', '#57a64e', '#cc4c4c', '#111111',
];

// Greyscale palette for basic (non advanced) computers and monitors.
const GREY_PALETTE = PALETTE.map((hex) => {
  const r = parseInt(hex.slice(1, 3), 16), g = parseInt(hex.slice(3, 5), 16), b = parseInt(hex.slice(5, 7), 16);
  const l = Math.round(0.299 * r + 0.587 * g + 0.114 * b);
  const h = l.toString(16).padStart(2, '0');
  return `#${h}${h}${h}`;
});

export const HEX = '0123456789abcdef';

// colors.* value (1, 2, 4 ... 32768) to palette index 0..15.
export function colorIndex(value) {
  const n = Math.round(Math.log2(value));
  return Math.min(15, Math.max(0, n));
}

// Size in characters of a monitor made of w x h blocks at a text scale.
export function monitorSize(blocksW, blocksH, scale) {
  return {
    width: Math.max(1, Math.round((64 * blocksW - 20) / (6 * scale))),
    height: Math.max(1, Math.round((64 * blocksH - 20) / (9 * scale))),
  };
}

export class Terminal {
  constructor(name, width, height, { color = true, kind = 'computer', blocksW = 1, blocksH = 1, scale = 1 } = {}) {
    this.name = name;
    this.kind = kind;
    this.color = color;
    this.blocksW = blocksW;
    this.blocksH = blocksH;
    this.scale = scale;
    this.version = 0;
    this.resize(width, height);
    this.cursorBlink = false;
    this.onResize = null;
  }

  resize(width, height) {
    this.width = width;
    this.height = height;
    this.text = [];
    this.fg = [];
    this.bg = [];
    this.textColor = 1;
    this.backColor = 32768;
    this.cursorX = 1;
    this.cursorY = 1;
    for (let y = 0; y < height; y++) {
      this.text.push(' '.repeat(width));
      this.fg.push('0'.repeat(width));
      this.bg.push('f'.repeat(width));
    }
    this.version++;
  }

  getSize() { return [this.width, this.height]; }
  isColor() { return this.color; }
  getCursorPos() { return [this.cursorX, this.cursorY]; }
  setCursorPos(x, y) { this.cursorX = Math.floor(x); this.cursorY = Math.floor(y); this.version++; }
  setCursorBlink(b) { this.cursorBlink = !!b; this.version++; }
  getTextColor() { return this.textColor; }
  getBackgroundColor() { return this.backColor; }
  setTextColor(c) { this.textColor = c; }
  setBackgroundColor(c) { this.backColor = c; }

  // Monitors only: changing the scale changes the size in characters.
  setTextScale(scale) {
    if (this.kind !== 'monitor') return;
    this.scale = scale;
    const { width, height } = monitorSize(this.blocksW, this.blocksH, scale);
    if (width !== this.width || height !== this.height) {
      this.resize(width, height);
      if (this.onResize) this.onResize();
    }
  }
  getTextScale() { return this.scale; }

  // Put a run of characters with per-cell colours at the cursor, clipped
  // to the row, then advance the cursor.
  _put(text, fg, bg) {
    const y = this.cursorY;
    let x = this.cursorX;
    if (y >= 1 && y <= this.height) {
      let start = 0;
      if (x < 1) { start = 1 - x; x = 1; }
      const avail = this.width - x + 1;
      const len = Math.min(text.length - start, avail);
      if (len > 0) {
        const splice = (row, s) => row.slice(0, x - 1) + s.slice(start, start + len) + row.slice(x - 1 + len);
        this.text[y - 1] = splice(this.text[y - 1], text);
        this.fg[y - 1] = splice(this.fg[y - 1], fg);
        this.bg[y - 1] = splice(this.bg[y - 1], bg);
      }
    }
    this.cursorX += text.length;
    this.version++;
  }

  write(text) {
    const n = text.length;
    this._put(text, HEX[colorIndex(this.textColor)].repeat(n), HEX[colorIndex(this.backColor)].repeat(n));
  }

  blit(text, fg, bg) {
    if (fg.length !== text.length || bg.length !== text.length) throw new Error('Arguments must be the same length');
    this._put(text, fg.toLowerCase(), bg.toLowerCase());
  }

  clear() {
    const f = HEX[colorIndex(this.textColor)], b = HEX[colorIndex(this.backColor)];
    for (let y = 0; y < this.height; y++) {
      this.text[y] = ' '.repeat(this.width);
      this.fg[y] = f.repeat(this.width);
      this.bg[y] = b.repeat(this.width);
    }
    this.version++;
  }

  clearLine() {
    const y = this.cursorY;
    if (y < 1 || y > this.height) return;
    this.text[y - 1] = ' '.repeat(this.width);
    this.fg[y - 1] = HEX[colorIndex(this.textColor)].repeat(this.width);
    this.bg[y - 1] = HEX[colorIndex(this.backColor)].repeat(this.width);
    this.version++;
  }

  scroll(n) {
    n = Math.floor(n);
    if (n === 0) return;
    const f = HEX[colorIndex(this.textColor)], b = HEX[colorIndex(this.backColor)];
    const blank = () => [' '.repeat(this.width), f.repeat(this.width), b.repeat(this.width)];
    const rows = this.text.map((t, i) => [t, this.fg[i], this.bg[i]]);
    const out = [];
    for (let y = 0; y < this.height; y++) {
      const src = y + n;
      out.push(src >= 0 && src < this.height ? rows[src] : blank());
    }
    this.text = out.map((r) => r[0]);
    this.fg = out.map((r) => r[1]);
    this.bg = out.map((r) => r[2]);
    this.version++;
  }

  getLine(y) {
    if (y < 1 || y > this.height) return null;
    return [this.text[y - 1], this.fg[y - 1], this.bg[y - 1]];
  }

  // Plain text dump, one string per row (for tests and the log).
  dump() { return this.text.join('\n'); }

  // Draw onto a 2D canvas context at the given cell size in pixels.
  render(ctx, cellW, cellH, blinkOn = true) {
    const palette = this.color ? PALETTE : GREY_PALETTE;
    ctx.font = `${Math.floor(Math.min(cellH * 0.85, cellW / 0.6))}px "DejaVu Sans Mono", "Consolas", monospace`;
    ctx.textBaseline = 'middle';
    ctx.textAlign = 'center';
    for (let y = 0; y < this.height; y++) {
      const text = this.text[y], fg = this.fg[y], bg = this.bg[y];
      for (let x = 0; x < this.width; x++) {
        ctx.fillStyle = palette[HEX.indexOf(bg[x])] || '#111111';
        ctx.fillRect(x * cellW, y * cellH, cellW, cellH);
        const ch = text[x];
        if (ch !== ' ') {
          ctx.fillStyle = palette[HEX.indexOf(fg[x])] || '#f0f0f0';
          ctx.fillText(renderable(ch), x * cellW + cellW / 2, y * cellH + cellH / 2 + 1);
        }
      }
    }
    if (this.cursorBlink && blinkOn && this.cursorX >= 1 && this.cursorX <= this.width && this.cursorY >= 1 && this.cursorY <= this.height) {
      ctx.fillStyle = palette[colorIndex(this.textColor)];
      ctx.fillText('_', (this.cursorX - 1) * cellW + cellW / 2, (this.cursorY - 1) * cellH + cellH / 2 + 1);
    }
  }
}

// ComputerCraft has its own glyphs below 32 and above 126; show a few
// of the common ones with similar unicode characters.
const GLYPHS = { 7: '•', 4: '◆', 15: '☀', 16: '►', 17: '◄', 24: '↑', 25: '↓', 26: '→', 27: '←', 30: '▲', 31: '▼', 127: '░', 128: '░', 129: '█' };
function renderable(ch) {
  const c = ch.charCodeAt(0);
  if (c >= 32 && c < 127) return ch;
  return GLYPHS[c] || '□';
}
