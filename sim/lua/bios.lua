--[[
bios.lua is the CraftOS stand-in that every simulated computer boots.
It builds the ComputerCraft APIs (term, window, paintutils, colors, os,
fs, shell, peripheral, rednet, turtle, parallel, textutils, keys ...)
on top of the small `sim` table of host functions the JavaScript side
installs, then runs startup.lua and a shell prompt like the game does.
--]]

local sim = sim
local rawtostring = tostring

-- Lua 5.3 prints integral floats as "5.0"; the game (5.1 style) prints
-- "5". Numbers that cross the host boundary arrive as integers, but
-- divisions still make floats, so tostring hides the ".0".
function tostring(v)
  if math.type(v) == "float" and v == math.floor(v) and math.abs(v) < 2 ^ 53 then
    return string.format("%d", v)
  end
  return rawtostring(v)
end
unpack = table.unpack
loadstring = load

--[[
colors and keys
--]]

colors = {
  white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16, lime = 32, pink = 64, gray = 128,
  lightGray = 256, cyan = 512, purple = 1024, blue = 2048, brown = 4096, green = 8192, red = 16384, black = 32768,
}
function colors.combine(...)
  local r = 0
  for _, c in ipairs({ ... }) do r = r | c end
  return r
end
function colors.subtract(c, ...)
  for _, s in ipairs({ ... }) do c = c & ~s end
  return c
end
function colors.test(c, bit) return c & bit == bit end
function colors.toBlit(c) return string.format("%x", math.floor(math.log(c, 2) + 0.5)) end
function colors.fromBlit(ch) return 2 ^ tonumber(ch, 16) end
colours = setmetatable({ grey = colors.gray, lightGrey = colors.lightGray }, { __index = colors })

keys = {
  space = 32, apostrophe = 39, comma = 44, minus = 45, period = 46, slash = 47,
  zero = 48, one = 49, two = 50, three = 51, four = 52, five = 53, six = 54, seven = 55, eight = 56, nine = 57,
  semicolon = 59, equals = 61, leftBracket = 91, backslash = 92, rightBracket = 93, grave = 96,
  enter = 257, tab = 258, backspace = 259, insert = 260, delete = 261,
  right = 262, left = 263, down = 264, up = 265, pageUp = 266, pageDown = 267, home = 268, ["end"] = 269,
  capsLock = 280, scrollLock = 281, numLock = 282, pause = 284,
  f1 = 290, f2 = 291, f3 = 292, f4 = 293, f5 = 294, f6 = 295, f7 = 296, f8 = 297, f9 = 298, f10 = 299, f11 = 300, f12 = 301,
  leftShift = 340, leftCtrl = 341, leftAlt = 342, rightShift = 344, rightCtrl = 345, rightAlt = 346,
}
for i = 0, 25 do keys[string.char(97 + i)] = 65 + i end
do
  local names = {}
  for name, code in pairs(keys) do if type(code) == "number" then names[code] = name end end
  function keys.getName(code) return names[code] end
end

--[[
Terminals
--]]

local function makeTerm(handle)
  local t = {}
  t.write = function(s) sim.termWrite(handle, tostring(s)) end
  t.blit = function(s, f, b)
    if type(s) ~= "string" or type(f) ~= "string" or type(b) ~= "string" then error("bad argument (string expected)", 2) end
    if #s ~= #f or #s ~= #b then error("Arguments must be the same length", 2) end
    sim.termBlit(handle, s, f, b)
  end
  t.clear = function() sim.termClear(handle) end
  t.clearLine = function() sim.termClearLine(handle) end
  t.scroll = function(n) sim.termScroll(handle, math.floor(tonumber(n) or 0)) end
  t.getSize = function() return sim.termGetSize(handle) end
  t.setCursorPos = function(x, y) sim.termSetCursor(handle, math.floor(tonumber(x) or 1), math.floor(tonumber(y) or 1)) end
  t.getCursorPos = function() return sim.termGetCursor(handle) end
  t.setCursorBlink = function(b) sim.termSetBlink(handle, b and true or false) end
  t.getCursorBlink = function() return sim.termGetBlink(handle) end
  t.setTextColor = function(c)
    if type(c) ~= "number" then error("bad argument #1 (number expected, got " .. type(c) .. ")", 2) end
    sim.termSetColors(handle, c, nil)
  end
  t.setBackgroundColor = function(c)
    if type(c) ~= "number" then error("bad argument #1 (number expected, got " .. type(c) .. ")", 2) end
    sim.termSetColors(handle, nil, c)
  end
  t.getTextColor = function() local f = sim.termGetColors(handle); return f end
  t.getBackgroundColor = function() local _, b = sim.termGetColors(handle); return b end
  t.isColor = function() return sim.termIsColor(handle) end
  t.getLine = function(y) return sim.termGetLine(handle, math.floor(y)) end
  t.setPaletteColor = function() end
  t.getPaletteColor = function() return 0, 0, 0 end
  t.setTextColour, t.setBackgroundColour = t.setTextColor, t.setBackgroundColor
  t.getTextColour, t.getBackgroundColour = t.getTextColor, t.getBackgroundColor
  t.isColour, t.setPaletteColour, t.getPaletteColour = t.isColor, t.setPaletteColor, t.getPaletteColor
  return t
end

local native = makeTerm("native")
local current = native

term = {}
function term.native() return native end
function term.current() return current end
function term.redirect(target)
  if type(target) ~= "table" then error("bad argument #1 (table expected, got " .. type(target) .. ")", 2) end
  local old = current
  current = target
  return old
end
for _, name in ipairs({ "write", "blit", "clear", "clearLine", "scroll", "getSize", "setCursorPos", "getCursorPos",
    "setCursorBlink", "getCursorBlink", "setTextColor", "setBackgroundColor", "getTextColor", "getBackgroundColor",
    "isColor", "getLine", "setPaletteColor", "getPaletteColor", "setTextColour", "setBackgroundColour",
    "getTextColour", "getBackgroundColour", "isColour", "setPaletteColour", "getPaletteColour" }) do
  term[name] = function(...) return current[name](...) end
end

--[[
window: a buffered terminal drawn through to a parent terminal
--]]

window = {}
local function blitChar(c) return string.format("%x", math.floor(math.log(c, 2) + 0.5)) end

function window.create(parent, x, y, width, height, visible)
  if visible == nil then visible = true end
  local lines = {}
  local cx, cy = 1, 1
  local fg, bg = colors.white, colors.black
  local blink = false
  local win = {}

  local function blankLine() return { text = string.rep(" ", width), fg = string.rep(blitChar(fg), width), bg = string.rep(blitChar(bg), width) } end
  local function fill() for i = 1, height do lines[i] = blankLine() end end
  fill()

  local function redrawLine(i)
    if not visible then return end
    local l = lines[i]
    parent.setCursorPos(x, y + i - 1)
    parent.blit(l.text, l.fg, l.bg)
  end
  local function updateCursor()
    if not visible then return end
    if blink and cx >= 1 and cx <= width and cy >= 1 and cy <= height then
      parent.setCursorPos(x + cx - 1, y + cy - 1)
      parent.setCursorBlink(true)
      parent.setTextColor(fg)
    else
      parent.setCursorBlink(false)
    end
  end
  local function put(text, tf, tb)
    if cy < 1 or cy > height then cx = cx + #text; return end
    local start = 1
    local px = cx
    if px < 1 then start = 2 - px; px = 1 end
    local n = math.min(#text - start + 1, width - px + 1)
    if n > 0 then
      local l = lines[cy]
      local function splice(row, s) return row:sub(1, px - 1) .. s:sub(start, start + n - 1) .. row:sub(px + n) end
      l.text, l.fg, l.bg = splice(l.text, text), splice(l.fg, tf), splice(l.bg, tb)
      redrawLine(cy)
    end
    cx = cx + #text
    updateCursor()
  end

  win.write = function(s) s = tostring(s); put(s, string.rep(blitChar(fg), #s), string.rep(blitChar(bg), #s)) end
  win.blit = function(s, f, b)
    if #s ~= #f or #s ~= #b then error("Arguments must be the same length", 2) end
    put(s, f:lower(), b:lower())
  end
  win.clear = function() fill(); if visible then for i = 1, height do redrawLine(i) end end updateCursor() end
  win.clearLine = function() if cy >= 1 and cy <= height then lines[cy] = blankLine(); redrawLine(cy) end updateCursor() end
  win.scroll = function(n)
    n = math.floor(n or 0)
    if n == 0 then return end
    local new = {}
    for i = 1, height do
      local src = i + n
      new[i] = (src >= 1 and src <= height) and lines[src] or blankLine()
    end
    lines = new
    if visible then for i = 1, height do redrawLine(i) end end
    updateCursor()
  end
  win.getSize = function() return width, height end
  win.setCursorPos = function(nx, ny) cx, cy = math.floor(nx), math.floor(ny); updateCursor() end
  win.getCursorPos = function() return cx, cy end
  win.setCursorBlink = function(b) blink = b and true or false; updateCursor() end
  win.getCursorBlink = function() return blink end
  win.setTextColor = function(c) fg = c end
  win.setBackgroundColor = function(c) bg = c end
  win.getTextColor = function() return fg end
  win.getBackgroundColor = function() return bg end
  win.isColor = function() return parent.isColor() end
  win.getLine = function(i) local l = lines[i]; if l then return l.text, l.fg, l.bg end end
  win.setPaletteColor = function() end
  win.getPaletteColor = function() return 0, 0, 0 end
  win.setVisible = function(v) v = v and true or false; if v and not visible then visible = true; win.redraw() else visible = v end end
  win.isVisible = function() return visible end
  win.redraw = function() if visible then for i = 1, height do redrawLine(i) end updateCursor() end end
  win.restoreCursor = updateCursor
  win.getPosition = function() return x, y end
  win.reposition = function(nx, ny, nw, nh, nparent)
    x, y = math.floor(nx), math.floor(ny)
    if nparent then parent = nparent end
    if nw and nh and (nw ~= width or nh ~= height) then
      local old = lines
      width, height = math.floor(nw), math.floor(nh)
      fill()
      for i = 1, math.min(#old, height) do
        local l = old[i]
        local function fit(s, pad) if #s >= width then return s:sub(1, width) end return s .. string.rep(pad, width - #s) end
        lines[i] = { text = fit(l.text, " "), fg = fit(l.fg, blitChar(fg)), bg = fit(l.bg, blitChar(bg)) }
      end
    end
    win.redraw()
  end
  win.setTextColour, win.setBackgroundColour = win.setTextColor, win.setBackgroundColor
  win.getTextColour, win.getBackgroundColour = win.getTextColor, win.getBackgroundColor
  win.isColour, win.setPaletteColour, win.getPaletteColour = win.isColor, win.setPaletteColor, win.getPaletteColor
  return win
end

--[[
paintutils
--]]

paintutils = {}
local function drawPixelInternal(x, y)
  term.setCursorPos(x, y)
  term.write(" ")
end
function paintutils.drawPixel(x, y, c)
  if c then term.setBackgroundColor(c) end
  drawPixelInternal(x, y)
end
function paintutils.drawLine(x1, y1, x2, y2, c)
  if c then term.setBackgroundColor(c) end
  x1, y1, x2, y2 = math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2)
  if x1 == x2 and y1 == y2 then drawPixelInternal(x1, y1); return end
  local minX = math.min(x1, x2)
  local maxX, minY, maxY
  if minX == x1 then minY, maxX, maxY = y1, x2, y2 else minY, maxX, maxY = y2, x1, y1 end
  local xDiff, yDiff = maxX - minX, maxY - minY
  if xDiff > math.abs(yDiff) then
    local y = minY
    local dy = yDiff / xDiff
    for x = minX, maxX do drawPixelInternal(x, math.floor(y + 0.5)); y = y + dy end
  else
    local x = minX
    local dx = xDiff / yDiff
    if maxY >= minY then
      for y = minY, maxY do drawPixelInternal(math.floor(x + 0.5), y); x = x + dx end
    else
      for y = minY, maxY, -1 do drawPixelInternal(math.floor(x + 0.5), y); x = x - dx end
    end
  end
end
function paintutils.drawBox(x1, y1, x2, y2, c)
  if c then term.setBackgroundColor(c) end
  x1, y1, x2, y2 = math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2)
  local minX, maxX = math.min(x1, x2), math.max(x1, x2)
  local minY, maxY = math.min(y1, y2), math.max(y1, y2)
  for x = minX, maxX do drawPixelInternal(x, minY); drawPixelInternal(x, maxY) end
  for y = minY + 1, maxY - 1 do drawPixelInternal(minX, y); drawPixelInternal(maxX, y) end
end
function paintutils.drawFilledBox(x1, y1, x2, y2, c)
  if c then term.setBackgroundColor(c) end
  x1, y1, x2, y2 = math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2)
  local minX, maxX = math.min(x1, x2), math.max(x1, x2)
  local minY, maxY = math.min(y1, y2), math.max(y1, y2)
  local row = string.rep(" ", maxX - minX + 1)
  for y = minY, maxY do term.setCursorPos(minX, y); term.write(row) end
end

--[[
textutils
--]]

textutils = {}
local function serializeImpl(v, tracking, indent)
  local t = type(v)
  if t == "table" then
    if tracking[v] then error("Cannot serialize table with recursive entries", 0) end
    tracking[v] = true
    if next(v) == nil then return "{}" end
    local parts = {}
    local seen = {}
    for i, item in ipairs(v) do
      parts[#parts + 1] = serializeImpl(item, tracking, indent)
      seen[i] = true
    end
    local keys_ = {}
    for k in pairs(v) do if not seen[k] then keys_[#keys_ + 1] = k end end
    table.sort(keys_, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys_) do
      local ks
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then ks = k
      else ks = "[" .. serializeImpl(k, tracking, indent) .. "]" end
      parts[#parts + 1] = ks .. " = " .. serializeImpl(v[k], tracking, indent)
    end
    tracking[v] = nil
    return "{ " .. table.concat(parts, ", ") .. " }"
  elseif t == "string" then
    return string.format("%q", v):gsub("\\\n", "\\n")
  elseif t == "number" then
    if v ~= v then return "0/0" end
    if v == math.huge then return "math.huge" elseif v == -math.huge then return "-math.huge" end
    return tostring(v)
  elseif t == "boolean" or t == "nil" then
    return tostring(v)
  else
    error("Cannot serialize type " .. t, 0)
  end
end
function textutils.serialize(v) return (serializeImpl(v, {}, "")) end
function textutils.unserialize(s)
  if type(s) ~= "string" then error("bad argument #1 (string expected, got " .. type(s) .. ")", 2) end
  local fn = load("return " .. s, "unserialize", "t", { math = { huge = math.huge } })
  if not fn then return nil end
  local ok, result = pcall(fn)
  if ok then return result end
  return nil
end
textutils.serialise, textutils.unserialise = textutils.serialize, textutils.unserialize
function textutils.tabulate(...)
  local rows = { ... }
  local w = term.getSize()
  local columns = 0
  for _, row in ipairs(rows) do if type(row) == "table" then columns = math.max(columns, #row) end end
  if columns == 0 then return end
  local colW = math.floor(w / columns)
  for _, row in ipairs(rows) do
    if type(row) == "number" then
      term.setTextColor(row)
    else
      local x = 1
      for i, cell in ipairs(row) do
        local _, y = term.getCursorPos()
        term.setCursorPos(x, y)
        term.write(tostring(cell):sub(1, colW - 1))
        x = x + colW
      end
      print()
    end
  end
end
textutils.pagedTabulate = textutils.tabulate
function textutils.formatTime(t, twentyFour)
  local h, m = math.floor(t), math.floor((t % 1) * 60)
  if twentyFour then return string.format("%d:%02d", h, m) end
  local suffix = h >= 12 and "PM" or "AM"
  h = h % 12
  if h == 0 then h = 12 end
  return string.format("%d:%02d %s", h, m, suffix)
end
function textutils.urlEncode(s) return (s:gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end)) end
function textutils.serializeJSON(v)
  local t = type(v)
  if t == "table" then
    if #v > 0 or next(v) == nil then
      local parts = {}
      for _, item in ipairs(v) do parts[#parts + 1] = textutils.serializeJSON(item) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local parts = {}
    for k, item in pairs(v) do parts[#parts + 1] = string.format("%q", tostring(k)) .. ":" .. textutils.serializeJSON(item) end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "string" then return string.format("%q", v)
  elseif t == "nil" then return "null"
  else return tostring(v) end
end
textutils.serialiseJSON = textutils.serializeJSON

--[[
os and events
--]]

local localQueue = {}
local serializedMark = "\0serialized"

os = {
  clock = function() return sim.clock() end,
  time = function() return (sim.clock() / 50) % 24 end,
  day = function() return math.floor(sim.clock() / 1200) end,
  epoch = function() return math.floor(sim.clock() * 1000) end,
  getComputerID = function() return sim.id() end,
  getComputerLabel = function() return sim.label() end,
  setComputerLabel = function(l) sim.setLabel(l) end,
  version = function() return "CraftOS 1.8 (simulated)" end,
  startTimer = function(t)
    if type(t) ~= "number" then error("bad argument #1 (number expected, got " .. type(t) .. ")", 2) end
    return sim.startTimer(t)
  end,
  cancelTimer = function(id) sim.cancelTimer(id) end,
  setAlarm = function() return 0 end,
  cancelAlarm = function() end,
  shutdown = function() sim.shutdown(); while true do coroutine.yield() end end,
  reboot = function() sim.reboot(); while true do coroutine.yield() end end,
}
os.computerID, os.computerLabel = os.getComputerID, os.getComputerLabel

function os.queueEvent(name, ...)
  if type(name) ~= "string" then error("bad argument #1 (string expected, got " .. type(name) .. ")", 2) end
  localQueue[#localQueue + 1] = table.pack(name, ...)
end

-- Every pull yields up to the boot loop at the bottom of this file,
-- which hands out events from the host and from os.queueEvent. That
-- way a queued event reaches every coroutine under parallel, as in
-- the game, instead of being eaten by whichever one asked first.
function os.pullEventRaw(filter)
  return coroutine.yield(filter)
end

function os.pullEvent(filter)
  local ev = table.pack(os.pullEventRaw(filter))
  if ev[1] == "terminate" then error("Terminated", 0) end
  return table.unpack(ev, 1, ev.n)
end

function sleep(t)
  local id = os.startTimer(tonumber(t) or 0)
  repeat local _, p = os.pullEvent("timer") until p == id
end
os.sleep = sleep

--[[
Printing and reading
--]]

function write(sText)
  local w, h = term.getSize()
  local x, y = term.getCursorPos()
  local nLinesPrinted = 0
  local function newLine()
    if y + 1 <= h then term.setCursorPos(1, y + 1) else term.scroll(1); term.setCursorPos(1, h) end
    x, y = term.getCursorPos()
    nLinesPrinted = nLinesPrinted + 1
  end
  sText = tostring(sText)
  while #sText > 0 do
    local whitespace = string.match(sText, "^[ \t]+")
    if whitespace then
      term.write(whitespace)
      x, y = term.getCursorPos()
      sText = string.sub(sText, #whitespace + 1)
    end
    local newline = string.match(sText, "^\n")
    if newline then
      newLine()
      sText = string.sub(sText, 2)
    end
    local text = string.match(sText, "^[^ \t\n]+")
    if text then
      sText = string.sub(sText, #text + 1)
      if #text > w then
        while #text > 0 do
          if x > w then newLine() end
          term.write(text)
          text = string.sub(text, w - x + 2)
          x, y = term.getCursorPos()
        end
      else
        if x + #text - 1 > w then newLine() end
        term.write(text)
        x, y = term.getCursorPos()
      end
    end
  end
  return nLinesPrinted
end

function print(...)
  local n = 0
  local args = table.pack(...)
  local parts = {}
  for i = 1, args.n do parts[i] = tostring(args[i]) end
  local line = table.concat(parts, "\t")
  sim.log(line)
  n = n + write(line)
  n = n + write("\n")
  return n
end

function printError(...)
  local c = term.getTextColor()
  if term.isColor() then term.setTextColor(colors.red) end
  print(...)
  term.setTextColor(c)
end

function read(replaceChar, history, completeFn, default)
  term.setCursorBlink(true)
  local line = type(default) == "string" and default or ""
  local pos = #line
  local w = term.getSize()
  local sx = term.getCursorPos()
  local function redraw(clear)
    local scroll = 0
    if sx + pos >= w then scroll = sx + pos - w end
    local _, cy = term.getCursorPos()
    term.setCursorPos(sx, cy)
    local shown = clear and string.rep(" ", #line) or (replaceChar and string.rep(replaceChar, #line) or line)
    term.write(string.sub(shown, scroll + 1))
    term.write(string.rep(" ", math.max(0, w - sx - #shown + scroll + 1)))
    term.setCursorPos(sx + pos - scroll, cy)
  end
  redraw()
  while true do
    local ev, p1 = os.pullEvent()
    if ev == "char" then
      line = line:sub(1, pos) .. p1 .. line:sub(pos + 1)
      pos = pos + 1
      redraw()
    elseif ev == "paste" then
      line = line:sub(1, pos) .. p1 .. line:sub(pos + 1)
      pos = pos + #p1
      redraw()
    elseif ev == "key" then
      if p1 == keys.enter then break
      elseif p1 == keys.backspace and pos > 0 then
        redraw(true)
        line = line:sub(1, pos - 1) .. line:sub(pos + 1)
        pos = pos - 1
        redraw()
      elseif p1 == keys.delete and pos < #line then
        redraw(true)
        line = line:sub(1, pos) .. line:sub(pos + 2)
        redraw()
      elseif p1 == keys.left and pos > 0 then pos = pos - 1; redraw()
      elseif p1 == keys.right and pos < #line then pos = pos + 1; redraw()
      elseif p1 == keys.home then pos = 0; redraw()
      elseif p1 == keys["end"] then pos = #line; redraw()
      end
    elseif ev == "term_resize" then
      w = term.getSize()
      redraw()
    end
  end
  local _, cy = term.getCursorPos()
  term.setCursorBlink(false)
  term.setCursorPos(w + 1, cy)
  print()
  return line
end

--[[
fs: files served by the host (the repo) plus anything written
--]]

fs = {}
local function normalize(path)
  path = tostring(path or ""):gsub("\\", "/")
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then table.remove(parts)
    elseif part ~= "." and part ~= "" then parts[#parts + 1] = part end
  end
  return table.concat(parts, "/")
end
function fs.combine(a, b, ...)
  local path = normalize(a)
  for _, p in ipairs({ b, ... }) do
    p = normalize(p)
    if p ~= "" then path = (path == "" and p) or (path .. "/" .. p) end
  end
  return path
end
function fs.getName(path) path = normalize(path); return path:match("([^/]+)$") or "root" end
function fs.getDir(path) path = normalize(path); return path:match("^(.*)/[^/]+$") or (path == "" and ".." or "") end
function fs.exists(path) return sim.fsExists(normalize(path)) end
function fs.isDir(path) return sim.fsIsDir(normalize(path)) end
function fs.isReadOnly(path) return normalize(path):match("^rom") ~= nil end
function fs.list(path)
  path = normalize(path)
  if not fs.isDir(path) then error("/" .. path .. ": Not a directory", 2) end
  local list = sim.fsList(path)
  table.sort(list)
  return list
end
function fs.getSize(path) local s = sim.fsRead(normalize(path)); return s and #s or 0 end
function fs.getFreeSpace() return 1000000 end
function fs.makeDir(path) sim.fsMakeDir(normalize(path)) end
function fs.delete(path) sim.fsDelete(normalize(path)) end
function fs.move(from, to) sim.fsMove(normalize(from), normalize(to)) end
function fs.copy(from, to) local s = sim.fsRead(normalize(from)); if s then sim.fsWrite(normalize(to), s) end end
function fs.find(wildcard)
  wildcard = normalize(wildcard)
  local dir, pattern = wildcard:match("^(.-)/?([^/]*)$")
  if not wildcard:find("/") then dir, pattern = "", wildcard end
  if not pattern:find("[%*%?]") then
    if fs.exists(wildcard) then return { wildcard } end
    return {}
  end
  if not fs.isDir(dir) then return {} end
  local lua = "^" .. pattern:gsub("[%%%.%-%+%[%]%(%)%^%$]", "%%%0"):gsub("%*", ".*"):gsub("%?", ".") .. "$"
  local out = {}
  for _, name in ipairs(fs.list(dir)) do
    if name:match(lua) then out[#out + 1] = fs.combine(dir, name) end
  end
  table.sort(out)
  return out
end
function fs.open(path, mode)
  path = normalize(path)
  mode = mode or "r"
  local handle = {}
  if mode == "r" or mode == "rb" then
    local data = sim.fsRead(path)
    if data == nil then return nil, "/" .. path .. ": No such file" end
    local pos = 1
    handle.readLine = function(withTrailing)
      if pos > #data then return nil end
      local nl = data:find("\n", pos, true)
      local line
      if nl then
        line = data:sub(pos, withTrailing and nl or nl - 1)
        pos = nl + 1
      else
        line = data:sub(pos)
        pos = #data + 1
      end
      if not withTrailing then line = line:gsub("\r$", "") end
      return line
    end
    handle.readAll = function()
      if pos > #data then return pos == 1 and "" or nil end
      local rest = data:sub(pos)
      pos = #data + 1
      return rest
    end
    handle.read = function(n)
      n = n or 1
      if pos > #data then return nil end
      local s = data:sub(pos, pos + n - 1)
      pos = pos + n
      if mode == "rb" and n == 1 then return s:byte() end
      return s
    end
    handle.close = function() end
    return handle
  elseif mode == "w" or mode == "wb" or mode == "a" or mode == "ab" then
    local buffer = {}
    if mode:sub(1, 1) == "a" then buffer[1] = sim.fsRead(path) or "" end
    local closed = false
    local function flush() if not closed then sim.fsWrite(path, table.concat(buffer)) end end
    handle.write = function(s)
      if type(s) == "number" and mode == "wb" then s = string.char(s) end
      buffer[#buffer + 1] = tostring(s)
    end
    handle.writeLine = function(s) buffer[#buffer + 1] = tostring(s) .. "\n" end
    handle.flush = flush
    handle.close = function() flush(); closed = true end
    flush()
    return handle
  end
  return nil, "Unsupported mode"
end

function loadfile(path, mode, env)
  local f = fs.open(path, "r")
  if not f then return nil, "File not found" end
  local src = f.readAll()
  f.close()
  if type(mode) == "table" then env, mode = mode, nil end
  return load(src, "@" .. fs.getName(path), mode or "t", env or _G)
end
function dofile(path)
  local fn, err = loadfile(path)
  if not fn then error(err, 2) end
  return fn()
end

--[[
peripheral, rednet
--]]

peripheral = {}
local wrapped = {}
function peripheral.getNames()
  local names = {}
  for _, p in ipairs(sim.peripherals()) do names[#names + 1] = p.name end
  return names
end
function peripheral.isPresent(name) return peripheral.getType(name) ~= nil end
function peripheral.getType(name)
  for _, p in ipairs(sim.peripherals()) do if p.name == name then return p.type end end
  return nil
end
function peripheral.wrap(name)
  local ptype = peripheral.getType(name)
  if not ptype then return nil end
  if wrapped[name] then return wrapped[name] end
  local obj
  if ptype == "monitor" then
    obj = makeTerm(name)
    obj.setTextScale = function(s) sim.termSetTextScale(name, tonumber(s) or 1) end
    obj.getTextScale = function() return sim.termGetTextScale(name) end
  elseif ptype == "modem" then
    local open = {}
    obj = {
      open = function(ch) open[ch] = true end,
      close = function(ch) if ch then open[ch] = nil else open = {} end end,
      isOpen = function(ch) return open[ch] == true end,
      isWireless = function() return true end,
      transmit = function() end,
      getNamesRemote = function() return {} end,
    }
  else
    obj = {}
  end
  obj.__name = name
  wrapped[name] = obj
  return obj
end
function peripheral.getMethods(name)
  local obj = peripheral.wrap(name)
  if not obj then return nil end
  local methods = {}
  for k, v in pairs(obj) do if type(v) == "function" then methods[#methods + 1] = k end end
  table.sort(methods)
  return methods
end
function peripheral.call(name, method, ...)
  local obj = peripheral.wrap(name)
  if not obj or not obj[method] then error("No such method " .. tostring(method), 2) end
  return obj[method](...)
end
function peripheral.find(ptype, filter)
  local found = {}
  for _, p in ipairs(sim.peripherals()) do
    if p.type == ptype then
      local obj = peripheral.wrap(p.name)
      if not filter or filter(p.name, obj) then found[#found + 1] = obj end
    end
  end
  return table.unpack(found)
end
function peripheral.getName(obj)
  if type(obj) ~= "table" then error("bad argument #1 (table expected, got " .. type(obj) .. ")", 2) end
  return obj.__name
end

rednet = {}
local openModems = {}
function rednet.open(side)
  if peripheral.getType(side) ~= "modem" then error("No such modem: " .. tostring(side), 2) end
  openModems[side] = true
end
function rednet.close(side) if side then openModems[side] = nil else openModems = {} end end
function rednet.isOpen(side)
  if side then return openModems[side] == true end
  return next(openModems) ~= nil
end
function rednet.send(id, message, protocol)
  if not rednet.isOpen() then return false end
  sim.rednetSend(id, textutils.serialize(message), protocol)
  return true
end
function rednet.broadcast(message, protocol) return rednet.send(-1, message, protocol) end
function rednet.receive(protocol, timeout)
  if type(protocol) == "number" and timeout == nil then protocol, timeout = nil, protocol end
  local timer = timeout and os.startTimer(timeout)
  while true do
    local ev = table.pack(os.pullEvent())
    if ev[1] == "rednet_message" then
      if protocol == nil or ev[4] == protocol then return ev[2], ev[3], ev[4] end
    elseif ev[1] == "timer" and ev[2] == timer then
      return nil
    end
  end
end
function rednet.host() end
function rednet.unhost() end
function rednet.lookup() return nil end
rednet.CHANNEL_BROADCAST, rednet.CHANNEL_REPEAT = 65535, 65533

--[[
parallel
--]]

parallel = {}
local function create(...)
  local fns = table.pack(...)
  local cos = {}
  for i = 1, fns.n do
    if type(fns[i]) ~= "function" then error("bad argument #" .. i .. " (function expected, got " .. type(fns[i]) .. ")", 3) end
    cos[i] = coroutine.create(fns[i])
  end
  return cos
end
local function runUntilLimit(routines, limit)
  local count = #routines
  if count < 1 then return 0 end
  local living = count
  local filters = {}
  local eventData = { n = 0 }
  while true do
    for n = 1, count do
      local r = routines[n]
      if r then
        if filters[r] == nil or filters[r] == eventData[1] or eventData[1] == "terminate" then
          local ok, param = coroutine.resume(r, table.unpack(eventData, 1, eventData.n))
          if not ok then error(param, 0) end
          filters[r] = param
          if coroutine.status(r) == "dead" then
            routines[n] = nil
            living = living - 1
            if living <= limit then return n end
          end
        end
      end
    end
    eventData = table.pack(os.pullEventRaw())
  end
end
function parallel.waitForAny(...) local r = create(...); return runUntilLimit(r, #r - 1) end
function parallel.waitForAll(...) local r = create(...); return runUntilLimit(r, 0) end

--[[
turtle (only on turtles)
--]]

if sim.isTurtle() then
  turtle = {}
  local function action(name)
    return function(arg)
      local ticket = sim.turtleAction(name, arg)
      while true do
        local _, t, ok, reason = os.pullEvent("turtle_response")
        if t == ticket then return ok, reason end
      end
    end
  end
  for _, name in ipairs({ "forward", "back", "up", "down", "turnLeft", "turnRight", "dig", "digUp", "digDown",
      "place", "placeUp", "placeDown", "drop", "dropUp", "dropDown", "suck", "suckUp", "suckDown",
      "attack", "attackUp", "attackDown" }) do
    turtle[name] = action(name)
  end
  local function query(name) return function(...) return sim.turtleQuery(name, ...) end end
  for _, name in ipairs({ "detect", "detectUp", "detectDown", "inspect", "inspectUp", "inspectDown",
      "getSelectedSlot", "getItemCount", "getItemSpace", "getItemDetail", "getFuelLevel", "getFuelLimit",
      "refuel", "transferTo", "compare", "compareUp", "compareDown" }) do
    turtle[name] = query(name)
  end
  turtle.select = function(slot)
    if type(slot) ~= "number" then error("bad argument #1 (number expected, got " .. type(slot) .. ")", 2) end
    local ok, err = sim.turtleQuery("select", slot)
    if not ok then error(err, 2) end
    return true
  end
  turtle.craft = function() return false, "No crafting table" end
  turtle.equipLeft = function() return false, "Nothing to equip" end
  turtle.equipRight = turtle.equipLeft
  turtle.getEquippedLeft = function() return nil end
  turtle.getEquippedRight = turtle.getEquippedLeft
end

http = {
  get = function() return nil, "http is not available in the simulator" end,
  post = function() return nil, "http is not available in the simulator" end,
  request = function() return false end,
  checkURL = function() return false, "http is not available in the simulator" end,
}

--[[
os.loadAPI
--]]

function os.loadAPI(path)
  path = normalize(path)
  local name = fs.getName(path):gsub("%.lua$", "")
  local env = setmetatable({}, { __index = _G })
  local fn, err = loadfile(path, "t", env)
  if not fn then
    printError("Failed to load API " .. name .. ": " .. tostring(err))
    return false
  end
  local ok, runErr = pcall(fn)
  if not ok then
    printError("Failed to load API " .. name .. ": " .. tostring(runErr))
    return false
  end
  local api = {}
  for k, v in pairs(env) do if k ~= "_ENV" then api[k] = v end end
  _G[name] = api
  return true
end
function os.unloadAPI(name) if name ~= "_G" and type(_G[name]) == "table" then _G[name] = nil end end

--[[
shell
--]]

shell = {}
local shellPath = ".:/rom/programs"
local currentDir = ""
local runningProgram = nil
local builtins = {}

function shell.path() return shellPath end
function shell.setPath(p) shellPath = p end
function shell.dir() return currentDir end
function shell.setDir(d) currentDir = normalize(d) end
function shell.resolve(path)
  if path:sub(1, 1) == "/" then return normalize(path) end
  return fs.combine(currentDir, path)
end
function shell.getRunningProgram() return runningProgram end
function shell.resolveProgram(name)
  if builtins[name] then return "rom/programs/" .. name end
  for dir in shellPath:gmatch("[^:]+") do
    local base = (dir == ".") and shell.resolve(name) or fs.combine(dir, name)
    for _, p in ipairs({ base, base .. ".lua" }) do
      if fs.exists(p) and not fs.isDir(p) then return p end
    end
  end
  return nil
end
function shell.programs()
  local list = {}
  for name in pairs(builtins) do list[#list + 1] = name end
  for dir in shellPath:gmatch("[^:]+") do
    local d = (dir == ".") and currentDir or normalize(dir)
    if fs.isDir(d) then
      for _, f in ipairs(fs.list(d)) do
        if not fs.isDir(fs.combine(d, f)) then list[#list + 1] = (f:gsub("%.lua$", "")) end
      end
    end
  end
  table.sort(list)
  return list
end
function shell.aliases() return {} end
function shell.setAlias() end
function shell.exit() end

local function tokenise(line)
  local words = {}
  local quoted = false
  for match in line:gmatch("[^ \"]+\"?") do
    if quoted then
      words[#words] = words[#words] .. " " .. match:gsub("\"", "")
    else
      words[#words + 1] = match:gsub("\"", "")
    end
    if match:sub(-1) == "\"" then quoted = not quoted end
  end
  for i, w in ipairs(words) do words[i] = w:gsub("^\"", "") end
  return words
end

function shell.run(...)
  local line = table.concat({ ... }, " ")
  local words = tokenise(line)
  local name = words[1]
  if not name then return false end
  local args = { table.unpack(words, 2) }
  if builtins[name] then
    local ok, err = pcall(builtins[name], table.unpack(args))
    if not ok then printError(err); return false end
    return true
  end
  local path = shell.resolveProgram(name)
  if not path then printError("No such program"); return false end
  local env = setmetatable({}, { __index = _G })
  local fn, err = loadfile(path, "t", env)
  if not fn then printError(err); return false end
  local previous = runningProgram
  runningProgram = path
  local ok, runErr = pcall(fn, table.unpack(args))
  runningProgram = previous
  if not ok then
    if runErr ~= nil then printError(runErr) end
    return false
  end
  return true
end

builtins.clear = function() term.clear(); term.setCursorPos(1, 1) end
builtins.cd = function(dir)
  if not dir then print(shell.dir()); return end
  local target = shell.resolve(dir)
  if fs.isDir(target) then shell.setDir(target) else printError("Not a directory") end
end
builtins.ls = function(dir)
  local target = dir and shell.resolve(dir) or currentDir
  if not fs.isDir(target) then printError("Not a directory"); return end
  local dirs, files = {}, {}
  for _, f in ipairs(fs.list(target)) do
    if fs.isDir(fs.combine(target, f)) then dirs[#dirs + 1] = f else files[#files + 1] = f end
  end
  if term.isColor() then
    textutils.tabulate(colors.green, dirs, colors.white, files)
  else
    textutils.tabulate(dirs, files)
  end
end
builtins.dir = builtins.ls
builtins.id = function() print("This is computer #" .. os.getComputerID()); local l = os.getComputerLabel(); if l then print("This computer is labelled \"" .. l .. "\"") end end
builtins.label = function(cmd, ...)
  if cmd == "set" then os.setComputerLabel(table.concat({ ... }, " ")); print("Computer label set to \"" .. table.concat({ ... }, " ") .. "\"")
  elseif cmd == "clear" then os.setComputerLabel(nil); print("Computer label cleared")
  else local l = os.getComputerLabel(); if l then print("Computer label is \"" .. l .. "\"") else print("No computer label") end end
end
builtins.programs = function() textutils.tabulate(shell.programs()) end
builtins.reboot = function() os.reboot() end
builtins.shutdown = function() os.shutdown() end
builtins.exit = function() end
builtins.cat = function(path)
  if not path then printError("Usage: cat <file>"); return end
  local f = fs.open(shell.resolve(path), "r")
  if not f then printError("No such file"); return end
  print(f.readAll())
  f.close()
end
builtins.type = builtins.cat
builtins.help = function()
  print("Programs in this repo live in /programs; type `programs` to list them.")
  print("Ctrl+T stops a program, Ctrl+R reboots.")
end
builtins.time = function() print("The time is " .. textutils.formatTime(os.time(), false)) end
builtins.refuel = function(n)
  if not turtle then printError("Requires a turtle"); return end
  local count = tonumber(n) or 64
  local before = turtle.getFuelLevel()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      turtle.refuel(count)
    end
  end
  turtle.select(1)
  print("Fuel level is " .. turtle.getFuelLevel() .. " (was " .. before .. ")")
end

--[[
Boot
--]]

term.setBackgroundColor(colors.black)
term.setTextColor(colors.yellow)
term.clear()
term.setCursorPos(1, 1)
print(os.version())
term.setTextColor(colors.white)

local function runStartup()
  if fs.exists("startup.lua") then shell.run("startup.lua")
  elseif fs.exists("startup") then shell.run("startup") end
end

-- Everything a program can do runs inside the main coroutine below,
-- startup and the scenario command included, so that queued events
-- go through the event loop.
local function shellLoop()
  local ok, err = pcall(runStartup)
  if not ok then printError(err) end

  local autorun = sim.autorun()
  if autorun and autorun ~= "" then
    term.setTextColor(colors.yellow)
    write("> ")
    term.setTextColor(colors.white)
    print(autorun)
    shell.run(autorun)
  end

  while true do
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    write(shell.dir() .. "> ")
    term.setTextColor(colors.white)
    local okRead, line = pcall(read)
    if okRead and line and line:match("%S") then
      shell.run(line)
    elseif not okRead then
      print()
    end
  end
end

-- The main coroutine and the event loop that feeds it. Events come
-- from the host (yielded for) or from os.queueEvent (the local
-- queue), and only reach the program when they match its filter.
local main = coroutine.create(shellLoop)
local started, filter = coroutine.resume(main)
if not started then error(filter, 0) end
while coroutine.status(main) ~= "dead" do
  local ev
  if #localQueue > 0 then
    ev = table.remove(localQueue, 1)
  else
    ev = table.pack(coroutine.yield(filter))
  end
  local accept = true
  if ev[1] == "rednet_message" then
    if not rednet.isOpen() then
      accept = false
    elseif ev[5] == serializedMark then
      ev[3] = textutils.unserialize(ev[3])
      ev[5] = nil
      ev.n = 4
    end
  end
  if accept and (filter == nil or ev[1] == filter or ev[1] == "terminate") then
    local ok, result = coroutine.resume(main, table.unpack(ev, 1, ev.n))
    if not ok then error(result, 0) end
    filter = result
    if coroutine.status(main) == "dead" then break end
  end
end
