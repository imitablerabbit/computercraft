--[[
A to-do list: type a task and press Add (or enter), tick it off with
its checkbox, Remove it, or Clear done. The list lives in a scroll
pane so it can grow past the screen, and is saved to todo.dat.

Shows GUIInput with char events, GUICheckbox, GUIScrollPane and
nested box layouts.
--]]

local file = "todo.dat"

local app = guiapplication.GUIApplication.new()
local w, h = term.getSize()

local items = {}
if fs.exists(file) then
  local f = fs.open(file, "r")
  if f then
    items = textutils.unserialize(f.readAll() or "") or {}
    f.close()
  end
end

local function save()
  local f = fs.open(file, "w")
  if f then
    f.write(textutils.serialize(items))
    f.close()
  end
end

local root = guirootcontainer.GUIRootContainer.new()
root:setTitle("To do")
root:setBackgroundColor(colors.black)
root:setTextColor(colors.white)
app:setRootContainer(root)

local page = guicomponent.GUIComponent.new()
page:setBackgroundColor(colors.black)
page:setBorder(false)
page:setPreferredBounds(1, 2, w, h - 1)
page:setLayout(guilayout.GUIBoxLayout.new("vertical", 0, 0))
root:add(page)

-- Entry row: the input takes the width, Add sits at the right.
local entry = guicomponent.GUIComponent.new()
entry:setBackgroundColor(colors.black)
entry:setBorder(false)
entry:setPreferredBounds(1, 1, w, 3)
entry:setLayout(guilayout.GUIBoxLayout.new("horizontal", 1, 0))
page:add(entry)

local input = guiinput.GUIInput.new("")
input:setPreferredBounds(1, 1, 20, 3)
input:setBorder(true)
input:setFlex(1)
entry:add(input)

local add = guibutton.GUIButton.new("Add")
add:setPreferredBounds(1, 1, 7, 3)
add:setBackgroundColor(colors.green)
add:setTextColor(colors.white)
entry:add(add)

local summary = guitext.GUIText.new("")
summary:setPreferredBounds(1, 1, w, 1)
summary:setBorder(false)
summary:setBackgroundColor(colors.black)
summary:setTextColor(colors.lightGray)
summary:setTextAlign("left")
page:add(summary)

local pane = guiscrollpane.GUIScrollPane.new()
pane:setFlex(1)
page:add(pane)

local bottom = guicomponent.GUIComponent.new()
bottom:setBackgroundColor(colors.black)
bottom:setBorder(false)
bottom:setPreferredBounds(1, 1, w, 1)
bottom:setLayout(guilayout.GUIGridLayout.new(1, 2, 1, 0))
page:add(bottom)

local refresh

local function newRow(item, index)
  local r = guicomponent.GUIComponent.new()
  r:setBackgroundColor(colors.black)
  r:setBorder(false)
  r:setPreferredBounds(1, 1, w, 1)
  r:setLayout(guilayout.GUIBoxLayout.new("horizontal", 1, 0))
  local box = guicheckbox.GUICheckbox.new(item.text, item.done)
  box:setFlex(1)
  box:addChangeListener(function(e)
    item.done = e.checked
    save()
    refresh()
  end)
  r:add(box)
  local remove = guibutton.GUIButton.new("Remove")
  remove:setPreferredBounds(1, 1, 8, 1)
  remove:setBorder(false)
  remove:setBackgroundColor(colors.red)
  remove:setTextColor(colors.white)
  remove:addButtonListener(function()
    table.remove(items, index)
    save()
    refresh()
  end)
  r:add(remove)
  return r
end

refresh = function()
  local scroll = pane:getScroll()
  local rows = guicomponent.GUIComponent.new()
  rows:setBackgroundColor(colors.black)
  rows:setBorder(false)
  rows:setLayout(guilayout.GUIBoxLayout.new("vertical", 0, 0))
  local done = 0
  for i, item in ipairs(items) do
    rows:add(newRow(item, i))
    if item.done then done = done + 1 end
  end
  pane:setContent(rows)
  pane:scrollTo(scroll)
  summary:setText(#items == 0 and "Nothing to do. Type a task and press Add." or (done .. " of " .. #items .. " done"))
  root:repaint()
end

local function addItem()
  local text = input:getText()
  if text:match("%S") then
    table.insert(items, { text = text, done = false })
    input:setText("")
    input.cursorPos = 0
    save()
    refresh()
    pane:scrollTo(pane:maxScroll())
  end
end
add:addButtonListener(addItem)
input:addDoneListener(addItem)

local clear = guibutton.GUIButton.new("Clear done")
clear:setPreferredBounds(1, 1, 10, 1)
clear:setBorder(false)
clear:setBackgroundColor(colors.orange)
clear:setTextColor(colors.white)
clear:addButtonListener(function()
  local kept = {}
  for _, item in ipairs(items) do if not item.done then kept[#kept + 1] = item end end
  items = kept
  save()
  refresh()
end)
bottom:add(clear)

local quit = guibutton.GUIButton.new("Quit")
quit:setPreferredBounds(1, 1, 10, 1)
quit:setBorder(false)
quit:setBackgroundColor(colors.gray)
quit:setTextColor(colors.white)
quit:addButtonListener(function() app:stop() end)
bottom:add(quit)

refresh()
app:setUPS(20)
app:start()
