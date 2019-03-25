-- Create the application object
local app = guiapplication.GUIApplication:new()

local w, h = term.getSize()

-- Create a root gui component. This is the base component used 
-- in a similar way to JFrame with no decorations.
local root = guirootcontainer.GUIRootContainer:new()

-- Title text that should be centered
local title = guitext.GUIText:new("Example Button Application")
title:setTextAlign("center")
title:setTextVerticalAlign("middle")
title:setBorder(false)
title:setPreferredBounds(2, 3, w - 2, 3)

local clickLabel = guitext.GUIText:new("Click Count:")
clickLabel:setTextAlign("right")
clickLabel:setTextVerticalAlign("middle")
clickLabel:setPreferredBounds(2, 6, (w - 2) / 2, 3)
clickLabel:setBorder(false)

local clickCount = guitext.GUIText:new("0")
clickCount:setTextAlign("left")
clickCount:setTextVerticalAlign("middle")
clickCount:setPreferredBounds((w / 2) + 1, 6, (w - 2) / 2, 3)
clickCount:setBorder(false)

-- Add and subtract buttons
local count = 0
local addClick = function(e)
    count = count + 1
    clickCount:setText(tostring(count))
end
local subtractClick = function(e)
    count = count - 1
    clickCount:setText(tostring(count))
end
local addButton = guibutton.GUIButton:new("Add Click")
addButton:setPreferredBounds(3, 10, (w - 4) / 2, 7)
addButton:addButtonListener(addClick)

local subtractButton = guibutton.GUIButton:new("Subtract Click")
subtractButton:setPreferredBounds((w - 4) / 2 + 4, 10, (w - 4) / 2, 7)
subtractButton:addButtonListener(subtractClick)

-- Add the button to the root container.
root:add(title)
root:add(clickLabel)
root:add(clickCount)
root:add(addButton)
root:add(subtractButton)
app:setRootContainer(root)
app:start()