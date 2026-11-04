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
C = Chest

Top Down:   Front:      Back:       Side:
BBBBBBBBBB  BBBBBBBBBB  BBBBBBBBBB  ..B
TGGGGGGGGG  ..........  ..........  ...
C           ..........  ..........  ...
            ..........  ..........  ...
            ..........  ..........  ...
            ..........  ..........  ...
            ..........  ..........  ...
            TSSSSSSSSS  SSSSSSSSSS  CTS
            GGGGGGGGGG  GGGGGGGGGG  .GG

--]]

local w = 10
local h = 7
local sleepTime = 60
local saplingName = inventory.ItemSapling
local dumpItems = true
local chest = "behind"

function usage()
  print("Usage: logger [width] [height] [saplingName] [sleeptime] [dumpItems] [chest]")
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
    alert.raise("saplings", "no " .. saplingName .. " left to plant")
    return false
  end
  alert.clear("saplings")
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

if #args > 6 then
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
if args[6] then
  chest = args[6]
end
if not inventory.isChestSide(chest) then
  print("chest must be one of " .. table.concat(inventory.ChestSides, ", "))
  return
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
  
  -- Try and dump the items in the chest, keeping the saplings
  if dumpItems then
    local saplingSlots = inventory.find(saplingName)
    local ok, reason = inventory.dumpTo(chest, saplingSlots)
    if not ok then print(reason .. ", keeping the items") end
  end
    
  print("Sleeping...")
  os.sleep(sleepTime)
end
  
  
