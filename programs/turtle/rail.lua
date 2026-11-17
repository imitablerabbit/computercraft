--[[
Rail lays a straight, level rail line `length` blocks long. Put the
turtle on the block where the line starts, looking along it, carrying
rails, some cobblestone (or any building block) for gaps, and coal.
It flies one block above the line placing rail below itself, digging
a two high space through anything in the way and putting a block
under any gap. Every poweredGap blocks it lays a powered rail with a
redstone torch beside it, if it carries both, and every torchGap
blocks a torch beside the line; 0 turns either off. When it runs out
of rails or blocks it raises an alert and waits until more are put in.
The engine is apis/rail.lua.

Usage: rail [length] [poweredGap] [torchGap]
--]]

local usage = "Usage: rail [length] [poweredGap] [torchGap]"
local o = { length = 64, poweredGap = 0, torchGap = 0 }

local args = { ... }
if #args > 3 then
  print(usage)
  return
end

local names = { "length", "poweredGap", "torchGap" }
for i, name in ipairs(names) do
  if args[i] ~= nil then
    local n = tonumber(args[i])
    if not n then error(name .. " must be a number, not " .. args[i] .. "\n" .. usage, 0) end
    o[name] = n
  end
end

local ok, err = rail.run(o)
if not ok then error(err, 0) end
