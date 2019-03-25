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
clickLabel:setPreferredBounds(2, 8, (w - 2) / 2, 3)
clickLabel:setBorder(false)

local clickCount = guitext.GUIText:new("0")
clickCount:setTextAlign("left")
clickCount:setTextVerticalAlign("middle")
clickCount:setPreferredBounds((w / 2) + 1, 8, (w - 2) / 2, 3)
clickCount:setBorder(false)

-- Create a new button with desired size and position.
-- Position is relative to root component.
local button = guibutton.GUIButton:new("Click me!")
button:setPreferredBounds(3, 15, w - 2, 9)
local count = 0
local onClick = function(e)
    count = count + 1
    clickCount:setText(tostring(count))
end
button:addButtonListener(onClick)

-- Add the button to the root container.
root:add(title)
root:add(clickLabel)
root:add(clickCount)
root:add(button)
app:setRootContainer(root)
app:start()