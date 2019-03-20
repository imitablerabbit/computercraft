--[[
Mine Line will mine a single strip mine infront of
the turtle. This command allows the turtle to place
torches down as it goes.
--]]

--[[
Variables and command line args
--]]

local length = 64
local placeTorches = true
local torchDistance = 10

local args = {...}
if #args > 3 then
  print("Usage: mineline [length] [placeTorches] [torchDistance]")
  return
end

if args[1] then
  length = tonumber(args[1])
end
if args[2] == "true" or args[2] == 1 then
  placeTorches = true
elseif args[2] == "false" or args[2] == 0 then
  placeTorches = false
end
if args[3] then
  torchDistance = tonumber(args[3])
end

--[[
Script start
--]]

mine.mineLine(length, placeTorches, torchDistance)