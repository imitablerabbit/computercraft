--[[
Farm tends a rectangular field of farmland: it harvests ripe crops,
replants them, sows empty farmland and takes the produce to a chest.
It is the engine behind the farm program.

The turtle starts over a corner of the field, one block above the
crops, looking along the field: length is straight ahead and width to
the right. Each pass it flies over every block of the field in a snake
and looks down at the crop below it. A ripe crop (wheat, carrots and
potatoes at age 7, beetroot at 3) is dug and the same crop planted
again from what it carries; empty farmland is sown with the default
crop (none leaves it empty). Unripe crops and anything else are left
alone. With a hoe equipped it also tries to till dirt it finds empty,
which works in the game (the hoe tills the dirt two blocks below,
through the empty crop space) but not in the simulator.

After the pass it flies back to the corner, empties what it harvested
into the chest beside it, keeping one stack of each kind of seed (and
carrots and potatoes, which are their own seeds) and its coal, then
sleeps and starts again, for `passes` passes or forever with 0. When it
has no seeds for a crop it raises a "seeds" alert and leaves the block
empty to be sown on a later pass. A full inventory sends it to the
chest in the middle of a pass.

Position is relative to the start (see the tracker api).
--]]

-- What the turtle knows how to grow: the crop block, the item that
-- plants it, and the age at which it is ripe.
Crops = {
  ["minecraft:wheat"] = { seed = "minecraft:wheat_seeds", maxAge = 7 },
  ["minecraft:carrots"] = { seed = "minecraft:carrot", maxAge = 7 },
  ["minecraft:potatoes"] = { seed = "minecraft:potato", maxAge = 7 },
  ["minecraft:beetroots"] = { seed = "minecraft:beetroot_seeds", maxAge = 3 },
}

-- The default crop choices, as given on the command line.
CropChoices = { "wheat", "carrots", "potatoes", "beetroots", "none" }
DefaultChestSide = "behind"

-- Fuel kept rather than emptied into the chest.
local keepFuel = { ["minecraft:coal"] = true, ["minecraft:charcoal"] = true, ["minecraft:coal_block"] = true }

-- The item that plants a crop choice ("wheat" -> wheat seeds), or nil
-- for none or an unknown choice.
function seedFor(choice)
  if choice == nil or choice == "none" then return nil end
  local crop = Crops["minecraft:" .. choice]
  return crop and crop.seed or nil
end

function isCropChoice(choice)
  for _, c in ipairs(CropChoices) do
    if c == choice then return true end
  end
  return false
end

-- Is this item a seed of one of the crops?
function isSeed(name)
  for _, crop in pairs(Crops) do
    if crop.seed == name then return true end
  end
  return false
end

-- Is this inspected block a ripe crop? Returns the crop as well.
function isRipe(data)
  if type(data) ~= "table" then return false end
  local crop = Crops[data.name]
  if not crop then return false end
  local age = type(data.state) == "table" and data.state.age
  return type(age) == "number" and age >= crop.maxAge, crop
end

-- Why a chest on that side cannot be used, or nil. The turtle flies
-- over the field, so the chest cannot be below it (that is the corner
-- crop) nor on the right of a field wider than one block.
function chestConflict(width, side)
  if side == "below" then return "the chest below would be in the field" end
  if side == "right" and width > 1 then return "the chest right would be over the field" end
  return nil
end

-- The chest sides that work with a field this wide.
function chestSides(width)
  local sides = {}
  for _, side in ipairs(inventory.ChestSides) do
    if not chestConflict(width, side) then table.insert(sides, side) end
  end
  return sides
end

-- Why these options cannot work, or nil.
function validate(o)
  local function whole(n) return type(n) == "number" and n == math.floor(n) end
  if not whole(o.width) or o.width < 1 then return "width must be a whole number of at least 1" end
  if not whole(o.length) or o.length < 1 then return "length must be a whole number of at least 1" end
  if not isCropChoice(o.crop) then return "crop must be one of " .. table.concat(CropChoices, ", ") end
  if type(o.sleep) ~= "number" or o.sleep < 0 then return "sleep must be 0 or more seconds" end
  if not whole(o.passes) or o.passes < 0 then return "passes must be 0 (forever) or more" end
  if not inventory.isChestSide(o.chest) then return "unknown chest side " .. tostring(o.chest) end
  return chestConflict(o.width, o.chest)
end

-- Fuel for one pass: every block once and the way back.
function passFuel(width, length)
  return width * length + width + length
end

-- Does the turtle have a hoe equipped? Only CC: Tweaked can tell.
function hasHoe()
  for _, fnName in ipairs({ "getEquippedLeft", "getEquippedRight" }) do
    if turtle[fnName] then
      local ok, item = pcall(turtle[fnName])
      if ok and type(item) == "table" and type(item.name) == "string" and string.find(item.name, "_hoe$") then
        return true
      end
    end
  end
  return false
end

--[[
The running job
--]]

local t, opts, stats, hoe, missing

-- The slots kept when emptying: the biggest stack of each seed and of
-- coal.
function keepSlots()
  local best = {}
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d and (isSeed(d.name) or keepFuel[d.name]) then
      local key = keepFuel[d.name] and "fuel" or d.name
      if not best[key] or d.count > best[key].count then best[key] = { slot = slot, count = d.count } end
    end
  end
  local keep = {}
  for _, b in pairs(best) do table.insert(keep, b.slot) end
  table.sort(keep)
  return keep
end

-- Plant a seed in the empty space below. Returns true when planted.
local function plant(seed)
  if not inventory.select(seed) then
    missing[seed] = true
    return false
  end
  if turtle.placeDown() then
    stats.planted = stats.planted + 1
    return true
  end
  -- Not farmland under the space: till it with a hoe and try again.
  if hoe and turtle.digDown() and inventory.select(seed) and turtle.placeDown() then
    stats.tilled = stats.tilled + 1
    stats.planted = stats.planted + 1
    return true
  end
  stats.bare = stats.bare + 1
  return false
end

-- Look after the block below the turtle.
local function tend()
  local data = t:inspect("Down")
  if data then
    local ripe, crop = isRipe(data)
    if ripe then
      if turtle.digDown() then
        stats.harvested = stats.harvested + 1
        plant(crop.seed)
      end
    end
    return
  end
  local seed = seedFor(opts.crop)
  if seed then plant(seed) end
end

-- Empty into the chest at the start. Returns false when it could not.
local function dump()
  t:face(0)
  local ok, reason = inventory.dumpTo(opts.chest, keepSlots())
  if ok then
    alert.clear("chest")
  else
    alert.raise("chest", reason .. ", keeping the produce")
  end
  return ok
end

local function goHome()
  local ok, err = t:goTo(0, t.y, 0, "x")
  if ok then ok, err = t:goTo(0, 0, 0, "y") end
  if ok then t:face(0) end
  return ok, err
end

-- Room for a harvest, or a trip to the chest to make some.
local function ensureRoom()
  if inventory.anyFreeSpace() then return true end
  local target = { x = t.x, y = t.y, h = t.heading }
  print("inventory full, taking it to the chest")
  local ok, err = goHome()
  if not ok then return false, err end
  if not dump() and not inventory.anyFreeSpace() then
    inventory.waitFor(function() return (inventory.dumpTo(opts.chest, keepSlots())) end,
      "chest", "no room in the chest " .. opts.chest .. " for the produce")
  end
  ok, err = t:goTo(0, target.y, 0, "y")
  if ok then ok, err = t:goTo(target.x, target.y, 0, "x") end
  if ok then t:face(target.h) end
  return ok, err
end

-- One pass over the field. Returns true, or false and a reason.
local function pass(n)
  local total = opts.width * opts.length
  local done = 0
  local passText = (opts.passes > 0) and ("pass " .. n .. " of " .. opts.passes) or ("pass " .. n)
  for x = 0, opts.width - 1 do
    local y0, y1, dy = 0, opts.length - 1, 1
    if x % 2 == 1 then y0, y1, dy = opts.length - 1, 0, -1 end
    for y = y0, y1, dy do
      local ok, err = t:goTo(x, y, 0, "xy")
      if not ok then return false, "blocked over the field: " .. tostring(err) end
      ok, err = ensureRoom()
      if not ok then return false, "blocked going to the chest: " .. tostring(err) end
      tend()
      done = done + 1
      progress.report(done, total, passText)
    end
  end
  return true
end

-- Tend the field. o has width, length, crop (one of CropChoices), sleep
-- (seconds between passes), passes (0 for forever) and chest (a side
-- from inventory.ChestSides). Returns true, or false and the reason.
function run(o)
  local reason = validate(o)
  if reason then return false, reason end
  opts = o
  t = tracker.new({ margin = 5, keep = function(d) return isSeed(d.name) end })
  hoe = hasHoe()
  print(string.format("farming %dx%d, sowing %s%s", o.width, o.length, o.crop, hoe and ", tilling with the hoe" or ""))

  local n = 0
  while o.passes == 0 or n < o.passes do
    n = n + 1
    stats = { harvested = 0, planted = 0, tilled = 0, bare = 0 }
    missing = {}
    local need = passFuel(o.width, o.length) + 5
    if not t:hasFuelFor(need) then
      t:waitForFuel(need, "needs " .. need .. " fuel for a pass over the field")
    end
    local ok, err = pass(n)
    local home, herr = goHome()
    if not home then return false, (err and (err .. ", then ") or "") .. "blocked on the way back: " .. tostring(herr) end
    dump()
    if not ok then return false, err end

    local text = string.format("pass %d: harvested %d, planted %d", n, stats.harvested, stats.planted)
    if stats.tilled > 0 then text = text .. ", tilled " .. stats.tilled end
    if stats.bare > 0 then text = text .. ", " .. stats.bare .. " not farmland" end
    print(text)
    local names = {}
    for seed in pairs(missing) do table.insert(names, (seed:gsub("^[^:]+:", ""))) end
    if #names > 0 then
      table.sort(names)
      alert.raise("seeds", "out of " .. table.concat(names, ", ") .. " to plant")
    else
      alert.clear("seeds")
    end

    if o.passes == 0 or n < o.passes then
      progress.report(nil, nil, "sleeping " .. o.sleep .. "s after pass " .. n)
      sleep(o.sleep)
    end
  end
  print("done: " .. n .. " passes")
  return true
end
