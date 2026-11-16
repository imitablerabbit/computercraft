--[[
Tunnel bores a width x height tunnel `length` blocks straight ahead,
the turtle working along the middle column. Put the turtle on the
tunnel's floor level just in front of where it starts, looking along
it, with a chest beside it (left, right, behind, below or above).
Width is 1 to 5 (centred on the turtle, an even width having its
extra column on the right), height 2 to 5 upwards from the turtle.

On the way it fills holes in the floor with blocks it dug, digs out
sand and gravel over the ceiling, places a torch every torchGap slices
(0 for none) where it will not get in the way, and with plug on (the
default) blocks off lava and water it uncovers. When the inventory is
full or fuel runs short it walks back to the chest, empties itself
(keeping torches, a stack of cobblestone and its coal) and carries on.
With return set it comes back to the chest at the end. The engine is
apis/tunnel.lua.

Usage: tunnel [length] [width] [height] [torchGap] [chest] [return] [plug]
--]]

local usage = "Usage: tunnel [length] [width] [height] [torchGap] [chest] [return] [plug]"
local o = {
  length = 32, width = 3, height = 3, torchGap = 8,
  chest = tunnel.DefaultChestSide, returnHome = true, plug = true,
}

local args = { ... }
if #args > 7 then
  print(usage)
  return
end

local function number(i, name)
  if args[i] == nil then return o[name] end
  local n = tonumber(args[i])
  if not n then error(name .. " must be a number, not " .. args[i] .. "\n" .. usage, 0) end
  return n
end

local function bool(i, name)
  if args[i] == nil then return o[name] end
  if args[i] == "true" then return true end
  if args[i] == "false" then return false end
  error(name .. " must be true or false, not " .. args[i] .. "\n" .. usage, 0)
end

o.length = number(1, "length")
o.width = number(2, "width")
o.height = number(3, "height")
o.torchGap = number(4, "torchGap")
if args[5] then o.chest = args[5] end
o.returnHome = bool(6, "returnHome")
o.plug = bool(7, "plug")

local ok, err = tunnel.run(o)
if not ok then error(err, 0) end
