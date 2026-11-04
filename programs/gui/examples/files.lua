--[[
A file browser in a scroll pane. Each row is a horizontal box with the
name taking the spare width and an Open button for directories. The
list scrolls with the bar at the right, the mouse wheel, and paging on
the track. Up goes to the parent directory.

Usage: files [directory]
--]]

local args = { ... }
local dir = args[1] or ""

local app = guiapplication.GUIApplication.new()
local w, h = term.getSize()

local root = guirootcontainer.GUIRootContainer.new()
root:setBackgroundColor(colors.black)
root:setTextColor(colors.white)
app:setRootContainer(root)

local page = guicomponent.GUIComponent.new()
page:setBackgroundColor(colors.black)
page:setBorder(false)
page:setPreferredBounds(1, 2, w, h - 1)
page:setLayout(guilayout.GUIBoxLayout.new("vertical", 0, 0))
root:add(page)

-- Tool row: Up and a count of entries.
local tools = guicomponent.GUIComponent.new()
tools:setBackgroundColor(colors.black)
tools:setBorder(false)
tools:setPreferredBounds(1, 1, w, 1)
tools:setLayout(guilayout.GUIBoxLayout.new("horizontal", 1, 0))
page:add(tools)

local up = guibutton.GUIButton.new("Up")
up:setPreferredBounds(1, 1, 6, 1)
up:setBorder(false)
up:setBackgroundColor(colors.gray)
up:setTextColor(colors.white)
tools:add(up)

local count = guitext.GUIText.new("")
count:setBorder(false)
count:setBackgroundColor(colors.black)
count:setTextColor(colors.lightGray)
count:setTextAlign("left")
count:setFlex(1)
tools:add(count)

local pane = guiscrollpane.GUIScrollPane.new()
pane:setFlex(1)
page:add(pane)

local show

local function newRow(name, isDir)
  local r = guicomponent.GUIComponent.new()
  r:setBackgroundColor(colors.black)
  r:setBorder(false)
  r:setPreferredBounds(1, 1, w, 1)
  r:setLayout(guilayout.GUIBoxLayout.new("horizontal", 1, 0))
  local label = guitext.GUIText.new((isDir and "/" or " ") .. name)
  label:setBorder(false)
  label:setBackgroundColor(colors.black)
  label:setTextColor(isDir and colors.lime or colors.white)
  label:setTextAlign("left")
  label:setFlex(1)
  r:add(label)
  if isDir then
    local open = guibutton.GUIButton.new("Open")
    open:setPreferredBounds(1, 1, 6, 1)
    open:setBorder(false)
    open:setBackgroundColor(colors.blue)
    open:setTextColor(colors.white)
    open:addButtonListener(function() show(fs.combine(dir, name)) end)
    r:add(open)
  else
    local size = guitext.GUIText.new(tostring(fs.getSize(fs.combine(dir, name))) .. "b")
    size:setPreferredBounds(1, 1, 8, 1)
    size:setBorder(false)
    size:setBackgroundColor(colors.black)
    size:setTextColor(colors.lightGray)
    size:setTextAlign("right")
    r:add(size)
  end
  return r
end

show = function(path)
  dir = path
  root:setTitle("/" .. dir)
  local rows = guicomponent.GUIComponent.new()
  rows:setBackgroundColor(colors.black)
  rows:setBorder(false)
  rows:setLayout(guilayout.GUIBoxLayout.new("vertical", 0, 0))
  local names = fs.list(dir)
  table.sort(names, function(a, b)
    local da, db = fs.isDir(fs.combine(dir, a)), fs.isDir(fs.combine(dir, b))
    if da ~= db then return da end
    return a < b
  end)
  for _, name in ipairs(names) do
    rows:add(newRow(name, fs.isDir(fs.combine(dir, name))))
  end
  pane:setContent(rows)
  count:setText(#names .. " entries")
  root:repaint()
end

up:addButtonListener(function()
  if dir ~= "" then show(fs.getDir(dir)) end
end)

show(dir)
app:setUPS(20)
app:start()
