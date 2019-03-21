-- Create the application object
local app = guiapplication.GUIApplication:new()

-- Create a root gui component. This is the base component used 
-- in a similar way to JFrame with no decorations.
local root = guirootcontainer.GUIRootContainer:new()

-- Create a new button with desired size and position.
-- Position is relative to root component.
local button = guibutton.GUIButton:new("hello")
button:setPrefferedBounds(5, 5, 10, 20)

-- Add the button to the root container.
root:add(button)
app:setRootContainer(root)
app:start()