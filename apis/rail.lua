--[[
Rail lays a straight, level line of rail. It is the engine behind the
rail program.

The turtle starts on the block where the line begins, looking along
it. It rises one block and from then on flies at head height over the
line: for each block it clears the rail's space below it (digging
whatever is there, unless it is already a rail) and the head height
space ahead of it, so the line ends up two blocks high, then places
the rail with placeDown. When the rail will not go down because there
is nothing under it (a gap, a ravine, water), it drops into the rail's
space, puts a building block under it and comes back up.

Every poweredGap blocks it lays a powered rail with a redstone torch
beside it at rail level (left side, else right), when it carries both;
without them it lays a plain rail there and says so once. Every
torchGap blocks a torch goes beside the rail (right side, else left)
for light. Both are 0 for none.

When the rails run out it raises a "rails" alert and waits, carrying
on as soon as rails are put into it; the same goes for building blocks
("blocks") when it needs a support. It stops after `length` blocks,
above the last rail.
--]]

ItemRail = "minecraft:rail"
ItemPowered = "minecraft:powered_rail"
ItemRedstoneTorch = "minecraft:redstone_torch"
ItemTorch = "minecraft:torch"

-- Is this block a rail of any kind already?
function isRail(name)
  return type(name) == "string" and string.find(name, "rail$") ~= nil
end

-- Does block i (1 is the first) get a powered rail or a torch?
function isGap(i, gap)
  return gap ~= nil and gap > 0 and i % gap == 0
end

-- Rough fuel: every block, rising at the start, and dropping to rail
-- level and back for each torch and powered rail.
function estimateFuel(length, poweredGap, torchGap)
  local extra = 0
  if poweredGap > 0 then extra = extra + 2 * math.floor(length / poweredGap) end
  if torchGap > 0 then extra = extra + 2 * math.floor(length / torchGap) end
  return length + 1 + extra
end

-- Why these options cannot work, or nil.
function validate(o)
  if not o.length or o.length < 1 or o.length ~= math.floor(o.length) then return "length must be a whole number of at least 1" end
  if not o.poweredGap or o.poweredGap < 0 then return "powered gap must be 0 (none) or more" end
  if not o.torchGap or o.torchGap < 0 then return "torch gap must be 0 (none) or more" end
  return nil
end

local t
local stats

-- A building block selected for a support, waiting for one if needed.
local function selectSupport()
  if inventory.selectBuildingBlock() then return end
  inventory.waitFor(function() return inventory.selectBuildingBlock() ~= nil end,
    "blocks", "no blocks left to hold up the rail, add cobblestone or similar")
  inventory.selectBuildingBlock()
end

-- In the rail's space: make sure there is something under it.
local function ensureSupport()
  if turtle.detectDown() then return true end
  selectSupport()
  if turtle.placeDown() then
    stats.supports = stats.supports + 1
    return true
  end
  return false
end

-- Place an item into the space at one side of the turtle (the rail's
-- level), trying `first` ("left" or "right") and then the other side.
-- The turtle ends facing along the line.
local function placeBeside(item, first)
  local placed = false
  local sides = first == "left" and { 3, 1 } or { 1, 3 }
  for _, h in ipairs(sides) do
    if inventory.select(item) then
      t:face(h)
      if turtle.place() then placed = true break end
    end
  end
  t:face(0)
  return placed
end

local warned = {}
local function warnOnce(key, text)
  if not warned[key] then print(text) warned[key] = true end
end

-- Lay one block of the line, the turtle above it. Returns false and
-- the reason when it cannot go on.
local function layOne(i, o)
  -- Clear the rail's space, unless a rail is already there.
  local below = t:inspect("Down")
  if below and isRail(below.name) then
    stats.existing = stats.existing + 1
    return true
  end
  if below and not tracker.isLiquid(below.name) then
    local ok, err = t:dig("Down")
    if not ok then return false, err end
  end

  local wantPowered = isGap(i, o.poweredGap)
  if wantPowered and (inventory.count(ItemPowered) == 0 or inventory.count(ItemRedstoneTorch) == 0) then
    warnOnce("powered", "no powered rails or redstone torches, laying plain rail instead")
    wantPowered = false
  end
  local wantTorch = isGap(i, o.torchGap)
  if wantTorch and inventory.count(ItemTorch) == 0 then
    warnOnce("torch", "no torches left, carrying on without")
    wantTorch = false
  end

  local item = ItemRail
  if wantPowered or wantTorch then
    -- Down into the rail's space to put things beside it.
    local ok, err = t:down()
    if not ok then return false, err end
    ensureSupport()
    if wantPowered then
      if placeBeside(ItemRedstoneTorch, "left") then
        item = ItemPowered
      else
        print("warn: no room for a redstone torch at block " .. i .. ", plain rail there")
      end
    end
    if wantTorch and placeBeside(ItemTorch, "right") then
      stats.torches = stats.torches + 1
    end
    ok, err = t:up()
    if not ok then return false, err end
  end

  if item == ItemRail and inventory.count(ItemRail) == 0 then
    inventory.waitFor(function() return inventory.count(ItemRail) > 0 end,
      "rails", "out of rails after " .. (i - 1) .. " blocks, add rails")
  end
  inventory.select(item)
  if turtle.placeDown() then
    if item == ItemPowered then stats.powered = stats.powered + 1 else stats.rails = stats.rails + 1 end
    return true
  end
  -- Nothing to stand on: drop in, put a block under, try again.
  if not turtle.detectDown() then
    local ok, err = t:down()
    if not ok then return false, err end
    ensureSupport()
    ok, err = t:up()
    if not ok then return false, err end
    inventory.select(item)
    if turtle.placeDown() then
      if item == ItemPowered then stats.powered = stats.powered + 1 else stats.rails = stats.rails + 1 end
      return true
    end
  end
  print("warn: could not place a rail at block " .. i)
  return true
end

-- Lay the line. o has length, poweredGap and torchGap (0 for none).
-- Returns true, or false and the reason it stopped.
function run(o)
  local reason = validate(o)
  if reason then return false, reason end
  stats = { rails = 0, powered = 0, torches = 0, supports = 0, existing = 0 }
  warned = {}
  t = tracker.new({ margin = 0, keep = function(d) return inventory.isBuildingBlock(d.name) end })

  local needed = estimateFuel(o.length, o.poweredGap, o.torchGap)
  local fuel = turtle.getFuelLevel()
  print(string.format("rail line of %d, about %d fuel needed, have %s, %d rails", o.length, needed, tostring(fuel), inventory.count(ItemRail)))
  if fuel ~= "unlimited" and fuel < needed then
    print("warning: probably not enough fuel, will burn coal it digs and wait for more")
  end

  local ok, err = t:up()
  if not ok then return false, "cannot rise above the start: " .. tostring(err) end
  for i = 1, o.length do
    if i > 1 then
      ok, err = t:forward()
      if not ok then err = "blocked after " .. (i - 1) .. " blocks: " .. tostring(err) break end
    end
    ok, err = layOne(i, o)
    if not ok then err = "stuck at block " .. i .. ": " .. tostring(err) break end
    progress.report(i, o.length, "block " .. i .. " of " .. o.length)
  end
  print(string.format("done: %d rails, %d powered, %d torches, %d supports, %d already there",
    stats.rails, stats.powered, stats.torches, stats.supports, stats.existing))
  return ok, err
end
