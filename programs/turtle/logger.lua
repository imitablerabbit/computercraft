--[[
Tree cutting script.

Setup:
Clear a 2 x 10 area at ground level. Make the back of the 2 x 10 is made up of
dirt blocks. Place the turtle at the front on the left of the 2 x 10 then make
sure all of the programs and apis are loaded onto it. Place a block 8 blocks
high on the back row. These blocks will stop the trees from growing too large.
Place saplings in the back row in front of the turtle. Place fuel inside the
turtle ready for it to start logging.

Schematics Key:
B = Block
T = Turtle
. = Air
G = Grass

Top Down:   Front:      Back:       Side:
BBBBBBBBBB  BBBBBBBBBB  BBBBBBBBBB  .B
TGGGGGGGGG  ..........  ..........  ..
            ..........  ..........  ..
            ..........  ..........  ..
            ..........  ..........  ..
            ..........  ..........  ..
            ..........  ..........  ..
            TSSSSSSSSS  SSSSSSSSSS  TS
            GGGGGGGGGG  GGGGGGGGGG  GG

--]]

local w = 10
local h = 7
local sleepTime = 60
local saplingName = inventory.ItemSapling
local dumpItems = true

function usage()
  print("Usage: logger [width] [height] [saplingName] [sleeptime] [dumpItems]")
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
    turtle.suck() -- Pick up saplings
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
    turtle.suck() -- Pick up saplings
    if move.forward() == 1 then
      break
    end
  end
  turtle.turnRight()
end

local args = {...}

if #args > 5 then
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
if args[5] and args[5] == "false" then
  dumpItems = false
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
        if not plantSapling() then -- replant sapling after cutting tree
          print("Unable to plant sapling")
        end
      end
    else
      if not plantSapling() then
        print("Unable to plant sapling")
      end
    end
    turtle.suck()
    moveRight()
  end
  for x = 1, w do
    turtle.suck()
    moveLeft()
  end
  
  -- Try and dump the items in a chest
  if dumpItems then
    turtle.turnLeft()
    turtle.turnLeft()
    local saplingSlots = inventory.find(saplingName)
    inventory.empty(saplingSlots)
    turtle.turnRight()
    turtle.turnRight()
  end
    
  print("Sleeping...")
  os.sleep(sleepTime)
end
  
  
