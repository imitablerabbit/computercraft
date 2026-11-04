--[[
A settings form built with layouts: a vertical box of rows, each row a
horizontal box with a fixed label and a flexible field. Shows GUIText,
GUIInput, GUICheckbox, GUIDropdown and GUIButton, and how the layout
redoes itself when the screen changes.

Click a field to edit it, Save to show the values at the bottom.
--]]

local app = guiapplication.GUIApplication.new()
local w, h = term.getSize()

local root = guirootcontainer.GUIRootContainer.new()
root:setTitle("Settings form")
root:setBackgroundColor(colors.black)
root:setTextColor(colors.white)
app:setRootContainer(root)

-- The page under the title bar: rows stacked top to bottom with a gap.
local page = guicomponent.GUIComponent.new()
page:setBackgroundColor(colors.black)
page:setBorder(false)
page:setPreferredBounds(1, 2, w, h - 1)
page:setLayout(guilayout.GUIBoxLayout.new("vertical", 0, 0))
root:add(page)

-- A row: a label of fixed width, then a field that takes the rest.
local function row(labelText, field, height)
  local r = guicomponent.GUIComponent.new()
  r:setBackgroundColor(colors.black)
  r:setBorder(false)
  r:setPreferredBounds(1, 1, w, height or 1)
  r:setLayout(guilayout.GUIBoxLayout.new("horizontal", 1, 0))
  local label = guitext.GUIText.new(" " .. labelText)
  label:setPreferredBounds(1, 1, 12, 1)
  label:setBorder(false)
  label:setBackgroundColor(colors.black)
  label:setTextColor(colors.lightGray)
  label:setTextAlign("left")
  r:add(label)
  field:setFlex(1)
  r:add(field)
  page:add(r)
  return r
end

local name = guiinput.GUIInput.new("Digger")
name:setPreferredBounds(1, 1, 20, 3)
name:setBorder(true)
row("Label", name, 3)

local fuel = guiinput.GUIInput.new("1000")
fuel:setPreferredBounds(1, 1, 20, 3)
fuel:setBorder(true)
row("Fuel", fuel, 3)

local torches = guicheckbox.GUICheckbox.new("place torches", true)
torches:setPreferredBounds(1, 1, 20, 1)
row("Torches", torches)

local returnHome = guicheckbox.GUICheckbox.new("come back when done", false)
returnHome:setPreferredBounds(1, 1, 20, 1)
row("Return", returnHome)

local chest = guidropdown.GUIDropdown.new({ "left", "right", "behind", "below", "above" }, 1)
chest:setPreferredBounds(1, 1, 12, 1)
chest:setStretch(false)
row("Chest", chest)

-- Buttons side by side in a grid, then a status line that fills the rest.
local buttons = guicomponent.GUIComponent.new()
buttons:setBackgroundColor(colors.black)
buttons:setBorder(false)
buttons:setPreferredBounds(1, 1, w, 3)
buttons:setLayout(guilayout.GUIGridLayout.new(1, 3, 1, 0))
page:add(buttons)

local status = guitext.GUIText.new("Fill in the form and press Save.")
status:setBorder(false)
status:setBackgroundColor(colors.gray)
status:setTextColor(colors.white)
status:setTextAlign("left")
status:setFlex(1)
page:add(status)

local function button(text, color, fn)
  local b = guibutton.GUIButton.new(text)
  b:setPreferredBounds(1, 1, 10, 3)
  b:setBackgroundColor(color)
  b:setTextColor(colors.white)
  b:addButtonListener(fn)
  buttons:add(b)
  return b
end

button("Save", colors.green, function()
  status:setTextColor(colors.white)
  status:setText(string.format("%s fuel=%s torches=%s return=%s chest=%s",
    name:getText(), fuel:getText(), tostring(torches:isChecked()), tostring(returnHome:isChecked()), tostring(chest:getValue())))
end)
button("Reset", colors.orange, function()
  name:setText("Digger")
  fuel:setText("1000")
  torches:setChecked(true)
  returnHome:setChecked(false)
  chest:setValue("left")
  status:setText("Reset to the defaults.")
end)
button("Quit", colors.red, function() app:stop() end)

app:setUPS(20)
app:start()
