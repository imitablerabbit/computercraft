--[[
Bridge walks straight ahead putting a floor block under itself across
a gap: air, water or lava. It is the engine behind the bridge program.

The turtle starts on the near edge looking across. For each of up to
`length` blocks it steps forward (digging through anything in the
way) and, when there is nothing solid under it, places a block below.
Walls adds a parapet one block high on both sides of the walkway
where it crosses the gap (not over ground it walks on):
"rails" uses fences or walls (any *_fence or *_wall item), "walls"
uses the same building blocks as the floor, "none" leaves it open.
Sides that are already filled are left as they are.

The floor is any building block it carries (see
inventory.isBuildingBlock: no sand or gravel, which would fall, nor
torches, chests and the like), or only the named item. With
untilGround set it stops once it has crossed a gap and then found
solid ground under it for that many blocks in a row, so it can be sent
across a gap of unknown width; length is then the most it will go.
When it runs out of blocks or fences it raises an alert and waits for
more to be put in.
--]]

Walls = { "none", "rails", "walls" }

function isWalls(w)
  for _, v in ipairs(Walls) do
    if v == w then return true end
  end
  return false
end

-- Is this item a fence or wall, for railings?
function isRailing(name)
  return type(name) == "string" and (string.find(name, "_fence$") ~= nil or string.find(name, "_wall$") ~= nil)
end

-- Can this item be the floor (and "walls" sides)?
function isFloor(name, block)
  if block == nil or block == "any" then return inventory.isBuildingBlock(name) end
  return name == block
end

-- Why these options cannot work, or nil.
function validate(o)
  if not o.length or o.length < 1 or o.length ~= math.floor(o.length) then return "length must be a whole number of at least 1" end
  if not isWalls(o.walls) then return "walls must be none, rails or walls, not " .. tostring(o.walls) end
  if not o.untilGround or o.untilGround < 0 then return "untilGround must be 0 (off) or more" end
  if type(o.block) ~= "string" or o.block == "" then return "block must be an item name or any" end
  return nil
end

local t, opts, stats

-- Select a floor block, waiting with an alert while there are none.
local function selectFloor()
  local function pick()
    return inventory.selectWhere(function(d) return isFloor(d.name, opts.block) end) ~= nil
  end
  if pick() then return end
  local what = (opts.block == "any") and "building blocks" or opts.block
  inventory.waitFor(pick, "blocks", "out of " .. what .. " after " .. stats.length .. " blocks, add more")
end

local function selectRailing()
  local function pick()
    return inventory.selectWhere(function(d) return isRailing(d.name) end) ~= nil
  end
  if pick() then return end
  inventory.waitFor(pick, "rails", "out of fences or walls for the railings, add more")
end

-- Put a railing or wall on both sides of the turtle, where empty.
local function sides()
  if opts.walls == "none" then return end
  for _, h in ipairs({ 3, 1 }) do
    t:face(h)
    if not turtle.detect() then
      if opts.walls == "rails" then selectRailing() else selectFloor() end
      if turtle.place() then stats.walls = stats.walls + 1 end
    end
  end
  t:face(0)
end

-- Build the bridge. o has length, walls (one of Walls), untilGround (0
-- for off) and block ("any" or an item name). Returns true, or false
-- and the reason it stopped.
function run(o)
  local reason = validate(o)
  if reason then return false, reason end
  opts = o
  stats = { length = 0, floor = 0, walls = 0 }
  t = tracker.new({ margin = 0, keep = function(d) return isFloor(d.name, o.block) or isRailing(d.name) end })

  local fuel = turtle.getFuelLevel()
  print(string.format("bridge up to %d long, walls %s, have %s fuel", o.length, o.walls, tostring(fuel)))
  if fuel ~= "unlimited" and fuel < o.length then
    print("warning: probably not enough fuel, will wait for more when it runs out")
  end

  local crossed = false -- has it put down any floor yet?
  local ground = 0      -- solid blocks in a row since
  local ok, err = true, nil
  for i = 1, o.length do
    ok, err = t:forward()
    if not ok then err = "blocked after " .. stats.length .. " blocks: " .. tostring(err) break end
    stats.length = i
    if turtle.detectDown() then
      ground = ground + 1
    else
      selectFloor()
      if turtle.placeDown() then
        stats.floor = stats.floor + 1
      else
        print("warn: could not place the floor at block " .. i)
      end
      crossed = true
      ground = 0
      sides()
    end
    progress.report(i, o.length, "block " .. i .. " of " .. o.length)
    if o.untilGround > 0 and crossed and ground >= o.untilGround then
      print("reached solid ground")
      break
    end
  end
  print(string.format("done: %d long, %d floor blocks, %d side blocks", stats.length, stats.floor, stats.walls))
  return ok, err
end
