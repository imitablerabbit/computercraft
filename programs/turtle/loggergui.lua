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
widthLabel:setPreferredBounds(labelX, 2, labelW, labelH)
widthLabel:setBorder(false)
local widthInput = guiinput.GUIInput.new(loggerWidth)
widthInput:setPreferredBounds(inputX, 2, inputW, inputH) 
widthInput:setBorder(true)

-- Setup the logging height label and input.
local heightLabel = guitext.GUIText.new("Height:")
heightLabel:setTextAlign("left")
heightLabel:setTextVerticalAlign("middle")
heightLabel:setPreferredBounds(labelX, 4, labelW, labelH)
heightLabel:setBorder(false)
local heightInput = guiinput.GUIInput.new(loggerHeight)
heightInput:setPreferredBounds(inputX, 4, inputW, inputH) 
heightInput:setBorder(true)

-- Setup the logging sleepTime label and input.
local sleepTimeLabel = guitext.GUIText.new("Sleep:")
sleepTimeLabel:setTextAlign("left")
sleepTimeLabel:setTextVerticalAlign("middle")
sleepTimeLabel:setPreferredBounds(labelX, 6, labelW, labelH)
sleepTimeLabel:setBorder(false)
local sleepTimeInput = guiinput.GUIInput.new(sleepTime)
sleepTimeInput:setPreferredBounds(inputX, 6, inputW, inputH) 
sleepTimeInput:setBorder(true)

-- Setup the logging height label and input.
local saplingLabel = guitext.GUIText.new("Sapling:")
saplingLabel:setTextAlign("left")
saplingLabel:setTextVerticalAlign("middle")
saplingLabel:setPreferredBounds(labelX, 8, labelW, labelH)
saplingLabel:setBorder(false)
local saplingInput = guiinput.GUIInput.new(saplingName)
saplingInput:setPreferredBounds(inputX, 8, inputW, inputH) 
saplingInput:setBorder(true)

-- Start logging button. When clicked the turtle will start chooping down trees.
local bw = w - (outerPadding * 2)
local startButton = guibutton.GUIButton.new("Start Logging")
startButton:setPreferredBounds(outerPadding, 11, bw, 3)
local startClick = function(e)
  shouldExecute = true
  app:stop()
end
startButton:addButtonListener(startClick)

-- Add the button to the root container.
root:add(widthLabel)
root:add(widthInput)
root:add(heightLabel)
root:add(heightInput)
root:add(sleepTimeLabel)
root:add(sleepTimeInput)
root:add(saplingLabel)
root:add(saplingInput)
root:add(startButton)
app:setRootContainer(root)
app:start()

-- Check whether the button was clicked to say whether we should execute the
-- command. This is needed as we might exit the application in other ways.
-- Ultimately this should be fixed by having seperate coroutines. One for UI
-- the other for the model side of things.
if shouldExecute then
  loggerWidth = widthInput:getText()
  loggerHeight = heightInput:getText()
  sleepTime = sleepTimeInput:getText()
  saplingName = saplingInput:getText()
  local prog = {"logger", loggerWidth, loggerHeight, saplingName, sleepTime, "true"}
  print(table.unpack(prog))
  shell.run(table.unpack(prog))
end