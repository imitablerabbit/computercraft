--[[
Flatten clears a width x length x height box upwards from where the
turtle is, to level the ground. The turtle starts on the near edge of
the footprint on the surface: length is straight ahead and height is
up, starting with its own layer. start says where on the edge it is:
left (the default, width is to its right), right (width is to its
left) or middle (width spread both ways). When its inventory fills up,
and when it finishes, it comes back to the start and empties itself
into a chest next to where it started: left (the default), right,
behind or below (above is inside the area); a side inside the area is
refused.

Usage: flatten [width] [length] [height] [chest] [start]
--]]

local width, length, height = 8, 8, 4
local chest = inventory.DefaultChestSide
local start = excavate.DefaultStart

local args = {...}
if #args > 5 then
  print("Usage: flatten [width] [length] [height] [chest] [start]")
  return
end
if args[1] then width = tonumber(args[1]) end
if args[2] then length = tonumber(args[2]) end
if args[3] then height = tonumber(args[3]) end
if args[4] then chest = args[4] end
if args[5] then start = args[5] end

local ok, err = excavate.run(width, length, height, "up", chest, start)
if not ok then error(err, 0) end
