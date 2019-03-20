--[[
Mine Line will mine a single strip mine infront of
the turtle. This command allows the turtle to place
torches down as it goes.
--]]

--[[
Variables and command line args
--]]

local mines = 5
local sep = 3
local length = 64
local placeTorches = true
local torchDistance = 10

local args = {...}
if #args > 5 then
  print("Usage: stripmine [mines] [seperator] [lineLength] [placeTorches] [torchDistance]")
  return
end

if args[1] then
  mines = tonumber(args[1])
end
if args[2] then
  sep = tonumber(args[2])
end
if args[3] then
  length = tonumber(args[3])
end
if args[4] == "true" or args[2] == 1 then
  placeTorches = true
elseif args[4] == "false" or args[2] == 0 then
  placeTorches = false
end
if args[5] then
  torchDistance = tonumber(args[3])
end

--[[
Script start
--]]

mine.stripMine(mines, sep, length, placeTorches, torchDistance)