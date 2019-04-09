local count = 0
local addCount = 0
local subCount = 0

function clickCount()
    return "Click Count: "..count
end

function addClickCount()
    return "Add Click Count: "..addCount
end

function subtractClickCount()
    return "Subtract Click Count: "..subCount
end

-- Create the application object
local app = guiapplication.GUIApplication.new()

local w, h = term.getSize()

-- Create a root gui component. This is the base component used 
-- in a similar way to JFrame with no decorations.
local root = guirootcontainer.GUIRootContainer.new()
root:setTitle("Example Button Application")

local clickLabel = guitext.GUIText.new(clickCount())
clickLabel:setTextAlign("left")
clickLabel:setTextVerticalAlign("middle")
clickLabel:setPreferredBounds(3, 3, w, 1) 
clickLabel:setBorder(false)

local addClickLabel = guitext.GUIText.new(addClickCount())
addClickLabel:setTextAlign("left")
addClickLabel:setTextVerticalAlign("middle")
addClickLabel:setPreferredBounds(3, 4, w, 1) 
addClickLabel:setBorder(false)

local subtractClickLabel = guitext.GUIText.new(subtractClickCount())
subtractClickLabel:setTextAlign("left")
subtractClickLabel:setTextVerticalAlign("middle")
subtractClickLabel:setPreferredBounds(3, 5, w, 1) 
subtractClickLabel:setBorder(false)

-- Add and subtract buttons
-- TODO: These are somehow getting 2 events triggered when the button is pressed.
local addClick = function(e)
    count = count + 1
    addCount = addCount + 1
    clickLabel:setText(clickCount())
    addClickLabel:setText(addClickCount())
end
local subtractClick = function(e)
    count = count - 1
    subCount = subCount + 1
    clickLabel:setText(clickCount())
    subtractClickLabel:setText(subtractClickCount())
end
local bw = math.floor((w - 4) / 2)
local addButton = guibutton.GUIButton.new("Add Click")
addButton:setPreferredBounds(3, 7, bw, 5)
addButton:addButtonListener(addClick)

local subtractButton = guibutton.GUIButton.new("Subtract Click")
subtractButton:setPreferredBounds(w - 1 - bw, 7, bw, 5)
subtractButton:addButtonListener(subtractClick)

-- Add the button to the root container.
root:add(clickLabel)
root:add(addClickLabel)
root:add(subtractClickLabel)
root:add(addButton)
root:add(subtractButton)
app:setRootContainer(root)
app:start()