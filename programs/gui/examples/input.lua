local count = 0

-- Create the application object
local app = guiapplication.GUIApplication.new()

local w, h = term.getSize()

-- Create a root gui component. This is the base component used 
-- in a similar way to JFrame with no decorations.
local root = guirootcontainer.GUIRootContainer.new()
root:setTitle("Example Input Application")

local clickLabel = guitext.GUIText.new(clickCount())
clickLabel:setTextAlign("left")
clickLabel:setTextVerticalAlign("middle")
clickLabel:setPreferredBounds(3, 3, w, 1) 
clickLabel:setBorder(false)

local deltaLabel = guitext.GUIText.new("Click Delta:")
deltaLabel:setTextAlign("left")
deltaLabel:setTextVerticalAlign("middle")
deltaLabel:setPreferredBounds(3, 5, w, 1) 
deltaLabel:setBorder(false)

local delta = guiinput.GUIInput.new("1")
delta:setPreferredBounds(3, 6, w, 3) 
delta:setBorder(true)

-- Add and subtract buttons
-- TODO: These are somehow getting 2 events triggered when the button is pressed.
local addClick = function(e)
    local countDelta = tonumber(delta:getText())
    count = count + countDelta
    clickLabel:setText(count)
end
local bw = math.floor((w - 4) / 2)
local addButton = guibutton.GUIButton.new("Add Click")
addButton:setPreferredBounds(3, 10, bw, 5)
addButton:addButtonListener(addClick)

-- Add the button to the root container.
root:add(clickLabel)
root:add(addClickLabel)
root:add(addButton)
app:setRootContainer(root)
app:start()