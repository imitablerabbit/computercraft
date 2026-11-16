--[[
Tracker moves a turtle while keeping count of where it is relative to
where it started, for jobs that go out, work and come back: tunnel,
rail, bridge, farm and lavafuel. A move digs through whatever is in
the way, waits out falling sand and gravel (digging again until the
space stays clear), and attacks a mob standing in the way, giving up
only on bedrock or after MaxAttempts tries. Before moving it burns fuel
from the inventory when the tank is empty, and waits for fuel (raising
the fuel alert) when there is none at all.

  local t = tracker.new({ margin = 10, keep = isBuildingBlock })
  t:forward()  t:up()  t:down()  t:turnLeft()  t:turnRight()  t:face(h)
  t:goTo(x, y, z, "zxy")       move along each axis in that order
  t:dig("Up")  t:digFalling("Up")  t:inspect("Down")
  t:distanceHome()  t:hasFuelFor(extra)  t:waitForFuel(need)

Position: x to the right of the start, y forward, z up. Heading 0 is
the start's forward, 1 right, 2 back, 3 left. Every move returns true,
or false and a reason.

Options for new: margin is the fuel kept spare above the way home
(default FuelMargin), dig = false stops it digging (blocked moves then
only attack and wait), and keep(detail) returns true for items that
must never be burnt for fuel (a bridge's planks, say), on top of
inventory.FuelBlacklist.
--]]

MaxAttempts = 30   -- tries to clear one blocked move
FuelMargin = 10    -- fuel kept spare above the distance home
SettleTime = 0.5   -- seconds for falling sand or gravel to land

-- Blocks that fall into a space dug under them.
local fallingNames = { ":gravel$", ":sand$", ":red_sand$", "concrete_powder$", "anvil$", "suspicious_sand$", "suspicious_gravel$" }

-- Does a block of this name fall when the block under it goes?
function isFalling(name)
  if type(name) ~= "string" then return false end
  for _, p in ipairs(fallingNames) do
    if string.find(name, p) then return true end
  end
  return false
end

-- Is this block a liquid (water, lava, or a modded fluid named so)?
-- inspect reports them; detect does not, as they do not stop a move.
function isLiquid(name)
  if type(name) ~= "string" then return false end
  return string.find(name, "water$") ~= nil or string.find(name, "lava$") ~= nil
end

-- A liquid that a bucket can pick up: its source block, level 0.
function isSource(data)
  return type(data) == "table" and isLiquid(data.name)
    and type(data.state) == "table" and (data.state.level == nil or data.state.level == 0)
end

-- One step along each heading, as x and y offsets.
local steps = { [0] = { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }

local Tracker = {}
Tracker.__index = Tracker

function new(opts)
  opts = opts or {}
  local t = setmetatable({}, Tracker)
  t.x, t.y, t.z, t.heading = 0, 0, 0, 0
  t.dug = 0
  t.margin = opts.margin or FuelMargin
  t.digging = opts.dig ~= false
  t.keep = opts.keep
  return t
end

-- The turtle function for a direction: "" (forward), "Up" or "Down".
local function fn(name, dir)
  return turtle[name .. (dir or "")]
end

function Tracker:turnLeft()
  turtle.turnLeft()
  self.heading = (self.heading + 3) % 4
end

function Tracker:turnRight()
  turtle.turnRight()
  self.heading = (self.heading + 1) % 4
end

-- Turn the shortest way to a heading.
function Tracker:face(h)
  local diff = (h - self.heading) % 4
  if diff == 1 then self:turnRight()
  elseif diff == 2 then self:turnRight(); self:turnRight()
  elseif diff == 3 then self:turnLeft() end
end

-- What is in a direction, as turtle.inspect gives it, or nil.
function Tracker:inspect(dir)
  local ok, data = fn("inspect", dir)()
  if ok and type(data) == "table" then return data end
  return nil
end

-- Dig a direction until it is clear. Sand and gravel that fall into
-- the space are dug too, after giving them time to land. Liquids and
-- air count as clear. Returns false and the reason when the block
-- will not break (bedrock) or keeps coming back.
function Tracker:dig(dir)
  for attempt = 1, MaxAttempts do
    local data = self:inspect(dir)
    if not data or isLiquid(data.name) then
      if not fn("detect", dir)() then return true end
    end
    local ok, reason = fn("dig", dir)()
    if not ok then return false, reason or "cannot dig" end
    self.dug = self.dug + 1
    if data and isFalling(data.name) then sleep(SettleTime) end
  end
  return false, "it keeps filling in"
end

-- Dig a direction while it holds sand or gravel (something that
-- falls), waiting for each to land, and stop at anything else, which
-- is left alone. Used on a ceiling so it does not cave in later.
function Tracker:digFalling(dir)
  for attempt = 1, MaxAttempts do
    local data = self:inspect(dir)
    if not data or not isFalling(data.name) then return true end
    local ok, reason = fn("dig", dir)()
    if not ok then return false, reason or "cannot dig" end
    self.dug = self.dug + 1
    sleep(SettleTime)
  end
  return false, "it keeps falling"
end

-- The items never to burn: the fuel blacklist plus, as slot numbers,
-- every slot the keep option says to keep.
function Tracker:fuelBlacklist()
  local list = {}
  for _, b in ipairs(inventory.FuelBlacklist) do table.insert(list, b) end
  if self.keep then
    for slot = 1, 16 do
      local d = turtle.getItemDetail(slot)
      if d and self.keep(d) then table.insert(list, slot) end
    end
  end
  return list
end

-- The fuel level as a number (huge when unlimited).
function fuelLevel()
  local f = turtle.getFuelLevel()
  if f == "unlimited" then return math.huge end
  return f
end

function Tracker:distanceHome()
  return math.abs(self.x) + math.abs(self.y) + math.abs(self.z)
end

-- Burn whatever fuel the inventory has (but not what is kept).
function Tracker:refuel()
  inventory.refuelAll(self:fuelBlacklist())
end

-- Is there fuel for `extra` more moves and still the way home plus
-- the margin? Burns fuel from the inventory first when there is not.
function Tracker:hasFuelFor(extra)
  local need = self:distanceHome() + (extra or 0) + self.margin
  if fuelLevel() >= need then return true end
  self:refuel()
  return fuelLevel() >= need
end

-- Wait until the turtle has at least `need` fuel, burning what is put
-- into it, with the fuel alert raised so turtle control shows it.
function Tracker:waitForFuel(need, why)
  local t = self
  inventory.waitFor(function()
    t:refuel()
    return fuelLevel() >= need
  end, "fuel", why or ("needs " .. need .. " fuel, add fuel to the turtle"))
end

-- Make sure one move is possible: burn fuel if the tank is empty, and
-- wait for some when there is nothing to burn.
function Tracker:ensureMoveFuel()
  if fuelLevel() >= 1 then return end
  self:refuel()
  if fuelLevel() < 1 then self:waitForFuel(1, "out of fuel, add fuel to the turtle") end
end

-- Move one block ("forward", "up" or "down"), clearing the way.
local detectFor = { forward = "", up = "Up", down = "Down" }

function Tracker:move(which)
  local dir = detectFor[which]
  local lastReason = "blocked"
  for attempt = 1, MaxAttempts do
    self:ensureMoveFuel()
    local ok, reason = turtle[which]()
    if ok then
      if which == "up" then self.z = self.z + 1
      elseif which == "down" then self.z = self.z - 1
      else
        local s = steps[self.heading]
        self.x, self.y = self.x + s[1], self.y + s[2]
      end
      return true
    end
    lastReason = reason or lastReason
    if fn("detect", dir)() then
      if not self.digging then
        sleep(0.5)
      else
        local dug, why = self:dig(dir)
        if not dug then return false, why end
      end
    elseif not fn("attack", dir)() then
      -- Nothing to dig or hit: another turtle or a mob out of reach.
      sleep(0.5)
    end
  end
  return false, lastReason
end

function Tracker:forward() return self:move("forward") end
function Tracker:up() return self:move("up") end
function Tracker:down() return self:move("down") end

-- Step to a neighbouring cell on the same level.
function Tracker:stepTo(x, y)
  if x > self.x then self:face(1) elseif x < self.x then self:face(3)
  elseif y > self.y then self:face(0) elseif y < self.y then self:face(2)
  else return true end
  return self:forward()
end

-- Go to a cell along one axis at a time, in the order given by a
-- string of the letters x, y and z (default "zxy").
function Tracker:goTo(x, y, z, order)
  for axis in string.gmatch(order or "zxy", ".") do
    if axis == "z" then
      while self.z < z do local ok, err = self:up() if not ok then return false, err end end
      while self.z > z do local ok, err = self:down() if not ok then return false, err end end
    elseif axis == "x" then
      while self.x ~= x do local ok, err = self:stepTo(x, self.y) if not ok then return false, err end end
    elseif axis == "y" then
      while self.y ~= y do local ok, err = self:stepTo(self.x, y) if not ok then return false, err end end
    end
  end
  return true
end
