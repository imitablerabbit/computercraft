--[[
Build puts up a blueprint (see apis/blueprint.lua for the file format)
layer by layer, flying one block above each layer in a snake and
placing every block with placeDown. The turtle starts on the block in
front of the footprint's front left corner, level with the bottom
layer and facing into the footprint, with a chest of materials beside
it (behind by default; left, right, below, above or none).

Before it starts it prints the materials the blueprint needs and what
the turtle and the chest have, and what is missing; with `check` it
refuses to start while anything is missing. It takes what it needs
from the chest, goes back for more when an item runs out, and when the
chest has run out too it raises an alert listing what is missing and
waits, checking the chest again every so often (or when items are
put into the turtle). Keep the chest for the build's materials: items
that are not needed are put back, and a chest whose first 16 stacks
are all unneeded never gets past them.

`.` cells (air) are dug out only with `clear`; so are blocks in the
way of a block to place and blocks in the way of the turtle while it
flies over a layer. Without it they are left alone, and blocks that
cannot be placed because something is there are counted and reported.
Protected blocks (chests, computers, turtles) are never dug. The
turtle never flies into a layer it has built, so the walls are safe.
At the end it returns to the start, puts unused materials back in the
chest and faces the way it started.

Movement goes through the nav API, so `where` stays right afterwards.
Blocks that need a facing (stairs, doors, torches on walls) are placed
however placeDown puts them.

Usage: build <blueprint> [chest] [clear] [check]
--]]

local args = { ... }
local function usage()
  print("Usage: build <blueprint> [chest] [clear] [check]")
  print("chest: behind (default), left, right, below, above or none")
end

if #args < 1 then usage() return end

local file = args[1]
local chest = "behind"
local clear, strict = false, false
for i = 2, #args do
  local a = args[i]:lower()
  if a == "clear" or (i == 3 and a == "true") then clear = true
  elseif a == "false" or a == "noclear" then clear = false
  elseif a == "check" then strict = true
  elseif a == "none" then chest = nil
  elseif inventory.isChestSide(a) then chest = a
  else
    usage()
    error("unknown option " .. args[i], 0)
  end
end

local path = blueprint.find(file)
if not path then error("no blueprint " .. file .. " (looked here and in /blueprints)", 0) end
local bp, err = blueprint.load(path)
if not bp then error(err, 0) end

local mats = blueprint.materials(bp)
local total = 0
for _, n in pairs(mats) do total = total + n end

-- The short name of an item, for messages.
local function short(name) return (name:gsub("^minecraft:", "")) end

--[[
Where things are: the build frame
--]]

local sx, sy, sz, sh = nav.position()
local origin = { x = sx, y = sy, z = sz, h = sh }

-- Where cell x (column), y (layer), z (row from the front) is.
local function cellPos(x, y, z) return nav.relative(origin, x, y, z + 1) end

-- And back: the cell at a nav position.
local rx, _, rz = nav.relative(origin, 1, 0, 0)
local fx, _, fz = nav.relative(origin, 0, 0, 1)
rx, rz, fx, fz = rx - sx, rz - sz, fx - sx, fz - sz
local function toCell(x, y, z)
  local dx, dz = x - sx, z - sz
  return dx * rx + dz * rz, y - sy, dx * fx + dz * fz - 1
end

-- Layers up to this one are built: the turtle keeps out of them.
local builtUpTo = -1
local function inBuilt(x, y, z)
  local cx, cy, cz = toCell(x, y, z)
  return cx >= 0 and cx < bp.width and cz >= 0 and cz < bp.length and cy >= 0 and cy <= builtUpTo
end

--[[
Inventory and chest
--]]

local function carried()
  local counts = {}
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d then counts[d.name] = (counts[d.name] or 0) + d.count end
  end
  return counts
end

-- Item names the turtle had when it started that are not materials
-- (fuel, tools): never put in the chest.
local ownItems = {}
for name in pairs(carried()) do
  if not mats[name] then ownItems[name] = true end
end

-- The chest's contents by item name, read through the peripheral
-- while the turtle is at the start facing the start heading, or nil
-- when it cannot be read.
local peripheralSide = { left = "left", right = "right", behind = "back", below = "bottom", above = "top" }
local function chestContents()
  if not chest then return nil end
  local side = peripheralSide[chest]
  if not peripheral.isPresent(side) then return nil end
  local ok, list = pcall(peripheral.call, side, "list")
  if not ok or type(list) ~= "table" then return nil end
  local counts = {}
  for _, item in pairs(list) do counts[item.name] = (counts[item.name] or 0) + item.count end
  return counts
end

-- Blocks still to place, by name. Counted down as blocks go in (or
-- turn out to be there already, or cannot be placed).
local remaining = {}
for name, n in pairs(mats) do remaining[name] = n end

local function freeSlot()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then return true end
  end
  return false
end

-- Turn to the chest from the start. Returns its suck, drop and detect.
local function faceChest()
  if chest == "below" then nav.face(sh) return turtle.suckDown, turtle.dropDown, turtle.detectDown end
  if chest == "above" then nav.face(sh) return turtle.suckUp, turtle.dropUp, turtle.detectUp end
  local turnBy = { left = 3, right = 1, behind = 2 }
  nav.face((sh + turnBy[chest]) % 4)
  return turtle.suck, turtle.drop, turtle.detect
end

-- How many of the blocks still to place the turtle is carrying.
local function useful()
  local n = 0
  for name, count in pairs(carried()) do
    n = n + math.min(count, remaining[name] or 0)
  end
  return n
end

-- At the start: take what is needed from the chest and put back what
-- is not. Several passes, since things put back go to the front of
-- the chest and may be picked up again; stops when a pass gains
-- nothing.
local function restock()
  if not chest then return false end
  local suck, drop, detect = faceChest()
  if not detect() then
    alert.raise("chest", "no chest " .. chest .. " of the build start")
    return false
  end
  alert.clear("chest")
  local selected = turtle.getSelectedSlot()
  for pass = 1, 4 do
    local before = useful()
    local emptied = false
    while freeSlot() do
      if not suck() then emptied = true break end
    end
    local keep = {}
    for slot = 1, 16 do
      local d = turtle.getItemDetail(slot)
      if d and not ownItems[d.name] then
        local want = math.max(0, (remaining[d.name] or 0) - (keep[d.name] or 0))
        local kept = math.min(d.count, want)
        keep[d.name] = (keep[d.name] or 0) + kept
        if d.count > kept then
          turtle.select(slot)
          drop(d.count - kept)
        end
      end
    end
    -- Done when nothing is short, the chest ran dry, or this pass
    -- brought nothing new.
    if #blueprint.missing(remaining, carried()) == 0 or emptied or useful() <= before or not freeSlot() then break end
  end
  turtle.select(selected)
  nav.face(sh)
  return true
end

-- What the turtle is short of for the rest of the build.
local function shortList()
  local have = carried()
  local list = {}
  for _, m in ipairs(blueprint.missing(remaining, have)) do
    list[#list + 1] = m.short .. " " .. short(m.name)
  end
  return list
end

--[[
Fuel
--]]

local Reserve = 20 -- fuel kept above the way back to the start

-- Burn fuel the turtle carries that is not a building material.
local function burnSpareFuel()
  local selected = turtle.getSelectedSlot()
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d and not mats[d.name] and not inventory.isFuelBlacklisted(d.name) then
      turtle.select(slot)
      if turtle.refuel(0) then turtle.refuel() end
    end
  end
  turtle.select(selected)
end

local function fuelLevel()
  local f = turtle.getFuelLevel()
  if f == "unlimited" then return math.huge end
  return f
end

-- Wait until there is at least `need` fuel, burning what is put into
-- the turtle (but never the materials).
local function waitForFuel(need)
  burnSpareFuel()
  if fuelLevel() >= need then return end
  alert.raise("fuel", "needs " .. need .. " fuel, has " .. fuelLevel() .. ": add fuel to the turtle")
  while fuelLevel() < need do
    os.pullEvent("turtle_inventory")
    burnSpareFuel()
  end
  alert.clear("fuel")
end

--[[
Moving
--]]

local moveOpts = { dig = clear, blocked = inBuilt }

local function goStart()
  local ok, why = nav.goTo(sx, sy, sz, { dig = clear, blocked = inBuilt, heading = sh, force = true })
  if not ok then
    alert.raise("stuck", "cannot get back to the start: " .. why)
    error("cannot get back to the start: " .. why, 0)
  end
end

-- Make sure there is fuel to get to x, y, z and back to the start
-- afterwards; if not, go to the start and wait for some there.
local function fuelFor(x, y, z)
  local cx, cy, cz = nav.position()
  local trip = math.abs(x - cx) + math.abs(y - cy) + math.abs(z - cz)
  local back = math.abs(x - sx) + math.abs(y - sy) + math.abs(z - sz)
  if fuelLevel() >= trip + back + Reserve then return end
  burnSpareFuel()
  if fuelLevel() >= trip + back + Reserve then return end
  print("low on fuel, going back to the start")
  goStart()
  waitForFuel(2 * back + Reserve)
end

--[[
Building
--]]

local placed, already, blocked, failed = 0, 0, 0, 0
local layerText = ""
local function reportProgress()
  progress.report(placed + already + blocked + failed, total, layerText)
end

local function cellDone(name, how)
  remaining[name] = math.max(0, (remaining[name] or 0) - 1)
  if how == "placed" then placed = placed + 1
  elseif how == "already" then already = already + 1
  elseif how == "blocked" then blocked = blocked + 1
  else failed = failed + 1 end
  reportProgress()
end

-- Get some of an item into the turtle: back to the chest for more,
-- and if that has none, alert and wait until it does.
local function fetch(name)
  local bx, by, bz = nav.position()
  if chest then
    print("out of " .. short(name) .. ", going to the chest")
    goStart()
    restock()
  end
  local said
  while not inventory.select(name) do
    local message = "missing " .. table.concat(shortList(), ", ")
    if message ~= said then
      alert.raise("materials", message)
      said = message
    end
    -- Look again when items are put into the turtle, or every 20
    -- seconds for the chest.
    local timer = os.startTimer(20)
    while true do
      local event, id = os.pullEvent()
      if event == "turtle_inventory" or (event == "timer" and id == timer) then break end
    end
    -- Only go through the chest again when it has some (or cannot
    -- be seen into).
    if chest then
      local contents = chestContents()
      if not contents or (contents[name] or 0) > 0 then restock() end
    end
  end
  alert.clear("materials")
  if chest then
    local ok, why = nav.goTo(bx, by, bz, moveOpts)
    if not ok then return false, why end
  end
  return true
end

-- The turtle is right above a cell: make it what the blueprint says.
local function doCell(want)
  local present, info = nav.inspectDown()
  local kind, name = nav.classify(present, info)
  if want == "air" then
    if kind == "s" and clear and not nav.isProtected(name) then nav.digDown() end
    return
  end
  if kind == "s" or kind == "u" or kind == "t" then
    if name == want then cellDone(want, "already") return end
    if not clear or kind ~= "s" or nav.isProtected(name) or not nav.digDown() then
      cellDone(want, "blocked")
      return
    end
  end
  if not inventory.select(want) then
    local ok, why = fetch(want)
    if not ok then
      print("could not get back to the build: " .. tostring(why))
      cellDone(want, "failed")
      return
    end
    inventory.select(want)
  end
  for attempt = 1, 5 do
    if turtle.placeDown() then
      local x, y, z = nav.position()
      nav.record(x, y - 1, z, "s", want)
      cellDone(want, "placed")
      return
    end
    -- a mob or item in the way, or sand still falling
    sleep(1)
  end
  print("could not place " .. short(want))
  cellDone(want, "failed")
end

--[[
Start
--]]

local name = bp.name or fs.getName(path)
print(name .. ": " .. bp.width .. " wide, " .. bp.length .. " long, " .. bp.height .. " high, " .. total .. " blocks")
local inChest = chestContents()
local have = carried()
if inChest then
  for item, n in pairs(inChest) do have[item] = (have[item] or 0) + n end
end
local names = {}
for item in pairs(mats) do names[#names + 1] = item end
table.sort(names)
for _, item in ipairs(names) do
  print(string.format("%5d %s (have %d)", mats[item], short(item), have[item] or 0))
end
if chest and not inChest then print("(cannot see into the chest " .. chest .. ")") end
local missing = blueprint.missing(mats, have)
if #missing > 0 then
  print("Missing:")
  for _, m in ipairs(missing) do print(string.format("%5d %s", m.short, short(m.name))) end
  if strict then error("not starting: materials missing", 0) end
  if chest and inChest then print("starting anyway; the turtle asks when it runs out") end
end
if strict and chest and not inChest then error("not starting: cannot check the chest", 0) end

-- A rough count of the moves: every cell of every layer, the way
-- between rows, and a trip or two to the chest.
local estimate = bp.height * (bp.width * bp.length + bp.width + bp.length) + 2 * (bp.width + bp.length + bp.height)
if fuelLevel() < estimate then burnSpareFuel() end
if fuelLevel() < estimate then
  print("fuel " .. fuelLevel() .. " may not last (about " .. estimate .. " moves); it will ask for more")
end

restock()
progress.report(0, total, "starting")

for layer = 0, bp.height - 1 do
  layerText = "layer " .. (layer + 1) .. " of " .. bp.height
  print(layerText)
  builtUpTo = layer - 1
  for row = 0, bp.length - 1 do
    local first, last, step = 0, bp.width - 1, 1
    if row % 2 == 1 then first, last, step = bp.width - 1, 0, -1 end
    for col = first, last, step do
      local want = blueprint.at(bp, col, layer, row)
      if want and (want ~= "air" or clear) then
        local x, y, z = cellPos(col, layer + 1, row)
        fuelFor(x, y, z)
        local ok, why = nav.goTo(x, y, z, moveOpts)
        if ok then
          doCell(want)
        elseif want ~= "air" then
          print("cannot get above " .. col .. "," .. layer .. "," .. row .. ": " .. tostring(why))
          cellDone(want, "blocked")
        end
      end
    end
  end
  builtUpTo = layer
end

goStart()
-- Put back what was not used.
if chest then
  local suck, drop = faceChest()
  local selected = turtle.getSelectedSlot()
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d and mats[d.name] then
      turtle.select(slot)
      drop()
    end
  end
  turtle.select(selected)
  nav.face(sh)
end
nav.save()
progress.clear()
local summary = "done: placed " .. placed .. " blocks"
if already > 0 then summary = summary .. ", " .. already .. " already there" end
if blocked > 0 then summary = summary .. ", " .. blocked .. " blocked" end
if failed > 0 then summary = summary .. ", " .. failed .. " failed" end
print(summary)
