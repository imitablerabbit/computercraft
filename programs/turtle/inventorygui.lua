--[[
Inventory GUI shows the turtle's 16 inventory slots as a 4x4 grid on
the turtle's own screen. Each filled slot shows the item name and
count plus two icons: an orange F when the item can be burnt as fuel
and a green B when it looks like a block that can be placed. Press a
slot (mouse on an advanced turtle, or arrow keys and Enter on a plain
one) to see the item's details and act on it.

The same grid is shown remotely by turtlecontrol; the reading and
classifying lives in the turtleinv api.

Usage: inventorygui
Keys: arrows move, Enter opens a slot, Backspace goes back, Q quits.
--]]

local RescanEvery = 2

if not turtle then
  print("inventorygui must run on a turtle")
  return
end

--[[
State
--]]

local app = guiapplication.GUIApplication.new()
local items = turtleinv.scan(true)
local cursor = turtleinv.MinSlot
local screen = nil
local rescanTimer = nil

local function fuelText()
  local level = turtle.getFuelLevel()
  if level == "unlimited" then return "fuel: unlimited" end
  return "fuel: " .. tostring(level)
end

--[[
Widgets
--]]

local function newRoot(title)
  local root = guirootcontainer.GUIRootContainer.new()
  root:setTitle(title)
  root:setBackgroundColor(colors.black)
  root:setBorderColor(colors.gray)
  root:setTextColor(colors.white)
  root:setDecorations(true)
  return root
end

local function newLabel(text, x, y, w, color)
  local label = guitext.GUIText.new(text)
  label:setPreferredBounds(x, y, math.max(1, w), 1)
  label:setBorder(false)
  label:setBackgroundColor(colors.black)
  label:setTextColor(color or colors.white)
  return label
end

local function newButton(text, x, y, w, h, color, onClick)
  local button = guibutton.GUIButton.new(text)
  button:setPreferredBounds(x, y, math.max(1, w), math.max(1, h))
  button:setBackgroundColor(color or colors.blue)
  button.pressColor = colors.lightGray
  button:setTextColor(colors.white)
  button:setBorderColor(colors.gray)
  button:setBorder(h >= 3)
  if onClick then button:addButtonListener(onClick) end
  return button
end

-- screen handlers: refresh redraws in place, onChange reacts to the
-- inventory changing, slot is set on the detail screen.
local function setScreen(root, handlers)
  screen = handlers
  app:setRootContainer(root)
  root:setStarted(true)
  root:repaint()
  if screen and screen.refresh then screen.refresh() end
end

--[[
Screens
--]]

local showGrid, showDetail

-- Main screen: title bar with the fuel level and the 4x4 grid.
showGrid = function()
  local root = newRoot("Inventory  " .. fuelText())
  local w, h = root.w, root.h
  local grid = guiinventorygrid.GUIInventoryGrid.new(items, turtle.getSelectedSlot())
  grid:setPreferredBounds(1, 2, w, h - 1)
  grid:setCursor(cursor)
  grid:addSelectListener(function(e)
    cursor = e.slot
    if e.item then showDetail(e.slot) end
  end)
  root:add(grid)
  root:addKeyPressListener(function(e)
    local k = e.keycode
    if k == keys.left then grid:moveCursor(-1, 0)
    elseif k == keys.right then grid:moveCursor(1, 0)
    elseif k == keys.up then grid:moveCursor(0, -1)
    elseif k == keys.down then grid:moveCursor(0, 1)
    elseif k == keys.enter then grid:select(grid:getCursor())
    elseif k == keys.q then app:stop()
    end
    cursor = grid:getCursor()
  end)
  local refresh = function()
    root:setTitle("Inventory  " .. fuelText())
    grid:setItems(items, turtle.getSelectedSlot())
    root:repaint()
  end
  setScreen(root, { refresh = refresh, onChange = refresh })
end

-- Detail screen for one slot with Select, Refuel and Drop actions.
showDetail = function(slot)
  local item = items[slot]
  if not item then
    -- Nothing to show. Only leave the detail screen if we are on it.
    if screen and screen.slot then showGrid() end
    return
  end
  local root = newRoot("Slot " .. slot)
  local w, h = root.w, root.h
  local labelW = 9
  local valueX = labelW + 2
  local valueW = w - valueX
  local bh = h >= 13 and 3 or 1
  local lastRow = h - bh - 1
  local y = 2
  local function addRow(label, value, color)
    if y > lastRow then return end
    root:add(newLabel(label, 2, y, labelW, colors.lightGray))
    root:add(newLabel(value, valueX, y, valueW, color))
    y = y + 1
  end
  for i, row in ipairs(turtleinv.detailRows(item)) do
    addRow(row.label, row.value, row.color)
  end
  local tags = turtleinv.tagText(item)
  if tags then
    for i, line in ipairs(turtleinv.wrap(tags, valueW)) do
      addRow(i == 1 and "Tags" or "", line, colors.lightGray)
    end
  end

  -- Action buttons along the bottom.
  local by = h - bh + 1
  local bw = math.floor((w - 3) / 4)
  local bx = 1 + math.floor((w - (bw * 4 + 3)) / 2)
  local function act(fn)
    return function()
      fn()
      items = turtleinv.scan(true)
      if items[slot] then showDetail(slot) else showGrid() end
    end
  end
  root:add(newButton("Back", bx, by, bw, bh, colors.gray, function() showGrid() end))
  root:add(newButton("Select", bx + bw + 1, by, bw, bh, colors.blue, act(function()
    turtle.select(slot)
  end)))
  root:add(newButton("Refuel", bx + (bw + 1) * 2, by, bw, bh, item.fuel and colors.orange or colors.gray, act(function()
    if not item.fuel then return end
    local selected = turtle.getSelectedSlot()
    turtle.select(slot)
    turtle.refuel(1)
    turtle.select(selected)
  end)))
  root:add(newButton("Drop", bx + (bw + 1) * 3, by, bw, bh, colors.red, act(function()
    local selected = turtle.getSelectedSlot()
    turtle.select(slot)
    turtle.drop()
    turtle.select(selected)
  end)))
  root:addKeyPressListener(function(e)
    if e.keycode == keys.backspace then showGrid()
    elseif e.keycode == keys.q then app:stop()
    end
  end)
  setScreen(root, {
    slot = slot,
    onChange = function()
      -- The slot changed under us: rebuild with the new contents.
      if not items[slot] then showGrid() else showDetail(slot) end
    end,
  })
end

--[[
Events
--]]

local function rescan()
  local before = items
  items = turtleinv.scan(true)
  for slot = turtleinv.MinSlot, turtleinv.MaxSlot do
    if turtleinv.changed(before[slot], items[slot]) then
      if screen and screen.onChange then screen.onChange() end
      return
    end
  end
  if screen and screen.refresh then
    screen.refresh() -- keeps the fuel level in the title current
  end
end

app:addEventListener(function(event)
  if event[1] == "turtle_inventory" then
    rescan()
  elseif event[1] == "timer" and event[2] == rescanTimer then
    rescan()
    rescanTimer = os.startTimer(RescanEvery)
  end
end)

--[[
Start
--]]

app:setUPS(20)
showGrid()
rescanTimer = os.startTimer(RescanEvery)
app:start()
