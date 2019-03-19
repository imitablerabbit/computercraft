local app = guiapplication.GUIApplication:new()

-- Create root container to handle window object
local w, h = term.getSize()
local win = window.create(term.current(), 0, 0, w, h) -- TODO: maybe change to 1, 1
local root = guiroot.GUIRootComponent:new(win)

-- TODO: how does the button setup the mouse listeners when it
-- is being added to the parent? Maybe the parent has to call
-- a function on the button?
local button = guibutton:GUIButton:new("hello")

root.add(button) -- This is responsible for setting up mouse?


app.start()