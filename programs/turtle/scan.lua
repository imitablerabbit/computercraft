--[[
Scan writes a blueprint (see apis/blueprint.lua) of what is in a
width x length x height box, so build can put up a copy somewhere
else. The turtle starts where build would: on the block in front of
the box's front left corner, level with its bottom layer, facing in.

A turtle can only look at the blocks right next to it, and scan never
digs, so it explores the air in and around the box (one block beyond
its sides, back and top) and looks at every block it can reach from
there: up and down from every cell it visits, and sideways where it
does not know the block yet. That sees every block of a building that
touches air the turtle can get to, inside or out; blocks it never saw
(inside a solid wall, or in a sealed room) are written as don't care.
Air inside the box is written as `.`, liquids and turtles as don't
care. Palette characters are given in name order, with readable
defaults (# cobblestone, = planks, o logs, g glass ...).

It returns to the start when done, and stops early, writing what it
has, when fuel gets short of the way back. A file name without a
folder or extension is saved as /blueprints/<name>.lua, where build
finds it by name.

Usage: scan <file> <width> <length> <height>
--]]

local args = { ... }
local file, width, length, height = args[1], tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
if #args ~= 4 or not (width and length and height) then
  print("Usage: scan <file> <width> <length> <height>")
  return
end
if width < 1 or length < 1 or height < 1 or width ~= math.floor(width) or length ~= math.floor(length) or height ~= math.floor(height) then
  error("width, length and height are whole numbers of 1 or more", 0)
end

local path = file
if not file:find("[/%.]") then path = "/blueprints/" .. file .. ".lua" end

local sx, sy, sz, sh = nav.position()
local origin = { x = sx, y = sy, z = sz, h = sh }
local Reserve = 10

-- Cells are column (from the left), layer (from the bottom) and row
-- (from the front, the turtle's own row is -1), as in blueprints.
local function cellPos(c, l, r) return nav.relative(origin, c, l, r + 1) end
local function cellKey(c, l, r) return c .. "," .. l .. "," .. r end
local function inSpace(c, l, r)
  return c >= -1 and c <= width and r >= -1 and r <= length and l >= 0 and l <= height
end
local function inBox(c, l, r)
  return c >= 0 and c < width and r >= 0 and r < length and l >= 0 and l < height
end

-- Headings in the build frame: 0 is into the box (sh), 1 right ...
local steps = { [0] = { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }

local seen = {}      -- cell key -> block name, "air" or "liquid"
local visited = {}   -- cell keys the turtle has been to or given up on
local open = {}      -- air cells to visit: key -> { c, l, r }
local seenCount = 0

local function note(c, l, r, present, info)
  local kind, name = nav.classify(present, info)
  local k = cellKey(c, l, r)
  if kind == "a" then seen[k] = "air"
  elseif kind == "l" or kind == "t" then seen[k] = "liquid"
  else seen[k] = name or "unknown" end
  seenCount = seenCount + 1
  if (kind == "a" or kind == "l") and not visited[k] then open[k] = { c, l, r } end
end

-- Look at everything unknown around the turtle, standing in cell c, l, r.
local function lookAround(c, l, r)
  if inSpace(c, l + 1, r) and not seen[cellKey(c, l + 1, r)] then note(c, l + 1, r, nav.inspectUp()) end
  if inSpace(c, l - 1, r) and not seen[cellKey(c, l - 1, r)] then note(c, l - 1, r, nav.inspectDown()) end
  -- sideways, starting with the way it faces, then the nearest turns
  local _, _, _, h = nav.position()
  local facing = (h - sh) % 4
  for _, turn in ipairs({ 0, 1, 3, 2 }) do
    local d = (facing + turn) % 4
    local nc, nr = c + steps[d][1], r + steps[d][2]
    if inSpace(nc, l, nr) and not seen[cellKey(nc, l, nr)] then
      nav.face((sh + d) % 4)
      note(nc, l, nr, nav.inspect())
    end
  end
end

local function fuelLevel()
  local f = turtle.getFuelLevel()
  if f == "unlimited" then return math.huge end
  return f
end

-- Explore: visit the nearest open cell until none is left.
local c, l, r = 0, 0, -1
seen[cellKey(c, l, r)] = "air"
local stoppedEarly
local cellsInSpace = (width + 2) * (length + 2) * (height + 1)
while true do
  visited[cellKey(c, l, r)] = true
  open[cellKey(c, l, r)] = nil
  lookAround(c, l, r)
  progress.report(math.min(seenCount, cellsInSpace), cellsInSpace, "looking at blocks")
  -- the nearest cell still to visit
  local best, bestD
  for k, cell in pairs(open) do
    local d = math.abs(cell[1] - c) + math.abs(cell[2] - l) + math.abs(cell[3] - r)
    if not bestD or d < bestD then best, bestD = k, d end
  end
  if not best then break end
  local cell = open[best]
  local x, y, z = cellPos(cell[1], cell[2], cell[3])
  local cx, cy, cz = nav.position()
  local back = math.abs(x - sx) + math.abs(y - sy) + math.abs(z - sz)
  local trip = math.abs(x - cx) + math.abs(y - cy) + math.abs(z - cz)
  if fuelLevel() < trip + back + Reserve then
    stoppedEarly = "fuel ran short"
    break
  end
  local ok = nav.goTo(x, y, z, { dig = false, maxReplans = 4 })
  if ok then
    c, l, r = cell[1], cell[2], cell[3]
  else
    -- cannot get there: give up on it, and carry on from wherever
    -- the turtle got to (which is a cell it knows)
    visited[best] = true
    open[best] = nil
    local nx, ny, nz = nav.position()
    local dx, dz = nx - sx, nz - sz
    local rx, _, rz = nav.relative({ x = 0, y = 0, z = 0, h = sh }, 1, 0, 0)
    local fx, _, fz = nav.relative({ x = 0, y = 0, z = 0, h = sh }, 0, 0, 1)
    c, l, r = dx * rx + dz * rz, ny - sy, dx * fx + dz * fz - 1
  end
end

local ok, why = nav.goTo(sx, sy, sz, { heading = sh, force = true })
if not ok then print("could not get back to the start: " .. tostring(why)) end
nav.save()

-- Write the blueprint, giving palette characters in name order.
local bp = blueprint.new(width, length, height)
bp.name = fs.getName(path):gsub("%.lua$", "")
local names, counted = {}, {}
for cc = 0, width - 1 do
  for ll = 0, height - 1 do
    for rr = 0, length - 1 do
      local s = seen[cellKey(cc, ll, rr)]
      if s and s ~= "air" and s ~= "liquid" and not counted[s] then
        counted[s] = true
        names[#names + 1] = s
      end
    end
  end
end
table.sort(names)
for _, n in ipairs(names) do blueprint.charFor(bp, n) end
local unseen = 0
for cc = 0, width - 1 do
  for ll = 0, height - 1 do
    for rr = 0, length - 1 do
      local s = seen[cellKey(cc, ll, rr)]
      if s == nil then unseen = unseen + 1 end
      if s and s ~= "liquid" then blueprint.set(bp, cc, ll, rr, s) end
    end
  end
end
local saved, err = blueprint.save(path, bp)
if not saved then error(err, 0) end
progress.clear()

local mats = blueprint.materials(bp)
local total = 0
for _, n in pairs(mats) do total = total + n end
print("saved " .. path .. ": " .. total .. " blocks")
for _, n in ipairs(names) do
  print(string.format("%5d %s", mats[n], (n:gsub("^minecraft:", ""))))
end
if unseen > 0 then print(unseen .. " blocks never seen (don't care)") end
if stoppedEarly then print("stopped early: " .. stoppedEarly) end
print("done: scanned " .. width .. "x" .. length .. "x" .. height)
