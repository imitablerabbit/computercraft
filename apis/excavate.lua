--[[
Excavate clears a width x length x height box of blocks next to the
turtle, one layer at a time, and brings everything it digs back to a
chest. It is the engine behind the quarry (digging down) and flatten
(clearing upward) programs.

The turtle starts on the near edge of the footprint, looking along the
length: length is straight ahead and width runs sideways. Where on the
edge is the start: at the left end (width is all to the right), the
right end (width is all to the left) or the middle (width spread both
ways; an even width puts the extra column on the right). For "down"
the first layer is the one directly below the turtle; for "up" it is
the turtle's own layer. Whenever the inventory fills up, and when the
job ends, the turtle goes back to where it started, turns to the chest
beside it, empties itself into it and carries on.

Position is tracked relative to the start: x to the right, y forward,
z along the digging direction (so z grows while going down in a
quarry and while going up when flattening). Heading 0 faces forward,
1 right, 2 back, 3 left.

The chest can also be "depot": instead of a chest beside the start,
the turtle empties itself at the nearest dump chest of a depot
(apis/depot.lua), straight from wherever it is when it fills up, and
comes back to the same block and heading to carry on. That needs nav
in Minecraft coordinates (gps), which run checks before it digs
anything. excavate moves the turtle itself, so before each trip it
tells nav where the turtle is (from the start's nav position and its
own tracking) and marks its own way out of the hole as known air, so
nav's route leaves the hole the way excavate would.
--]]

MaxAttempts = 30 -- tries to dig or attack through one blocked move
FuelMargin = 10  -- fuel kept spare above the distance home

-- Where the turtle stands on the near edge of the footprint.
Starts = { "left", "middle", "right" }
DefaultStart = "left"

local pos, heading, direction, firstLayer, chest
local origin -- nav's position and heading at the start, for depot trips
local stranded -- a depot trip did not get back, so pos is not to be trusted
local xMin, xMax -- the footprint's columns, relative to the start
local dug, dumps
local cells, cellsTotal, layerEnd, layerText -- progress: cells cleared of all of them

-- One more cell of the box cleared (see the progress api). Cells walked
-- twice (getting to the corner from a middle start) do not count twice
-- past the end of the layer.
local function cellDone()
  cells = math.min(cells + 1, layerEnd)
  progress.report(cells, cellsTotal, layerText)
end

function isStart(start)
  for i, s in ipairs(Starts) do
    if s == start then return true end
  end
  return false
end

-- The leftmost and rightmost columns of a footprint, relative to a
-- turtle standing at the start position on its near edge.
function columns(width, start)
  if start == "right" then return 1 - width, 0 end
  if start == "middle" then
    local left = math.floor((width - 1) / 2)
    return -left, width - 1 - left
  end
  return 0, width - 1
end

-- Why a chest on that side cannot be used with this box: it is inside
-- the area to clear. nil when it is fine.
function chestConflict(width, length, height, dir, side, start)
  local offsets = { left = { -1, 0, 0 }, right = { 1, 0, 0 }, behind = { 0, -1, 0 }, below = { 0, 0, -1 }, above = { 0, 0, 1 } }
  local o = offsets[side]
  if not o then return nil end
  local x, y, z = o[1], o[2], o[3]
  local x0, x1 = columns(width, start or DefaultStart)
  local first = (dir == "down") and -1 or 0
  local last = (dir == "down") and -height or (height - 1)
  local inside = x >= x0 and x <= x1 and y >= 0 and y < length
    and ((dir == "down" and z <= first and z >= last) or (dir == "up" and z >= first and z <= last))
  if inside then
    return "the chest " .. side .. " is inside the area to clear"
  end
  return nil
end

-- The chest sides that work with this box.
function chestSides(width, length, height, dir, start)
  local sides = {}
  for i, side in ipairs(inventory.ChestSides) do
    if not chestConflict(width, length, height, dir, side, start) then table.insert(sides, side) end
  end
  return sides
end

--[[
Turning and moving
--]]

local function turnLeft()
  turtle.turnLeft()
  heading = (heading + 3) % 4
end

local function turnRight()
  turtle.turnRight()
  heading = (heading + 1) % 4
end

-- Turn the shortest way to a heading.
local function face(h)
  local diff = (h - heading) % 4
  if diff == 1 then turnRight()
  elseif diff == 2 then turnRight(); turnRight()
  elseif diff == 3 then turnLeft() end
end

-- Fuel moves and burns found fuel when it would not get home otherwise.
local function topUpFuel()
  local fuel = turtle.getFuelLevel()
  if fuel == "unlimited" then return end
  local home = pos.x + pos.y + pos.z + FuelMargin
  if fuel < home then
    inventory.refuelAll()
  end
  move.checkFuel() -- waits for fuel if there is none at all
end

-- Keep digging (or attacking whatever is in the way) until the move
-- succeeds. Returns false when it stays blocked, e.g. at bedrock.
local function tryMove(moveFn, detectFn, digFn)
  topUpFuel()
  for attempt = 1, MaxAttempts do
    if moveFn() then return true end
    if detectFn() then
      if digFn() then dug = dug + 1 end
    else
      turtle.attack()
    end
  end
  return false
end

-- One step in the heading direction, digging through if needed.
local function forward()
  if not tryMove(turtle.forward, turtle.detect, turtle.dig) then return false end
  if heading == 0 then pos.y = pos.y + 1
  elseif heading == 1 then pos.x = pos.x + 1
  elseif heading == 2 then pos.y = pos.y - 1
  else pos.x = pos.x - 1 end
  return true
end

-- One layer further along the digging direction.
local function deeper()
  local ok
  if direction == "down" then
    ok = tryMove(turtle.down, turtle.detectDown, turtle.digDown)
  else
    ok = tryMove(turtle.up, turtle.detectUp, turtle.digUp)
  end
  if ok then pos.z = pos.z + 1 end
  return ok
end

-- One layer back towards the start.
local function shallower()
  local ok
  if direction == "down" then
    ok = tryMove(turtle.up, turtle.detectUp, turtle.digUp)
  else
    ok = tryMove(turtle.down, turtle.detectDown, turtle.digDown)
  end
  if ok then pos.z = pos.z - 1 end
  return ok
end

-- Step to a neighbouring cell on the current layer.
local function stepTo(x, y)
  if x > pos.x then face(1) elseif x < pos.x then face(3)
  elseif y > pos.y then face(0) elseif y < pos.y then face(2)
  else return true end
  return forward()
end

local function moveVertical(z)
  while pos.z < z do if not deeper() then return false end end
  while pos.z > z do if not shallower() then return false end end
  return true
end

-- Cross a cleared layer to a cell, x first then y.
local function moveHorizontal(x, y)
  while pos.x ~= x do if not stepTo(x, pos.y) then return false end end
  while pos.y ~= y do if not stepTo(pos.x, y) then return false end end
  return true
end

--[[
Going home and dumping
--]]

-- Back to the start: up or down to the first layer, which is fully
-- cleared, across to the corner, then to the start level.
local function goHome()
  if not moveVertical(firstLayer) then return false end
  if not moveHorizontal(0, 0) then return false end
  if not moveVertical(0) then return false end
  face(0)
  return true
end

-- Back out to a cell from the start, the same way in reverse.
local function returnTo(target)
  if not moveVertical(firstLayer) then return false end
  if not moveHorizontal(target.x, target.y) then return false end
  if not moveVertical(target.z) then return false end
  face(target.h)
  return true
end

-- Where the turtle is in nav's coordinates: right, up and forward of
-- the start as the turtle saw it there.
local function toWorld(rx, ry, rz)
  return nav.relative(origin, rx, (direction == "down") and -rz or rz, ry)
end

-- Tell nav where the turtle is now, and that the way excavate itself
-- would take out of the box (along the column to the first layer,
-- across it to the start column, then to the start) is clear.
local function syncNav()
  local function air(rx, ry, rz)
    local x, y, z = toWorld(rx, ry, rz)
    nav.record(x, y, z, "a")
  end
  for z = math.min(pos.z, firstLayer), math.max(pos.z, firstLayer) do air(pos.x, pos.y, z) end
  for x = math.min(pos.x, 0), math.max(pos.x, 0) do air(x, pos.y, firstLayer) end
  for y = math.min(pos.y, 0), math.max(pos.y, 0) do air(0, y, firstLayer) end
  for z = 0, firstLayer do air(0, 0, z) end
  local x, y, z = toWorld(pos.x, pos.y, pos.z)
  nav.setPosition(x, y, z, (origin.h + heading) % 4)
end

-- Empty the inventory into the chest beside the start, or at the
-- depot from wherever the turtle is. Items are kept when there is
-- nothing there to drop them into.
local function dump()
  local ok, reason
  if chest == "depot" then
    syncNav()
    ok, reason = depot.unload()
    if not ok then reason = "depot: " .. tostring(reason) end
  else
    face(0)
    ok, reason = inventory.dumpTo(chest)
  end
  if ok then
    dumps = dumps + 1
    alert.clear("chest")
  else
    alert.raise("chest", reason .. ", keeping the items")
  end
  return ok
end

local function dumpTrip()
  if chest == "depot" then
    print("inventory full, taking it to the depot")
    dump()
    -- depot.unload comes back to the same block and heading; make sure
    local x, y, z, h = nav.position()
    local wx, wy, wz = toWorld(pos.x, pos.y, pos.z)
    if x ~= wx or y ~= wy or z ~= wz or h ~= (origin.h + heading) % 4 then
      stranded = true
      return false, "did not get back from the depot (nav says " .. x .. " " .. y .. " " .. z .. ")"
    end
    return true
  end
  local target = { x = pos.x, y = pos.y, z = pos.z, h = heading }
  print("inventory full, taking it to the chest")
  if not goHome() then return false, "blocked on the way home" end
  dump()
  if not returnTo(target) then return false, "blocked on the way back" end
  return true
end

--[[
Layers
--]]

-- Snake over every cell of the current layer starting from where the
-- turtle is. That is one of the four corners, except on the first
-- layer of a middle start, where it first works its way along the near
-- edge to the closer corner.
local function clearLayer(width, length)
  -- Getting onto this layer dug a block too, so there may be no room
  -- for the first cell's.
  if not inventory.anyFreeSpace() then
    local ok, err = dumpTrip()
    if not ok then return false, err end
  end
  if pos.x ~= xMin and pos.x ~= xMax then
    local corner = (pos.x - xMin <= xMax - pos.x) and xMin or xMax
    while pos.x ~= corner do
      if not stepTo(corner, pos.y) then return false, "blocked on layer " .. pos.z end
      cellDone()
      if not inventory.anyFreeSpace() then
        local ok, err = dumpTrip()
        if not ok then return false, err end
      end
    end
  end
  local xStep = (pos.x == xMin) and 1 or -1
  local xEnd = (xStep == 1) and xMax or xMin
  local x = pos.x
  while true do
    local yEnd = (pos.y == 0) and (length - 1) or 0
    while pos.y ~= yEnd do
      if not stepTo(x, yEnd) then return false, "blocked on layer " .. pos.z end
      cellDone()
      if not inventory.anyFreeSpace() then
        local ok, err = dumpTrip()
        if not ok then return false, err end
      end
    end
    if x == xEnd then break end
    x = x + xStep
    if not stepTo(x, pos.y) then return false, "blocked on layer " .. pos.z end
    cellDone()
    if not inventory.anyFreeSpace() then
      local ok, err = dumpTrip()
      if not ok then return false, err end
    end
  end
  return true
end

-- Rough fuel needed: every cell once, plus the trips between layers
-- and home.
function estimateFuel(width, length, height)
  return width * length * height + 2 * (width + length + 2 * height)
end

-- Clear width x length x height blocks in the given direction ("down"
-- or "up"). chestSide is one of inventory.ChestSides (default left) and
-- says where the chest is relative to the start, or "depot"; start is one of Starts
-- (default left) and says where on the near edge the turtle stands.
-- Returns true, or false and a reason, after returning to the start and
-- emptying into the chest either way.
function run(width, length, height, dir, chestSide, start)
  width, length, height = tonumber(width), tonumber(length), tonumber(height)
  if not width or not length or not height or width < 1 or length < 1 or height < 1 then
    return false, "width, length and height must be at least 1"
  end
  if dir ~= "down" and dir ~= "up" then return false, "direction must be down or up" end
  chestSide = chestSide or inventory.DefaultChestSide
  if chestSide ~= "depot" and not inventory.isChestSide(chestSide) then return false, "unknown chest side " .. tostring(chestSide) end
  start = start or DefaultStart
  if not isStart(start) then return false, "unknown start position " .. tostring(start) .. " (left, middle or right)" end
  local conflict = chestConflict(width, length, height, dir, chestSide, start)
  if conflict then return false, conflict end
  if chestSide == "depot" then
    -- Find out now, before digging, that the depot can be used.
    local okPos, why = depot.ensurePosition()
    if not okPos then return false, why end
    local found, ferr = depot.find("dump")
    if not found then return false, "depot: " .. tostring(ferr) end
    local ox, oy, oz, oh = nav.position()
    origin = { x = ox, y = oy, z = oz, h = oh }
    print("emptying at the depot's " .. found.name .. " (" .. found.x .. " " .. found.y .. " " .. found.z .. ")")
  end
  direction = dir
  chest = chestSide
  xMin, xMax = columns(width, start)
  firstLayer = (dir == "down") and 1 or 0
  pos = { x = 0, y = 0, z = 0 }
  heading = 0
  dug, dumps = 0, 0
  stranded = false
  cells, cellsTotal = 0, width * length * height

  local fuel = turtle.getFuelLevel()
  local needed = estimateFuel(width, length, height)
  print(string.format("clearing %dx%dx%d %s from the %s, about %d fuel needed, have %s", width, length, height, dir, start, needed, tostring(fuel)))
  if fuel ~= "unlimited" and fuel < needed then
    print("warning: probably not enough fuel, will burn what it digs if it runs low")
  end

  local ok, err = true, nil
  for layer = firstLayer, firstLayer + height - 1 do
    if pos.z < layer and not deeper() then
      ok, err = false, "blocked going " .. dir .. " after " .. (layer - firstLayer) .. " layers"
      break
    end
    print("layer " .. (layer - firstLayer + 1) .. " of " .. height)
    layerText = "layer " .. (layer - firstLayer + 1) .. " of " .. height
    cells = (layer - firstLayer) * width * length -- the corner it starts on
    layerEnd = cells + width * length
    cellDone()
    ok, err = clearLayer(width, length)
    if not ok then break end
  end

  -- Away from where excavate thinks it is, the way home would be wrong.
  if stranded then return false, err end
  if not goHome() then
    return false, (err and (err .. ", then ") or "") .. "blocked on the way home"
  end
  dump()
  print(string.format("done: dug %d blocks, %d chest trips", dug, dumps))
  return ok, err
end
