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
local chest = inventory.DefaultChestSide

local args = {...}
if #args > 6 then
  print("Usage: stripmine [mines] [seperator] [lineLength] [placeTorches] [torchDistance] [chest]")
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
if args[4] == "true" then
  placeTorches = true
elseif args[4] == "false" then
  placeTorches = false
end
if args[5] then
  torchDistance = tonumber(args[5])
end
if args[6] then
  chest = args[6]
end
if chest == "depot" then
  -- Check the depot can be used before digging (see apis/depot.lua).
  local ok, err = depot.ensurePosition()
  if ok then ok, err = depot.find("dump") end
  if not ok then error("depot: " .. tostring(err), 0) end
elseif not inventory.isChestSide(chest) then
  print("chest must be one of " .. table.concat(inventory.ChestSides, ", ") .. " or depot")
  return
end

--[[
Script start
--]]

mine.stripMine(mines, sep, length, placeTorches, torchDistance, chest)