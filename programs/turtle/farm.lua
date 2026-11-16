--[[
Farm looks after a field of farmland that a player has tilled. Put
the turtle over a corner of the field, one block above the crops,
looking along it, with a chest beside it (left, behind or above; right
only for a field one block wide). Width is to its right and length
straight ahead. It carries the seeds, carrots or potatoes to plant and
some coal.

Every pass it flies over the whole field, harvests ripe wheat, carrots,
potatoes and beetroot and replants the same crop, sows empty farmland
with `crop` (wheat by default, none to leave it), then empties the
harvest into the chest keeping a stack of each seed, sleeps `sleep`
seconds and goes again: `passes` times, or forever with 0. It raises
an alert when it runs out of seeds. The engine is apis/farm.lua.

Usage: farm [width] [length] [crop] [sleep] [passes] [chest]
--]]

local usage = "Usage: farm [width] [length] [crop] [sleep] [passes] [chest]"
local o = { width = 9, length = 9, crop = "wheat", sleep = 300, passes = 0, chest = farm.DefaultChestSide }

local args = { ... }
if #args > 6 then
  print(usage)
  return
end

local function number(i, name)
  if args[i] == nil then return o[name] end
  local n = tonumber(args[i])
  if not n then error(name .. " must be a number, not " .. args[i] .. "\n" .. usage, 0) end
  return n
end

o.width = number(1, "width")
o.length = number(2, "length")
if args[3] then o.crop = args[3] end
o.sleep = number(4, "sleep")
o.passes = number(5, "passes")
if args[6] then o.chest = args[6] end

local ok, err = farm.run(o)
if not ok then error(err, 0) end
