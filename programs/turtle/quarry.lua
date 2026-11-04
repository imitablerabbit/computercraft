--[[
Quarry digs a width x length x depth hole straight down from where
the turtle is. The turtle starts in the bottom left corner of the
footprint: width is to its right, length is straight ahead and depth
is down, starting with the block below it. When its inventory fills
up, and when it finishes, it comes back to the start and empties
itself into a chest next to where it started: left (the default),
right, behind or above (below would be dug up).

Usage: quarry [width] [length] [depth] [chest]
--]]

local width, length, depth = 8, 8, 8
local chest = inventory.DefaultChestSide

local args = {...}
if #args > 4 then
  print("Usage: quarry [width] [length] [depth] [chest]")
  return
end
if args[1] then width = tonumber(args[1]) end
if args[2] then length = tonumber(args[2]) end
if args[3] then depth = tonumber(args[3]) end
if args[4] then chest = args[4] end

local ok, err = excavate.run(width, length, depth, "down", chest)
if not ok then error(err, 0) end
