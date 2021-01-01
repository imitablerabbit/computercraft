local loggerWidth = "10"
local loggerHeight = "7"
local sleepTime = "60"
local saplingName = inventory.ItemSapling
local dumpItems = true

local w, h = term.getSize()
local outerPadding = 3
local innerPadding = 1
local labelX = outerPadding
local labelW = 10
local labelH = 3
local inputX = labelX + labelW + innerPadding
local inputW = w - (outerPadding * 2) - innerPadding - labelW
local inputH = 3

-- Create the application object
local app = guiapplication.GUIApplication.new()

-- Create a root gui component. This is the base component used 
-- in a similar way to JFrame with no decorations.
local root = guirootcontainer.GUIRootContainer.new()
root:setTitle("LoggerGUI")

-- Setup the logging width label and input.
local widthLabel = guitext.GUIText.new("Width:")
widthLabel:setTextAlign("left")
widthLabel:setTextVerticalAlign("middle")
widthLabel:setPreferredBounds(labelX, 3, labelW, labelH)
widthLabel:setBorder(false)
local widthInput = guiinput.GUIInput.new(loggerWidth)
widthInput:setPreferredBounds(inputX, 3, inputW, inputH) 
widthInput:setBorder(true)

-- Setup the logging height label and input.
local heightLabel = guitext.GUIText.new("Height:")
heightLabel:setTextAlign("left")
heightLabel:setTextVerticalAlign("middle")
heightLabel:setPreferredBounds(labelX, 6, labelW, labelH)
heightLabel:setBorder(false)
local heightInput = guiinput.GUIInput.new(loggerHeight)
heightInput:setPreferredBounds(inputX, 6, inputW, inputH) 
heightInput:setBorder(true)

-- Add button to change whether the contents of the turtle should be dumped in
-- the chest placed behind it.
--local dumpItemsButton = guibutton.GUIButton.new("Dump Items")
--dumpItemsButton:setPreferredBounds(w - 1 - bw, 7, bw, 5)
--local dumpItemsClick = function(e)
--  dumpItems = not dumpItems
--  if dumpItems then
--    dumpItemsButton:setText("Dumping Items")
--  else
--    dumpItemsButton:setText("Not Dumping Items")
--  end
--end
--dumpItemsButton:addButtonListener(dumpItemsClick)

-- Start logging button. When clicked the turtle will start chooping down trees.
--local bw = math.floor((w - 4) / 2)
--local startButton = guibutton.GUIButton.new("Start Logging")
--startButton:setPreferredBounds(3, 7, bw, 5)
--local startClick = function(e)
--  shell.run("logger.lua", loggerWidth, loggerHeight, sleepTime, saplingName, tostring(dumpItems))
--end
--startButton:addButtonListener(addClick)

-- Add the button to the root container.
root:add(widthLabel)
root:add(widthInput)
root:add(heightLabel)
root:add(heightInput)
--root:add(addClickLabel)
--root:add(subtractClickLabel)
--root:add(startButton)
--root:add(dumpItemsButton)
app:setRootContainer(root)
app:start()