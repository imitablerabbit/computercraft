--[[
A layout playground. Six coloured boxes sit in a container whose
layout the buttons change: vertical or horizontal box, grid, the gap
between boxes, and whether box C shares the space (flex) or keeps its
fixed 8x3 size. Watch how the boxes move as the settings change.
--]]

local app = guiapplication.GUIApplication.new()
local w, h = term.getSize()

local root = guirootcontainer.GUIRootContainer.new()
root:setTitle("Layout playground")
root:setBackgroundColor(colors.black)
root:setTextColor(colors.white)
app:setRootContainer(root)

local page = guicomponent.GUIComponent.new()
page:setBackgroundColor(colors.black)
page:setBorder(false)
page:setPreferredBounds(1, 2, w, h - 1)
page:setLayout(guilayout.GUIBoxLayout.new("vertical", 0, 0))
root:add(page)

-- The controls along the top.
local controls = guicomponent.GUIComponent.new()
controls:setBackgroundColor(colors.black)
controls:setBorder(false)
controls:setPreferredBounds(1, 1, w, 1)
controls:setLayout(guilayout.GUIBoxLayout.new("horizontal", 1, 0))
page:add(controls)

-- The stage whose layout is changed.
local stage = guicomponent.GUIComponent.new()
stage:setBackgroundColor(colors.black)
stage:setBorderColor(colors.gray)
stage:setBorder(true)
stage:setFlex(1)
page:add(stage)

local settings = { axis = "vertical", mode = "box", gap = 1, flex = true }
local palette = { colors.red, colors.orange, colors.yellow, colors.lime, colors.cyan, colors.purple }
local boxes = {}
for i = 1, 6 do
  local b = guitext.GUIText.new(string.char(64 + i))
  b:setPreferredBounds(1, 1, 8, 3)
  b:setBorder(false)
  b:setBackgroundColor(palette[i])
  b:setTextColor(colors.black)
  b:setTextAlign("center")
  b:setFlex(1) -- share the space; C can be made a fixed 8x3 instead
  stage:add(b)
  boxes[i] = b
end

local function apply()
  boxes[3]:setFlex(settings.flex and 1 or 0)
  if settings.mode == "grid" then
    stage:setLayout(guilayout.GUIGridLayout.new(2, 3, settings.gap, 1))
  else
    stage:setLayout(guilayout.GUIBoxLayout.new(settings.axis, settings.gap, 1))
  end
  root:repaint()
end

local function control(text, fn)
  local b = guibutton.GUIButton.new(text)
  b:setPreferredBounds(1, 1, #text + 2, 1)
  b:setBorder(false)
  b:setBackgroundColor(colors.blue)
  b:setTextColor(colors.white)
  b:addButtonListener(function()
    fn()
    apply()
  end)
  controls:add(b)
  return b
end

local axisButton = control("vertical", function()
  settings.mode = "box"
  settings.axis = settings.axis == "vertical" and "horizontal" or "vertical"
end)
control("grid", function() settings.mode = "grid" end)
local gapButton = control("gap 1", function() settings.gap = (settings.gap + 1) % 3 end)
local flexButton = control("C fixed", function() settings.flex = not settings.flex end)
control("quit", function() app:stop() end)

local function names()
  axisButton:setText(settings.mode == "grid" and "box" or settings.axis)
  gapButton:setText("gap " .. settings.gap)
  flexButton:setText(settings.flex and "C flex" or "C fixed")
end
for _, b in ipairs(controls.children) do
  b:addButtonListener(names)
end

apply()
names()
app:setUPS(20)
app:start()
