--[[
Lavafuel refuels the turtle from a lava lake. Put it at the edge of
the lava, looking toward it, carrying empty buckets (and a chest
beside it for depot mode). It searches `range` blocks straight ahead
and `width` blocks across (1 by default, a single line; the area is
centred on the turtle), at its own level and one below, digging
through anything in the way, and scoops every lava source it finds.

In refuel mode (the default) it burns each lava bucket at once, 1000
fuel each, until it has targetFuel, then comes home. In depot mode it
tops itself up to targetFuel, then fills every empty bucket, comes
home, puts the lava buckets into the chest for other turtles and takes
back the empty buckets they left there. It never goes further than it
can get back from, and raises an alert when it has no buckets. The
engine is apis/lavafuel.lua.

Usage: lavafuel [targetFuel] [range] [mode] [chest] [width]
--]]

local usage = "Usage: lavafuel [targetFuel] [range] [mode] [chest] [width]"
local o = { target = 5000, range = 16, mode = "refuel", chest = lavafuel.DefaultChestSide, width = 1 }

local args = { ... }
if #args > 5 then
  print(usage)
  return
end

local function number(i, name)
  if args[i] == nil then return o[name] end
  local n = tonumber(args[i])
  if not n then error(name .. " must be a number, not " .. args[i] .. "\n" .. usage, 0) end
  return n
end

o.target = number(1, "target")
o.range = number(2, "range")
if args[3] then o.mode = args[3] end
if args[4] then o.chest = args[4] end
o.width = number(5, "width")

local ok, err = lavafuel.run(o)
if not ok then error(err, 0) end
