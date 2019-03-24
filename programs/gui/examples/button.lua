-- Create the application object
print("creating new application")
local app = guiapplication.GUIApplication:new()
print("created application")

-- Create a root gui component. This is the base component used 
-- in a similar way to JFrame with no decorations.
local root = guirootcontainer.GUIRootContainer:new()
print("created new root container")


-- Create a new button with desired size and position.
-- Position is relative to root component.
local button = guibutton.GUIButton:new("hello")
print("created button")

button:setPreferredBounds(5, 5, 20, 10)
print("set button bounds")

local onClick = function(e)
    -- print("Ya clicked the button ya goof")
    -- print("x: "..e.x..", y: "..e.y)
    -- app:stop()
end
button:addButtonListener(onClick)
print("added button listener")


-- Add the button to the root container.
root:add(button)
print("add button to root")

app:setRootContainer(root)
print("set root container on application")

print("starting application")
app:start()
print("stopped application")

