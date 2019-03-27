--[[
Tree cutting script. The turtle is placed at the far left
of the farm. There should be no blocks to the left and right
or below the turtle for the whole farm as these blocks will
be dug. This script is meant to be run with lines of trees.
--]]

local w, h = 10, 7
local sleepTime = 60
local saplingName = inventory.ItemSapling

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

-- Dont use saplings as fuel
inventory.FuelBlacklist = {
  saplingName,
}

-- Create the application object
local app = guiapplication.GUIApplication.new()
local w, h = term.getSize()

-- Create a root gui component. This is the base component used 
-- in a similar way to JFrame with no decorations.
local root = guirootcontainer.GUIRootContainer.new()

-- Title text that should be centered
local title = guitext.GUIText.new("Tree Logger")
title:setTextAlign("center")
title:setTextVerticalAlign("middle")
title:setBorder(false)
title:setPreferredBounds(2, 3, w - 2, 3)

local saplingLabel = guitext.GUIText.new("Sapling:")
saplingLabel:setTextAlign("left")
saplingLabel:setTextVerticalAlign("middle")
saplingLabel:setPreferredBounds(3, 6, 9, 3) 
saplingLabel:setBorder(false)

local saplingNameLabel = guitext.GUIText.new(saplingName)
saplingNameLabel:setTextAlign("left")
saplingNameLabel:setTextVerticalAlign("middle")
saplingNameLabel:setPreferredBounds(3 + 9 + 1, 6, (w - 2) / 2, 3)
saplingNameLabel:setBorder(false)

local fuelLabel = guitext.GUIText.new("Fuel Level:")
fuelLabel:setTextAlign("left")
fuelLabel:setTextVerticalAlign("middle")
fuelLabel:setPreferredBounds(3, 7, 9, 3) 
fuelLabel:setBorder(false)

local fuelLevelLabel = guitext.GUIText.new(turtle.getFuelLevel())
fuelLevelLabel:setTextAlign("left")
fuelLevelLabel:setTextVerticalAlign("middle")
fuelLevelLabel:setPreferredBounds(3 + 9 + 1, 6, (w - 2) / 2, 3)
fuelLevelLabel:setBorder(false)

-- Add and subtract buttons
-- TODO: These are somehow getting 2 events triggered when the button is pressed.
-- local count = 0
-- local addClick = function(e)
--     count = count + 1
--     clickCount:setText(tostring(count))
-- end
-- local subtractClick = function(e)
--     count = count - 1
--     clickCount:setText(tostring(count))
-- end
-- local bw = math.floor((w - 4) / 2)
-- local addButton = guibutton.GUIButton.new("Add Click")
-- addButton:setPreferredBounds(3, 10, bw, 7)
-- addButton:addButtonListener(addClick)

-- local subtractButton = guibutton.GUIButton.new("Subtract Click")
-- subtractButton:setPreferredBounds(w - 1 - bw, 10, bw, 7)
-- subtractButton:addButtonListener(subtractClick)

-- Add the button to the root container.
root:add(title)
root:add(saplingLabel)
root:add(saplingNameLabel)
root:add(fuelLabel)
root:add(fuelLevelLabel)
-- root:add(addButton)
-- root:add(subtractButton)
app:setRootContainer(root)
app:start()





-- while true do
--   print("Starting...")
--   for x = 1, w do
--     if turtle.detect() then
--       if not isSapling() then
--         print("Tree detected")
--         if not fellTree() then
--           print("Unable to fell tree")
--           return
--         end
--         if not plantSapling() then -- replant sapling after cutting tree
--           print("Unable to plant sapling")
--         end
--       end
--     else
--       if not plantSapling() then
--         print("Unable to plant sapling")
--       end
--     end
--     turtle.suck()
--     moveRight()
--   end
--   for x = 1, w do
--     turtle.suck()
--     moveLeft()
--   end
--   print("Sleeping...")
--   os.sleep(sleepTime)
-- end
  
  
