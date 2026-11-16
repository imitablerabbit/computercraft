--[[
A settings form described as a table and built with guibuild: a
vertical box of rows, each row a horizontal box with a fixed label and
a flexible field. Shows GUIText, GUIInput, GUICheckbox, GUIDropdown and
GUIButton, how ids give back the components that need code, and how
the layout redoes itself when the screen changes.

Click a field to edit it, Save to show the values at the bottom.
--]]

local app = guiapplication.GUIApplication.new()
local root, ids

-- A row: a label of fixed width, then the field taking the rest.
local function row(labelText, field, height)
  field.flex = 1
  return {
    type = "box", dir = "horizontal", gap = 1, h = height or 1, bg = colors.black,
    children = {
      { type = "text", text = " " .. labelText, w = 12, h = 1, bg = colors.black, fg = colors.lightGray },
      field,
    },
  }
end

local function button(text, color, onPress)
  return { type = "button", text = text, w = 10, h = 3, border = true, bg = color, fg = colors.white, onPress = onPress }
end

local function save()
  ids.status:setText(string.format("%s fuel=%s torches=%s return=%s chest=%s",
    ids.name:getText(), ids.fuel:getText(), tostring(ids.torches:isChecked()),
    tostring(ids.returnHome:isChecked()), tostring(ids.chest:getValue())))
end

local function reset()
  ids.name:setText("Digger")
  ids.fuel:setText("1000")
  ids.torches:setChecked(true)
  ids.returnHome:setChecked(false)
  ids.chest:setValue("left")
  ids.status:setText("Reset to the defaults.")
end

root, ids = guibuild.build({
  type = "root", title = "Settings form", bg = colors.black, fg = colors.white,
  dir = "vertical", gap = 0,
  children = {
    row("Label", { type = "input", id = "name", text = "Digger", h = 3, border = true }, 3),
    row("Fuel", { type = "input", id = "fuel", text = "1000", h = 3, border = true }, 3),
    row("Torches", { type = "checkbox", id = "torches", text = "place torches", checked = true }),
    row("Return", { type = "checkbox", id = "returnHome", text = "come back when done" }),
    row("Chest", { type = "dropdown", id = "chest", options = { "left", "right", "behind", "below", "above" },
                   w = 12, stretch = false }),
    -- Buttons side by side in a grid, then a status line that fills the rest.
    { type = "grid", rows = 1, columns = 3, gap = 1, h = 3, bg = colors.black, children = {
      button("Save", colors.green, save),
      button("Reset", colors.orange, reset),
      button("Quit", colors.red, function() app:stop() end),
    } },
    { type = "text", id = "status", text = "Fill in the form and press Save.", flex = 1,
      bg = colors.gray, fg = colors.white },
  },
})

app:setRootContainer(root)
app:setUPS(20)
app:start()
