--[[
Bridge builds a one block wide walkway straight across a gap (air,
water or lava). Put the turtle on the near edge looking across,
carrying building blocks (cobblestone, planks, stone ...) and some
fuel. It walks forward placing a block under itself wherever there is
nothing solid, for `length` blocks. walls adds a side one block high
on both sides: none (the default), rails (fences or walls, any kind)
or walls (the floor's blocks). With untilGround above 0 it stops once
it has crossed the gap and had solid ground under it for that many
blocks in a row. block picks the floor item, or any building block
(the default). Out of blocks it raises an alert and waits for more.
The engine is apis/bridge.lua.

Usage: bridge [length] [walls] [untilGround] [block]
--]]

local usage = "Usage: bridge [length] [walls] [untilGround] [block]"
local o = { length = 32, walls = "none", untilGround = 0, block = "any" }

local args = { ... }
if #args > 4 then
  print(usage)
  return
end

local function number(i, name)
  if args[i] == nil then return o[name] end
  local n = tonumber(args[i])
  if not n then error(name .. " must be a number, not " .. args[i] .. "\n" .. usage, 0) end
  return n
end

o.length = number(1, "length")
if args[2] then o.walls = args[2] end
o.untilGround = number(3, "untilGround")
if args[4] then o.block = args[4] end

local ok, err = bridge.run(o)
if not ok then error(err, 0) end
