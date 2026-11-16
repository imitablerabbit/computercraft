--[[
Mine Line will mine a single strip mine infront of
the turtle. This command allows the turtle to place
torches down as it goes. With returnHome set to true
the turtle walks back to where it started once the
line is finished.
--]]

--[[
Variables and command line args
--]]

local length = 64
local placeTorches = true
local torchDistance = 10
local returnHome = false

local args = {...}
if #args > 4 then
  print("Usage: mineline [length] [placeTorches] [torchDistance] [return]")
  return
end

if args[1] then
  length = tonumber(args[1])
end
if args[2] == "true" then
  placeTorches = true
elseif args[2] == "false" then
  placeTorches = false
end
if args[3] then
  torchDistance = tonumber(args[3])
end
if args[4] == "true" then
  returnHome = true
elseif args[4] == "false" then
  returnHome = false
end

--[[
Script start
--]]

local distance = mine.mineLine(length, placeTorches, torchDistance)
print("mined "..distance.." blocks")
if returnHome and distance > 0 then
  print("returning to start")
  local moved = move.back(distance)
  if moved < distance then
    print("warn: blocked after "..moved.." of "..distance.." blocks back")
  end
end
