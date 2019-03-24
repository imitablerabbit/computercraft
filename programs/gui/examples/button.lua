-- Create the application object
local app = guiapplication.GUIApplication:new()

-- Create a root gui component. This is the base component used 
-- in a similar way to JFrame with no decorations.
local root = guirootcontainer.GUIRootContainer:new()

-- Create a new button with desired size and position.
-- Position is relative to root component.
local button = guibutton.GUIButton:new("Click me!")
button:setPreferredBounds(3, 3, 15, 9)
local onClick = function(e)
    -- print("Ya clicked the button ya goof")
    -- print("x: "..e.x..", y: "..e.y)
    -- app:stop()
end
button:addButtonListener(onClick)

-- Add the button to the root container.
root:add(button)
app:setRootContainer(root)
app:start()