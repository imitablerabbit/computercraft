local count = 0

-- Create the application object
local app = guiapplication.GUIApplication.new()

local w, h = term.getSize()

-- Create a root gui component. This is the base component used 
-- in a similar way to JFrame with no decorations.
local root = guirootcontainer.GUIRootContainer.new()
root:setTitle("Example Input Application")

local clickLabel = guitext.GUIText.new("Count: "..count)
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
delta:setPreferredBounds(3, 6, w-4, 3) 
delta:setBorder(true)

local status = guitext.GUIText.new("Status: ")
status:setPreferredBounds(1, h-1, w, 1)
status:setBackgroundColor(colors.lightgray)
status:setBorder(false)

local addClick = function(e)
    local countDelta = tonumber(delta:getText())
    if not countDelta then 
        status:setText("Status: "..countDelta.." not a number")
        status:setTextColor(red)
        return
    else
        status:setText("Status:")
        status:setTextColor(black)
    end
    count = count + countDelta
    clickLabel:setText("Count: "..count)
end
local bw = math.floor((w - 4) / 2)
local addButton = guibutton.GUIButton.new("Add Click")
addButton:setPreferredBounds(3, 10, bw, 5)
addButton:addButtonListener(addClick)

-- Add the button to the root container.
root:add(clickLabel)
root:add(deltaLabel)
root:add(delta)
root:add(addButton)
root:add(status)
app:setRootContainer(root)
app:start()