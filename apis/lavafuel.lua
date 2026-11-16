--[[
Lavafuel refuels a turtle from a lava lake with buckets. It is the
engine behind the lavafuel program.

The turtle starts at home, looking toward the lava, carrying empty
buckets. It searches an area `width` blocks across (centred on it, an
even width having its extra column on the right) and `range` blocks
long, straight ahead and starting with the block in front of it, at
its own level and the level below: it flies over the area in a snake,
digging through anything in the way. Before each step it looks at the
block ahead and at every block it looks at the one below, and a lava
source there (turtle.inspect gives the lava a state.level of 0; flowing
lava has a higher level and cannot be picked up) is scooped with an
empty bucket.

In "refuel" mode each lava bucket is burnt at once (1000 fuel, the
bucket comes back) until the fuel reaches targetFuel; then it flies
home. In "depot" mode it first brings its own fuel up to targetFuel
the same way, then keeps filling buckets until none are empty, flies
home, puts the lava buckets in the chest beside the start for other
turtles to refuel from, and takes back the empty buckets they left
there (from the first stacks of the chest) to use next time.

It never goes further than its fuel can bring it back, burning a lava
bucket it carries rather than stopping short. Without any buckets it
raises a "buckets" alert and waits for some.

Position is relative to the start (see the tracker api).
--]]

Modes = { "refuel", "depot" }
DefaultChestSide = "behind"
ItemBucket = "minecraft:bucket"
ItemLavaBucket = "minecraft:lava_bucket"
LavaFuel = 1000 -- fuel in one lava bucket

function isMode(m)
  for _, v in ipairs(Modes) do
    if v == m then return true end
  end
  return false
end

-- Is this inspected block a lava source a bucket can take?
function isLavaSource(data)
  return tracker.isSource(data) and string.find(data.name, "lava$") ~= nil
end

-- The leftmost and rightmost columns of the search area.
function columns(width)
  local left = math.floor((width - 1) / 2)
  return -left, width - 1 - left
end

-- Why these options cannot work, or nil. limit is the turtle's fuel
-- limit ("unlimited" when it needs none).
function validate(o, limit)
  local function whole(n) return type(n) == "number" and n == math.floor(n) end
  if limit == "unlimited" then return "this turtle needs no fuel" end
  if not whole(o.target) or o.target < 1 then return "target fuel must be a whole number of at least 1" end
  if type(limit) == "number" and o.target > limit then
    return "target fuel " .. o.target .. " is over the turtle's fuel limit of " .. limit
  end
  if not whole(o.range) or o.range < 1 then return "range must be a whole number of at least 1" end
  if not whole(o.width) or o.width < 1 then return "width must be a whole number of at least 1" end
  if not isMode(o.mode) then return "mode must be refuel or depot, not " .. tostring(o.mode) end
  if not inventory.isChestSide(o.chest) then return "unknown chest side " .. tostring(o.chest) end
  return nil
end

--[[
The running job
--]]

local t, opts, stats

local function fuel() return tracker.fuelLevel() end

-- Burn one lava bucket. Returns true when one was burnt.
local function burnOne()
  local slot = inventory.find(ItemLavaBucket)[1]
  if not slot then return false end
  local selected = turtle.getSelectedSlot()
  turtle.select(slot)
  local ok = turtle.refuel(1)
  turtle.select(selected)
  if ok then stats.burnt = stats.burnt + 1 end
  return ok
end

-- Burn lava buckets while the fuel is below the target (which
-- validate keeps within the turtle's limit).
local function burnToTarget()
  while fuel() < opts.target do
    if not burnOne() then break end
  end
end

-- Is there room for a lava bucket from the empty bucket stack?
local function roomForLava()
  if inventory.anyFreeSpace() then return true end
  for _, slot in ipairs(inventory.find(ItemBucket)) do
    if turtle.getItemCount(slot) == 1 then return true end
  end
  return false
end

-- Has the job got all it came for? In depot mode that is when no empty
-- bucket is left, or there is no room for another lava bucket.
local function finished()
  if fuel() < opts.target then return false end
  if opts.mode == "refuel" then return true end
  return inventory.count(ItemBucket) == 0 or not roomForLava()
end

-- Scoop lava in a direction ("" or "Down") if there is a source there
-- and something to do with it.
local function scoop(dir)
  if finished() then return end
  local data = t:inspect(dir)
  if not isLavaSource(data) then return end
  if inventory.count(ItemBucket) == 0 or not roomForLava() then
    -- Full of lava buckets: burning one makes room when it is wanted.
    if fuel() < opts.target then burnOne() else return end
  end
  if not inventory.select(ItemBucket) then return end
  if turtle["place" .. dir]() then
    stats.scooped = stats.scooped + 1
    if opts.mode == "refuel" or fuel() < opts.target then burnToTarget() end
    progress.report(math.min(fuel(), opts.target), opts.target, "fuel " .. fuel() .. ", scooped " .. stats.scooped)
  end
end

-- Enough fuel to take one more step and still get home? Burns a lava
-- bucket it carries when that is what it takes.
local function fuelForStep()
  if t:hasFuelFor(1) then return true end
  while burnOne() do
    if t:hasFuelFor(1) then return true end
  end
  return false
end

-- Step to a neighbouring cell, looking at what is ahead first.
local function stepTo(x, y)
  if x > t.x then t:face(1) elseif x < t.x then t:face(3)
  elseif y > t.y then t:face(0) elseif y < t.y then t:face(2)
  else return true end
  scoop("")
  if finished() then return true end
  if not fuelForStep() then return false, "fuel" end
  local ok, err = t:forward()
  if not ok then return false, err end
  scoop("Down")
  return true
end

-- Walk to a cell, row first then column, scooping on the way.
local function walkTo(x, y)
  while t.x ~= x or t.y ~= y do
    if finished() then return true end
    local nx, ny = t.x, t.y
    if t.x ~= x then nx = t.x + (x > t.x and 1 or -1) else ny = t.y + (y > t.y and 1 or -1) end
    local ok, err = stepTo(nx, ny)
    if not ok then return false, err end
  end
  return true
end

-- Search the area in a snake until finished. Returns true, or false
-- and "fuel" or what blocked it.
local function search()
  local x0, x1 = columns(opts.width)
  local ok, err = walkTo(0, 1)
  if ok then ok, err = walkTo(x0, 1) end
  if not ok then return false, err end
  for x = x0, x1 do
    if finished() then return true end
    local y = (t.y == 1) and opts.range or 1
    ok, err = walkTo(x, t.y)
    if ok then ok, err = walkTo(x, y) end
    if not ok then return false, err end
  end
  return true
end

local function goHome()
  local ok, err = t:goTo(0, t.y, 0, "x")
  if ok then ok, err = t:goTo(0, 0, 0, "y") end
  if ok then t:face(0) end
  return ok, err
end

-- Depot: lava buckets into the chest, empty buckets out of it.
local function depot()
  local detect, drop, back, suck = inventory.faceChestSide(opts.chest)
  if not detect() then
    back()
    alert.raise("chest", "no chest " .. opts.chest .. " for the lava buckets")
    return false
  end
  local selected = turtle.getSelectedSlot()
  for _, slot in ipairs(inventory.find(ItemLavaBucket)) do
    turtle.select(slot)
    if drop() then stats.deposited = stats.deposited + 1 end
  end
  -- Take out what the chest's first stacks hold, then give back all
  -- but the empty buckets.
  local before = {}
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    before[slot] = d and { name = d.name, count = d.count } or nil
  end
  for i = 1, 16 do
    if not inventory.anyFreeSpace() or not suck() then break end
  end
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d and d.name ~= ItemBucket then
      local had = (before[slot] and before[slot].name == d.name) and before[slot].count or 0
      if d.count > had then
        turtle.select(slot)
        drop(d.count - had)
      end
    end
  end
  turtle.select(selected)
  back()
  if inventory.count(ItemLavaBucket) > 0 then
    alert.raise("chest", "the chest " .. opts.chest .. " is full, keeping the lava buckets")
    return false
  end
  alert.clear("chest")
  return true
end

-- Burning a lava bucket leaves its empty bucket in that slot; put them
-- back into one stack.
function stackBuckets()
  local slots = inventory.find(ItemBucket)
  local selected = turtle.getSelectedSlot()
  for i = #slots, 2, -1 do
    turtle.select(slots[i])
    for j = 1, i - 1 do
      if turtle.getItemCount(slots[i]) == 0 then break end
      turtle.transferTo(slots[j])
    end
  end
  turtle.select(selected)
end

-- Refuel from lava. o has target (fuel to reach), range and width (the
-- search area), mode (refuel or depot) and chest (where the depot
-- chest is, one of inventory.ChestSides). Returns true, or false and
-- the reason.
function run(o)
  local reason = validate(o, turtle.getFuelLimit())
  if reason then return false, reason end
  opts = o
  stats = { scooped = 0, burnt = 0, deposited = 0 }
  t = tracker.new({ margin = 2, keep = function(d) return d.name == ItemLavaBucket end })

  print(string.format("%s from lava up to %d fuel, have %d, searching %dx%d", o.mode, o.target, fuel(), o.width, o.range))
  burnToTarget()
  if o.mode == "depot" and inventory.count(ItemBucket) == 0 then depot() end
  if inventory.count(ItemBucket) == 0 and not finished() then
    inventory.waitFor(function() return inventory.count(ItemBucket) > 0 end,
      "buckets", "no empty buckets, give the turtle some buckets")
  end
  alert.clear("buckets")

  local ok, err = true, nil
  if not finished() then ok, err = search() end
  if err == "fuel" then
    ok, err = true, nil
    print("fuel too low to search further")
  end
  local home, herr = goHome()
  if not home then
    return false, (err and (err .. ", then ") or "") .. "blocked on the way home: " .. tostring(herr)
  end
  if o.mode == "depot" then depot() end
  stackBuckets()

  local text = string.format("done: fuel %d, scooped %d, burnt %d", fuel(), stats.scooped, stats.burnt)
  if o.mode == "depot" then text = text .. ", " .. stats.deposited .. " lava buckets put in the chest" end
  print(text)
  if not ok then return false, err end
  if fuel() < o.target and stats.scooped == 0 then
    return false, "found no lava source within range"
  end
  return true
end
