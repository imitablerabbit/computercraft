--[[
Tunnel bores a width x height tunnel straight ahead and brings what it
digs back to a chest at the start. It is the engine behind the tunnel
program.

The turtle starts on the tunnel's floor level in front of where the
tunnel begins, in its middle column, looking along it. The tunnel is
the `length` slices ahead of it; each slice is `width` blocks across
(centred on the turtle, an even width putting the extra column on the
right) and `height` blocks up from the turtle's level. The start block
itself is not dug, so a chest can stand on any side of it.

Each slice is cleared column by column, visiting every block of it.
On the way the turtle fills holes in the floor with blocks it has dug
(cobblestone, dirt, ...) so the tunnel can be walked, digs out sand and
gravel that hangs over the ceiling until the ceiling stays put, and
with plug on puts a block over any lava or water showing in the walls,
floor, ceiling or end, and in the tunnel itself. Torches go every
torchGap slices: standing on the floor of an outer column for tunnels
two or more wide, or at the top of the column for one wide tunnels,
where they hang on the wall; the turtle never has to pass a torch.

Whenever the inventory gets full, and when fuel runs short of the way
home, the turtle walks back along the middle of the tunnel, empties
itself into the chest (keeping its torches and a stack of filler) and
goes back to where it left off. With returnHome it comes back at the
end too; otherwise it stops at the far end.

Position is relative to the start (see the tracker api): x to the
right, y forward, z up.
--]]

MinWidth, MaxWidth = 1, 5
MinHeight, MaxHeight = 2, 5
DefaultChestSide = "behind"
MinFreeSlots = 4 -- free slots wanted before starting a slice

-- Blocks used to fill holes and plug liquids, best first.
Fillers = {
  "minecraft:cobblestone", "minecraft:cobbled_deepslate", "minecraft:dirt",
  "minecraft:stone", "minecraft:netherrack", "minecraft:andesite", "minecraft:diorite",
  "minecraft:granite", "minecraft:tuff", "minecraft:deepslate", "minecraft:blackstone",
  "minecraft:basalt", "minecraft:end_stone", "minecraft:sandstone", "minecraft:calcite",
}

ItemTorch = "minecraft:torch"

function isFiller(name)
  for _, f in ipairs(Fillers) do
    if f == name then return true end
  end
  return false
end

-- The leftmost and rightmost columns, relative to the middle.
function columns(width)
  local left = math.floor((width - 1) / 2)
  return -left, width - 1 - left
end

-- The column whose floor takes the torches, or nil for a one wide
-- tunnel, where they go at the top of the only column instead. It is
-- never the middle column, which the turtle walks along.
function torchColumn(width)
  if width < 2 then return nil end
  local x0, x1 = columns(width)
  if x0 ~= 0 then return x0 end
  return x1
end

-- Does slice y (1 is the first) get a torch?
function isTorchSlice(y, gap)
  return gap ~= nil and gap > 0 and y % gap == 0
end

-- Rough fuel for one slice: every block once, getting to the corner
-- and back to the middle, and a torch detour.
function sliceFuel(width, height)
  return width * height + width + height + 4
end

-- Rough fuel for the whole tunnel and the walk back.
function estimateFuel(length, width, height)
  return length * sliceFuel(width, height) + length
end

-- Why these options cannot work, or nil.
function validate(o)
  if not o.length or o.length < 1 or o.length ~= math.floor(o.length) then return "length must be a whole number of at least 1" end
  if not o.width or o.width < MinWidth or o.width > MaxWidth or o.width ~= math.floor(o.width) then
    return "width must be " .. MinWidth .. " to " .. MaxWidth
  end
  if not o.height or o.height < MinHeight or o.height > MaxHeight or o.height ~= math.floor(o.height) then
    return "height must be " .. MinHeight .. " to " .. MaxHeight
  end
  if not o.torchGap or o.torchGap < 0 then return "torch gap must be 0 (no torches) or more" end
  if not inventory.isChestSide(o.chest) then return "unknown chest side " .. tostring(o.chest) end
  return nil
end

--[[
State of the running job
--]]

local t, opts, x0, x1
local alerted = {} -- alerts raised, so they are cleared when things improve

local function raiseOnce(kind, message)
  if not alerted[kind] then
    alert.raise(kind, message)
    alerted[kind] = true
  end
end

local function clearAlert(kind)
  if alerted[kind] then
    alert.clear(kind)
    alerted[kind] = nil
  end
end

-- Select a filler block. Returns false (and raises an alert once) when
-- the turtle has none.
local function selectFiller()
  for _, name in ipairs(Fillers) do
    if inventory.select(name) then
      clearAlert("blocks")
      return true
    end
  end
  raiseOnce("blocks", "no cobblestone or dirt left to fill holes")
  return false
end

-- Put a filler block in a direction ("", "Up" or "Down").
local function placeFiller(dir)
  if not selectFiller() then return false end
  return turtle["place" .. dir]()
end

-- Plug a liquid showing in a direction with a block.
local function plug(dir)
  local data = t:inspect(dir)
  if data and tracker.isLiquid(data.name) then
    if placeFiller(dir) then print("plugged " .. data.name .. " at slice " .. t.y) end
  end
end

-- Move into the next block ("forward", "up", "down"). With plug on, a
-- liquid there is turned into a block first so digging removes it.
local dirOf = { forward = "", up = "Up", down = "Down" }

local function enter(which)
  if opts.plug then
    local data = t:inspect(dirOf[which])
    if data and tracker.isLiquid(data.name) then placeFiller(dirOf[which]) end
  end
  return t:move(which)
end

local function stepTo(x)
  if x > t.x then t:face(1) elseif x < t.x then t:face(3) else return true end
  return enter("forward")
end

local function moveZ(z)
  while t.z < z do local ok, err = enter("up") if not ok then return false, err end end
  while t.z > z do local ok, err = enter("down") if not ok then return false, err end end
  return true
end

-- Work on the block the turtle is in: floor, ceiling and walls.
local function visit()
  local y = t.y
  if t.z == 0 and not turtle.detectDown() then
    placeFiller("Down")
  end
  if t.z == opts.height - 1 then
    local data = t:inspect("Up")
    if data and tracker.isFalling(data.name) then
      local ok = t:digFalling("Up")
      if not ok then print("warn: the ceiling at " .. t.x .. "," .. y .. " keeps falling") end
    elseif opts.plug then
      plug("Up")
    end
  end
  if opts.plug then
    -- The faces that look out of the tunnel, the current one first so
    -- climbing a column needs no turning.
    local faces = {}
    if t.x == x0 then table.insert(faces, 3) end
    if t.x == x1 then table.insert(faces, 1) end
    if y == opts.length then table.insert(faces, 0) end
    table.sort(faces, function(a, b) return a == t.heading and b ~= t.heading end)
    for _, h in ipairs(faces) do
      t:face(h)
      plug("")
    end
  end
end

--[[
Going home and emptying
--]]

-- Fuel worth keeping rather than emptying into the chest.
KeepFuel = { ["minecraft:coal"] = true, ["minecraft:charcoal"] = true, ["minecraft:coal_block"] = true }

-- The slots not emptied into the chest: torches, the biggest stack of
-- filler (for holes and plugs) and the biggest stack of coal (burnt
-- when fuel runs low).
local function keepSlots()
  local keep = inventory.find(ItemTorch)
  local filler, fillerCount, coal, coalCount = nil, 0, nil, 0
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d and isFiller(d.name) and d.count > fillerCount then filler, fillerCount = slot, d.count end
    if d and KeepFuel[d.name] and d.count > coalCount then coal, coalCount = slot, d.count end
  end
  if filler then table.insert(keep, filler) end
  if coal then table.insert(keep, coal) end
  return keep
end

-- Empty into the chest, waiting (with an alert) while there is no
-- chest or it is full, when `wait` is set.
local function dump(wait)
  t:face(0)
  local ok, reason = inventory.dumpTo(opts.chest, keepSlots())
  if ok then
    clearAlert("chest")
    return true
  end
  if not wait then
    alert.raise("chest", reason .. ", keeping the items")
    return false
  end
  inventory.waitFor(function()
    t:face(0)
    return (inventory.dumpTo(opts.chest, keepSlots()))
  end, "chest", reason .. ", empty it or put one there")
  return true
end

-- Home from anywhere in the tunnel: down to the floor, across to the
-- middle, back along it.
local function goHome()
  local ok, err = t:goTo(0, t.y, 0, "zx")
  if ok then ok, err = t:goTo(0, 0, 0, "y") end
  if ok then t:face(0) end
  return ok, err
end

-- Back out to a block, the same way in reverse.
local function returnTo(target)
  local ok, err = t:goTo(0, target.y, 0, "y")
  if ok then ok, err = t:goTo(target.x, target.y, target.z, "xz") end
  if ok then t:face(target.h) end
  return ok, err
end

-- Go home, empty, wait for fuel when `fuelNeed` is given, come back.
local function trip(why, fuelNeed)
  local target = { x = t.x, y = t.y, z = t.z, h = t.heading }
  print(why)
  local ok, err = goHome()
  if not ok then return false, "blocked on the way home: " .. tostring(err) end
  dump(true)
  if fuelNeed then t:waitForFuel(fuelNeed, "needs " .. fuelNeed .. " fuel to carry on, add fuel") end
  ok, err = returnTo(target)
  if not ok then return false, "blocked on the way back: " .. tostring(err) end
  return true
end

local function freeSlots()
  local n = 0
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then n = n + 1 end
  end
  return n
end

-- Before digging into another block: room for what it gives.
local function ensureRoom()
  if inventory.anyFreeSpace() then return true end
  return trip("inventory full, taking it to the chest")
end

--[[
Slices
--]]

local function placeTorch(dir)
  if not inventory.select(ItemTorch) then
    raiseOnce("torches", "no torches left")
    return false
  end
  clearAlert("torches")
  if not turtle["place" .. dir]() then
    print("warn: could not place a torch at slice " .. t.y)
    return false
  end
  return true
end

-- Clear slice y. The turtle is at (0, y, 0) and ends there.
local function clearSlice(y)
  local w = opts.width
  -- Along the floor to the left column, then up and down each column.
  while t.x > x0 do
    local ok, err = ensureRoom() if not ok then return false, err end
    visit()
    ok, err = stepTo(t.x - 1)
    if not ok then return false, err end
  end
  for x = x0, x1 do
    if t.x ~= x then
      local ok, err = ensureRoom() if not ok then return false, err end
      ok, err = stepTo(x)
      if not ok then return false, err end
    end
    local top = (t.z == 0) and (opts.height - 1) or 0
    visit()
    while t.z ~= top do
      local ok, err = ensureRoom() if not ok then return false, err end
      ok, err = moveZ(t.z + (top > t.z and 1 or -1))
      if not ok then return false, err end
      visit()
    end
  end
  -- Torches, then back to the middle of the floor.
  if isTorchSlice(y, opts.torchGap) then
    local col = torchColumn(w)
    if col then
      local ok, err = t:goTo(col, y, 1, "xz")
      if not ok then return false, err end
      placeTorch("Down")
    else
      local ok, err = moveZ(opts.height - 2)
      if not ok then return false, err end
      placeTorch("Up")
    end
  end
  local ok, err = t:goTo(0, y, 0, "xz")
  if not ok then return false, err end
  return true
end

-- Bore the tunnel. o has length, width, height, torchGap (0 for none),
-- chest (an inventory.ChestSides side), returnHome and plug. Returns
-- true, or false and the reason.
function run(o)
  local reason = validate(o)
  if reason then return false, reason end
  opts = o
  x0, x1 = columns(o.width)
  alerted = {}
  t = tracker.new({ margin = tracker.FuelMargin, keep = function(d) return d.name == ItemTorch end })

  local needed = estimateFuel(o.length, o.width, o.height)
  local fuel = turtle.getFuelLevel()
  print(string.format("tunnel %dx%d, %d long, about %d fuel needed, have %s", o.width, o.height, o.length, needed, tostring(fuel)))
  if fuel ~= "unlimited" and fuel < needed then
    print("warning: probably not enough fuel, will burn what it digs and come back for more")
  end
  if o.torchGap > 0 and inventory.count(ItemTorch) == 0 then
    print("warning: no torches, the tunnel will be dark")
  end

  local ok, err = true, nil
  local slice = sliceFuel(o.width, o.height)
  for y = 1, o.length do
    progress.report(y - 1, o.length, "slice " .. y .. " of " .. o.length)
    -- Fuel for this slice and the way back from its far side.
    if not t:hasFuelFor(slice + 1) then
      ok, err = trip("low on fuel, going home", 2 * (t:distanceHome() + 1) + slice + t.margin)
      if not ok then break end
    end
    if freeSlots() < MinFreeSlots then
      ok, err = trip("inventory nearly full, taking it to the chest")
      if not ok then break end
    end
    t:face(0)
    ok, err = enter("forward")
    if not ok then err = "blocked at slice " .. y .. ": " .. tostring(err) break end
    ok, err = clearSlice(y)
    if not ok then err = "blocked at slice " .. y .. ": " .. tostring(err) break end
  end
  if ok then progress.report(o.length, o.length, "done") end

  if o.returnHome or not ok then
    local home, herr = goHome()
    if not home then
      return false, (err and (err .. ", then ") or "") .. "blocked on the way home: " .. tostring(herr)
    end
    dump(false)
  else
    t:face(0)
  end
  print(string.format("done: %d slices, dug %d blocks", ok and o.length or math.max(0, t.y - 1), t.dug))
  return ok, err
end
