--[[
Flatten clears a width x length x height box upwards from where the
turtle is, to level the ground. The turtle starts in the bottom left
corner of the footprint on the surface: width is to its right, length
is straight ahead and height is up, starting with its own layer. When
its inventory fills up, and when it finishes, it comes back to the
start and empties itself into a chest next to where it started: left
(the default), behind or below (right and above are inside the area).

Usage: flatten [width] [length] [height] [chest]
--]]

local width, length, height = 8, 8, 4
local chest = inventory.DefaultChestSide

local args = {...}
if #args > 4 then
  print("Usage: flatten [width] [length] [height] [chest]")
  return
end
if args[1] then width = tonumber(args[1]) end
if args[2] then length = tonumber(args[2]) end
if args[3] then height = tonumber(args[3]) end
if args[4] then chest = args[4] end

local ok, err = excavate.run(width, length, height, "up", chest)
if not ok then error(err, 0) end
