--[[
Tree cutting script. The turtle is placed at the far left
of the farm. There should be no blocks to the left and right
or below the turtle for the whole farm as these blocks will
be dug. This script is meant to be run with lines of trees.
--]]

local w, h = 10, 6
local sleepTime = 60
local saplingName = inventory.ItemSapling

function usage()
  print("Usage: logger [width] [height] [saplingName] [sleeptime]")
end

function isSapling()
  local exists, data = turtle.inspect()
  if not exists then return false end
  if data.name == saplingName then
    return true
  else
    return false
  end
end

function plantSapling()
  if not inventory.select(saplingName) then
    return false
  end
  if not turtle.place() then
    return false
  end
  return true
end

function waitForInput()
  print("press any key to to resume...")
  os.pullEvent("key")
end

function fellTree()
  local dh = 0
  for i = 1, h do

    -- Continually try and move up
    while true do
      if mine.dig() then
        if mine.digUp() then
          if move.up() == 1 then
            break
          end
        end
      end
    end

  end

  -- Try and move down
  for i = 1, h do
    while true do
      if mine.digDown() then
        if move.down() == 1 then
          break
        end
      end
    end
  end

  return true
end

-- Leaves can grow around the turtle. We always need to
-- dig around us before we move
function moveRight()
  turtle.turnRight()
  while true do
    turtle.dig() -- Remove the leaf block
    if move.forward() == 1 then
      break
    end
  end
  turtle.turnLeft()
end

function moveLeft()
  turtle.turnLeft()
  while true do
    turtle.dig() -- Remove the leaf block
    if move.forward() == 1 then
      break
    end
  end
  turtle.turnRight()
end

local args = {...}

if #args > 4 then
  usage()
  return
end
if args[1] then
  if args[1] == "help" or args[1] == "-help" or args[1] == "--help" then
    usage()
    return
  end
  w = tonumber(args[1])
end
if args[2] then
  h = tonumber(args[2])
end
if args[3] then
  saplingName = args[3]
end
if args[4] then
  sleepTime = tonumber(args[4])
end

-- Dont use saplings as fuel
inventory.FuelBlacklist = {
  saplingName,
}

while true do
  print("Starting...")
  for x = 1, w do
    if turtle.detect() then
      if not isSapling() then
        print("Tree detected")
        if not fellTree() then
          print("Unable to fell tree")
          return
        end
      end
    else
      if not plantSapling() then
        print("Unable to plant sapling")
        return
      end
    end
    turtle.suck() -- suck up any loose saplings if possible
    moveRight()
  end
  for x = 1, w do
    turtle.suck()
    moveLeft()
  end
  print("Sleeping...")
  os.sleep(sleepTime)
end
  
  
