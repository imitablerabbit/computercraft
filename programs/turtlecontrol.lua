--[[
Turtle control is a touch screen dashboard for the turtles running
turtleagent. It runs on a computer with a modem and an advanced monitor,
or on the computer's own screen when there is no monitor, which is how
it runs on an advanced pocket computer with a wireless modem. Screens
rearrange themselves for narrow displays.

Screens:
  main    an icon per turtle that changes with what the turtle is doing
          (red with NEEDS HELP when it raised an alert, e.g. no fuel);
          touch one to open it
  turtle  state and fuel, buttons for the jobs in turtlectl, Items,
          Move, Shell and Stop
  job     a form for the job's parameters (length, torches, chest side,
          sapling ...) with a Start button; switches are checkboxes and
          choices are dropdowns; values are remembered per turtle
  text    an on screen keyboard to edit one text value of a job form
  move    a pad of single steps and actions (forward, turn, dig, place ...)
  shell   an on screen keyboard to type a command line that runs on the
          turtle, with its output streamed back
  items   the turtle's inventory as a 4x4 grid with fuel (F) and block
          (B) icons, refreshed from the turtle while open
  discover a dropdown of the items the turtle carries, to pick a text
          value such as the sapling name from them
  fuel    the items the turtle never burns as fuel, with Remove buttons
          and Add from what it carries or by name
  item    details of one slot with Select, Refuel and Drop buttons

Turtles are found by their status broadcasts. If a registry file from
registrylistener exists its turtles are shown as offline until heard from.

Usage: turtlecontrol [monitorSide|term] [textScale] [registryFile]
  monitorSide  the monitor to use (default: the first one found, or
               the computer's own screen when there is none); "term"
               forces the computer's own screen
--]]

local args = {...}
local monitorSide = args[1]
local textScale = tonumber(args[2]) or 0.5
local registryFile = args[3] or "registry_store.dat"

local discoverEvery = 10 -- seconds between discover broadcasts
local offlineAfter = 20  -- seconds without a status before a turtle is offline
local animateEvery = 0.5 -- seconds between busy animation frames
local maxOutput = 100    -- shell output lines kept per turtle
local inventoryEvery = 3 -- seconds between inventory requests while on the items screen

--[[
Display and peripherals. The display is an advanced monitor when one
is attached or named, otherwise the computer's own screen (a pocket
computer, or any advanced computer with a mouse).
--]]

local monitor, display
if monitorSide == "term" or monitorSide == "screen" then
  monitorSide = nil
elseif monitorSide then
  monitor = peripheral.wrap(monitorSide)
  if not monitor then
    print("Error: no monitor on side " .. monitorSide)
    return
  end
else
  monitor = peripheral.find("monitor")
  if monitor then monitorSide = peripheral.getName(monitor) end
end
if monitor then
  if not monitor.isColor() then
    print("Error: an advanced monitor is needed for touch")
    return
  end
  monitor.setTextScale(textScale)
  display = monitor
else
  display = term.current()
  if not display.isColor() then
    print("Error: an advanced computer is needed for the mouse")
    return
  end
end
if not turtlectl.openModem() then
  print("Error: no modem attached")
  return
end

--[[
Turtle records: id -> { id, label, state, job, message, fuel, lastSeen,
                        output = {}, command = "", lastMove,
                        inventory = {}, selected, inventoryMessage,
                        alerts = {} (kind -> message of help needed),
                        fuelBlacklist (list of item names, nil until asked) }
--]]

local turtles = {}

local function sortedTurtles()
  local list = {}
  for id, t in pairs(turtles) do table.insert(list, t) end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

local function getTurtle(id)
  local t = turtles[id]
  if not t then
    t = { id = id, label = "Turtle " .. id, state = "offline", output = {}, command = "", forms = {}, alerts = {} }
    turtles[id] = t
  end
  return t
end

-- Seed the list from the registry so known turtles show as offline.
local function loadRegistry(file)
  if not fs.exists(file) then return end
  local reg = registry.new()
  reg:loadFile(file)
  for i, record in pairs(reg.records or {}) do
    local id, ctype, label = tonumber(record[1]), record[2], record[3]
    if id and ctype and ctype:find("turtle") then
      local t = getTurtle(id)
      if label and label ~= "" then t.label = label end
    end
  end
end

local function addOutput(t, text)
  table.insert(t.output, text)
  while #t.output > maxOutput do table.remove(t.output, 1) end
end

--[[
Screen helpers
--]]

local app = guiapplication.GUIApplication.new()
local icons = {}   -- id -> GUITurtleIcon on the main screen
local screen = nil -- the open screen: { id, refresh, tick, onAck, onOutput }
local showMain, showTurtle, showMove, showShell, showJobForm, showTextInput
local showInventory, showItemDetail, showDiscover, showFuelRules

local function setScreen(root, handlers)
  icons = {}
  screen = handlers
  app:setRootContainer(root)
  root:setStarted(true)
  root:repaint()
  if screen and screen.refresh then screen.refresh() end
end

local function newRoot(title, decorations)
  local root = guirootcontainer.GUIRootContainer.new(display, monitorSide)
  root:setTitle(title)
  root:setBackgroundColor(colors.black)
  root:setBorderColor(colors.gray)
  root:setTextColor(colors.white)
  root:setDecorations(decorations or false)
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

-- A dropdown showing value (or the first option) from options.
local function newDropdown(options, value, x, y, w)
  local index = 1
  for i, o in ipairs(options) do
    if o == value then index = i end
  end
  local dropdown = guidropdown.GUIDropdown.new(options, index)
  dropdown:setPreferredBounds(x, y, math.max(3, w), 1)
  dropdown:setBackgroundColor(colors.cyan)
  dropdown:setTextColor(colors.white)
  dropdown:setListColor(colors.gray)
  dropdown:setHighlightColor(colors.lightGray)
  return dropdown
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

-- Title row with Back (and optionally Stop) buttons at the right.
local function addHeader(root, w, title, onBack, onStop)
  root:add(newLabel(title, 1, 1, w, colors.yellow))
  local x = w - 5
  root:add(newButton("Back", x, 1, 6, 1, colors.gray, onBack))
  if onStop then
    x = x - 7
    root:add(newButton("Stop", x, 1, 6, 1, colors.red, onStop))
  end
end

-- The help a turtle is asking for, as one line, or nil.
local function alertText(t)
  local kinds = {}
  for kind in pairs(t.alerts or {}) do kinds[#kinds + 1] = kind end
  if #kinds == 0 then return nil end
  table.sort(kinds)
  local parts = {}
  for i, kind in ipairs(kinds) do parts[i] = t.alerts[kind] end
  return table.concat(parts, "; ")
end

local function fuelText(t)
  local fuel = t.fuel and tostring(t.fuel) or "?"
  if t.fuelLimit then fuel = fuel .. " / " .. t.fuelLimit end
  return fuel
end

local function sendStop(t)
  turtlectl.sendCommand(t.id, "stop")
  t.message = "stop sent..."
end

-- Send a job with the values from the turtle's form (or the defaults).
local function startJob(t, job)
  turtlectl.sendCommand(t.id, job.id, turtlectl.jobArgs(job, t.forms[job.id]))
  t.state = "busy"
  t.job = job.id
  t.message = "sent " .. job.id .. "..."
end

--[[
Main screen: a grid of turtle icons.
--]]

showMain = function()
  local root = newRoot("Turtle Control", true)
  local w, h = display.getSize()
  local tileW, tileH = guiturtleicon.GUITurtleIcon.MinWidth, guiturtleicon.GUITurtleIcon.MinHeight
  local gap = 1
  if w < tileW + 2 or h < tileH + 2 then
    tileW, tileH, gap = math.max(8, w - 2), 4, 0 -- compact tiles for small monitors
  end
  local columns = math.max(1, math.floor((w - gap) / (tileW + gap)))
  local list = sortedTurtles()
  local rows = math.max(1, math.floor((h - 1 - gap) / (tileH + gap)))
  if columns < 2 or columns * rows < #list then
    -- Narrow screens, or more turtles than big tiles fit: text tiles
    -- two to a row, four rows tall.
    gap = 1
    tileW = math.max(8, math.floor((w - 3 * gap) / 2))
    tileH = 4
    columns = math.max(1, math.floor((w - gap) / (tileW + gap)))
  end
  if #list == 0 then
    root:add(newLabel("Waiting for turtles...", 2, 3, w - 2, colors.lightGray))
    root:add(newLabel("Run turtleagent on each turtle", 2, 4, w - 2, colors.gray))
  end
  local tiles = {}
  for i, t in ipairs(list) do
    local col = (i - 1) % columns
    local row = math.floor((i - 1) / columns)
    local x = 1 + gap + col * (tileW + gap)
    local y = 2 + gap + row * (tileH + gap)
    if y + tileH - 1 <= h then
      local icon = guiturtleicon.GUITurtleIcon.new(t)
      icon:setPreferredBounds(x, y, tileW, tileH)
      icon:addSelectListener(function(e) showTurtle(e.turtle.id) end)
      root:add(icon)
      tiles[t.id] = icon
    end
  end
  setScreen(root, {
    isMain = true,
    tick = function() for id, icon in pairs(tiles) do icon:tick() end end,
  })
  icons = tiles
end

--[[
Turtle screen: status lines and buttons for jobs, Move, Shell, Stop.
--]]

showTurtle = function(id)
  local t = turtles[id]
  if not t then return showMain() end
  local root = newRoot(t.label)
  local w, h = display.getSize()
  local iconW, iconH = guiturtleicon.GUITurtleIcon.MinWidth, guiturtleicon.GUITurtleIcon.MinHeight

  -- Header: the icon with status lines beside it, or three text lines
  -- when the monitor is too small for that.
  local lines, top, icon
  if w >= iconW * 2 and h >= iconH + 4 then
    icon = guiturtleicon.GUITurtleIcon.new(t)
    icon:setPreferredBounds(1, 1, iconW, iconH)
    icon:setBorder(false)
    root:add(icon)
    local textX = iconW + 1
    local textW = w - textX
    lines = {
      title = newLabel(t.label .. " (#" .. id .. ")", textX, 2, textW, colors.yellow),
      state = newLabel("", textX, 3, textW),
      job = newLabel("", textX, 4, textW),
      fuel = newLabel("", textX, 5, textW),
      message = newLabel("", textX, 6, textW, colors.lightGray),
    }
    top = iconH + 1
  else
    lines = {
      title = newLabel(t.label .. " (#" .. id .. ")", 1, 1, w, colors.yellow),
      state = newLabel("", 1, 2, w),
      fuel = newLabel("", 1, 3, w),
    }
    top = 4
  end
  for k, label in pairs(lines) do root:add(label) end

  -- Buttons: one per job, then Move and Shell, then Stop and Back.
  local actions = {}
  for i, job in ipairs(turtlectl.jobs) do
    table.insert(actions, { name = job.name, color = colors.blue, fn = function()
      if t.state == "busy" then
        t.message = "Busy, stop it first"
        screen.refresh()
      elseif job.params and #job.params > 0 then
        showJobForm(id, job)
      else
        startJob(t, job)
        screen.refresh()
      end
    end })
  end
  table.insert(actions, { name = "Items", color = colors.orange, fn = function() showInventory(id) end })
  table.insert(actions, { name = "Fuel", color = colors.brown, fn = function() showFuelRules(id) end })
  table.insert(actions, { name = "Move", color = colors.green, fn = function() showMove(id) end })
  table.insert(actions, { name = "Shell", color = colors.purple, fn = function() showShell(id) end })
  table.insert(actions, { name = "Stop", color = colors.red, fn = function() sendStop(t); screen.refresh() end })
  table.insert(actions, { name = "Back", color = colors.gray, fn = function() showMain() end })

  local columns = (w >= 34) and 3 or 2
  local rows = math.ceil(#actions / columns)
  local gap = (h - top + 1 >= rows * 2 - 1) and 1 or 0 -- drop the gaps when rows are tight
  local bw = math.floor((w - (columns + 1)) / columns)
  local bh = math.floor((h - top + 1 - (rows - 1) * gap) / rows)
  bh = math.max(1, math.min(3, bh))
  for i, action in ipairs(actions) do
    local col = (i - 1) % columns
    local row = math.floor((i - 1) / columns)
    local x = 2 + col * (bw + 1)
    local y = top + row * (bh + gap)
    root:add(newButton(action.name, x, y, bw, bh, action.color, action.fn))
  end

  setScreen(root, {
    id = id,
    tick = function() if icon then icon:tick() end end,
    refresh = function()
      local t = turtles[id]
      if icon then icon:setInfo(t) end
      local help = alertText(t)
      if lines.job then
        lines.state:setText("State: " .. (t.state or "?") .. (help and ", needs help" or ""))
        lines.job:setText("Job:   " .. (t.job or "-"))
        lines.fuel:setText("Fuel:  " .. fuelText(t))
        lines.message:setTextColor(help and colors.red or colors.lightGray)
        lines.message:setText(help and ("NEEDS HELP: " .. help) or (t.message or ""))
      else
        lines.state:setTextColor(help and colors.red or colors.white)
        lines.state:setText(help and ("HELP: " .. help) or ((t.state or "?") .. " " .. (t.job or "")))
        lines.fuel:setText("Fuel: " .. fuelText(t))
      end
    end,
  })
end

--[[
Move screen: a pad of single steps and actions.
--]]

-- Buttons by column and row of a 7 x 3 grid.
local movePad = {
  { name = "Fwd",    action = "forward",   col = 2, row = 1 },
  { name = "TurnL",  action = "left",      col = 1, row = 2 },
  { name = "Back",   action = "back",      col = 2, row = 2 },
  { name = "TurnR",  action = "right",     col = 3, row = 2 },
  { name = "Up",     action = "up",        col = 4, row = 1 },
  { name = "Down",   action = "down",      col = 4, row = 2 },
  { name = "DigUp",  action = "digUp",     col = 5, row = 1 },
  { name = "Dig",    action = "dig",       col = 5, row = 2 },
  { name = "DigDn",  action = "digDown",   col = 5, row = 3 },
  { name = "PlcUp",  action = "placeUp",   col = 6, row = 1 },
  { name = "Place",  action = "place",     col = 6, row = 2 },
  { name = "PlcDn",  action = "placeDown", col = 6, row = 3 },
  { name = "Suck",   action = "suck",      col = 7, row = 2 },
  { name = "Drop",   action = "drop",      col = 7, row = 3 },
}

-- The same actions four to a row for narrow screens.
local movePadNarrow = {
  { name = "Fwd",    action = "forward",   col = 1, row = 1 },
  { name = "Up",     action = "up",        col = 2, row = 1 },
  { name = "DigUp",  action = "digUp",     col = 3, row = 1 },
  { name = "PlcUp",  action = "placeUp",   col = 4, row = 1 },
  { name = "TurnL",  action = "left",      col = 1, row = 2 },
  { name = "Back",   action = "back",      col = 2, row = 2 },
  { name = "TurnR",  action = "right",     col = 3, row = 2 },
  { name = "Down",   action = "down",      col = 4, row = 2 },
  { name = "Dig",    action = "dig",       col = 1, row = 3 },
  { name = "Place",  action = "place",     col = 2, row = 3 },
  { name = "Suck",   action = "suck",      col = 3, row = 3 },
  { name = "Drop",   action = "drop",      col = 4, row = 3 },
  { name = "DigDn",  action = "digDown",   col = 1, row = 4 },
  { name = "PlcDn",  action = "placeDown", col = 2, row = 4 },
}

showMove = function(id)
  local t = turtles[id]
  if not t then return showMain() end
  local root = newRoot(t.label)
  local w, h = display.getSize()
  addHeader(root, w, "Move " .. t.label, function() showTurtle(id) end)
  local status = newLabel("", 1, 2, w, colors.lightGray)
  root:add(status)

  local top, gap = 3, 1
  local pad, cols, rows = movePad, 7, 3
  if w < 7 * 4 + 6 then pad, cols, rows = movePadNarrow, 4, 4 end
  local bw = math.floor((w - gap * (cols - 1)) / cols)
  local bh = math.floor((h - top + 1 - gap * (rows - 1)) / rows)
  bh = math.max(1, math.min(4, bh))
  for i, key in ipairs(pad) do
    local x = 1 + (key.col - 1) * (bw + gap)
    local y = top + (key.row - 1) * (bh + gap)
    local color = colors.blue
    if key.action:find("dig") then color = colors.brown
    elseif key.action:find("place") or key.action == "suck" or key.action == "drop" then color = colors.cyan end
    root:add(newButton(key.name, x, y, bw, bh, color, function()
      if t.state == "busy" then
        t.lastMove = "busy with " .. tostring(t.job) .. ", stop it first"
      else
        turtlectl.sendMove(id, key.action)
        t.lastMove = key.action .. "..."
      end
      screen.refresh()
    end))
  end

  setScreen(root, {
    id = id,
    refresh = function()
      local t = turtles[id]
      status:setText("Fuel " .. fuelText(t) .. "  " .. (t.lastMove or "touch a button"))
    end,
    onAck = function(msg)
      t.lastMove = msg.job .. ": " .. (msg.message or (msg.ok and "ok" or "failed"))
      screen.refresh()
    end,
  })
end

--[[
Items screen: the turtle's inventory grid, polled while open.
--]]

showInventory = function(id)
  local t = turtles[id]
  if not t then return showMain() end
  local root = newRoot(t.label)
  local w, h = display.getSize()
  addHeader(root, w, "Items " .. t.label, function() showTurtle(id) end)
  local status = newLabel("", 1, 2, w, colors.lightGray)
  root:add(status)
  local grid = guiinventorygrid.GUIInventoryGrid.new(t.inventory, t.selected)
  grid:setPreferredBounds(1, 3, w, h - 2)
  grid:addSelectListener(function(e)
    if e.item then showItemDetail(id, e.slot) end
  end)
  root:add(grid)

  turtlectl.requestInventory(id)
  t.inventoryMessage = t.inventory and "" or "asking the turtle..."
  local ticks = 0
  setScreen(root, {
    id = id,
    refresh = function()
      local t = turtles[id]
      grid:setItems(t.inventory, t.selected)
      status:setText("Fuel " .. fuelText(t) .. "  " .. (t.inventoryMessage or ""))
    end,
    onInventory = function() screen.refresh() end,
    tick = function()
      ticks = ticks + 1
      if ticks * animateEvery >= inventoryEvery then
        ticks = 0
        turtlectl.requestInventory(id)
      end
    end,
  })
end

--[[
Item screen: one slot's details with Select, Refuel and Drop.
--]]

showItemDetail = function(id, slot)
  local t = turtles[id]
  if not t then return showMain() end
  local item = t.inventory and t.inventory[slot]
  if not item then return showInventory(id) end
  local root = newRoot(t.label)
  local w, h = display.getSize()
  addHeader(root, w, "Slot " .. slot .. " on " .. t.label, function() showInventory(id) end)

  local bh = (h >= 16) and 3 or 1
  local by = h - bh + 1
  local status = newLabel("", 1, by - 1, w, colors.lightGray)
  root:add(status)
  local labelW = math.min(9, math.floor(w / 4))
  local valueX = labelW + 2
  local valueW = w - valueX
  local y = 2
  local function addRow(label, value, color)
    if y >= by - 1 then return end
    root:add(newLabel(label, 1, y, labelW, colors.lightGray))
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

  local bw = math.floor((w - 3) / 4)
  local bx = 1 + math.floor((w - (bw * 4 + 3)) / 2)
  local function act(action)
    return function()
      if t.state == "busy" then
        t.inventoryMessage = "busy with " .. tostring(t.job) .. ", stop it first"
      else
        turtlectl.sendSlotAction(id, action, slot)
        t.inventoryMessage = action .. "..."
      end
      screen.refresh()
    end
  end
  root:add(newButton("Back", bx, by, bw, bh, colors.gray, function() showInventory(id) end))
  root:add(newButton("Select", bx + bw + 1, by, bw, bh, colors.blue, act("select")))
  root:add(newButton("Refuel", bx + (bw + 1) * 2, by, bw, bh, item.fuel and colors.orange or colors.gray, act("refuel")))
  root:add(newButton("Drop", bx + (bw + 1) * 3, by, bw, bh, colors.red, act("drop")))

  setScreen(root, {
    id = id,
    refresh = function()
      local t = turtles[id]
      status:setText("Fuel " .. fuelText(t) .. "  " .. (t.inventoryMessage or ""))
    end,
    onAck = function(msg)
      if turtlectl.slotActions[msg.job] then
        t.inventoryMessage = msg.job .. ": " .. (msg.message or (msg.ok and "ok" or "failed"))
      end
      screen.refresh()
    end,
    onInventory = function(before)
      -- Rebuild when the slot changed, leave when it emptied.
      local now = t.inventory[slot]
      if not now then
        showInventory(id)
      elseif turtleinv.changed(before, now) then
        showItemDetail(id, slot)
      end
    end,
  })
end

--[[
Shell screen: output pane, command line and an on screen keyboard.
--]]

-- Keyboard rows. A string is one key per character; a table entry is a
-- wider special key with its width in key units.
local keyboard = {
  { "1234567890-=" },
  { "qwertyuiop/" },
  { "asdfghjkl:_" },
  { "zxcvbnm.,", { name = "<", units = 2, key = "left" }, { name = ">", units = 2, key = "right" } },
  { { name = "Shift", units = 2, key = "shift" }, { name = "Space", units = 5, key = " " },
    { name = "Bksp", units = 2, key = "bksp" }, { name = "Clear", units = 2, key = "clear" },
    { name = "Run", units = 2, key = "enter" } },
}
local keyUnits = 13 -- widest row, in key units

-- A line of text with a cursor, driven by keyboard keys: characters
-- are inserted at the cursor, bksp deletes before it, left and right
-- move it, clear empties the line. key returns true on enter.
local function newLineEditor(text)
  local ed = { text = text or "", pos = #(text or "") }
  function ed.key(key)
    if key == "bksp" then
      if ed.pos > 0 then
        ed.text = ed.text:sub(1, ed.pos - 1) .. ed.text:sub(ed.pos + 1)
        ed.pos = ed.pos - 1
      end
    elseif key == "clear" then
      ed.text, ed.pos = "", 0
    elseif key == "left" then
      ed.pos = math.max(0, ed.pos - 1)
    elseif key == "right" then
      ed.pos = math.min(#ed.text, ed.pos + 1)
    elseif key == "enter" then
      return true
    else
      ed.text = ed.text:sub(1, ed.pos) .. key .. ed.text:sub(ed.pos + 1)
      ed.pos = ed.pos + #key
    end
    return false
  end
  function ed.set(text)
    ed.text, ed.pos = text, #text
  end
  -- The line as shown: prefix, then the text with | at the cursor,
  -- scrolled so the cursor stays within width.
  function ed.render(prefix, width)
    local shown = prefix .. ed.text:sub(1, ed.pos) .. "|" .. ed.text:sub(ed.pos + 1)
    local cursorAt = #prefix + ed.pos + 1
    if #shown > width then
      local start = math.max(1, cursorAt - width + 1)
      shown = shown:sub(start, start + width - 1)
    end
    return shown
  end
  return ed
end

-- Let the computer's own keyboard drive an on screen keyboard's onKey:
-- typed characters, enter, backspace and the arrows.
local function hookKeys(root, onKey)
  root:addCharListener(function(e) onKey(e.char) end)
  root:addKeyPressListener(function(e)
    local k = e.keycode
    if k == keys.enter then onKey("enter")
    elseif k == keys.backspace then onKey("bksp")
    elseif k == keys.left then onKey("left")
    elseif k == keys.right then onKey("right")
    end
  end)
end

-- Add the keyboard to root with its top row at keyTop. onKey gets a
-- character, or "bksp", "clear", "left", "right" or "enter". Shift is
-- handled here. enterName renames the Run key.
local function addKeyboard(root, w, keyTop, onKey, enterName)
  local keyW = math.max(1, math.floor(w / keyUnits))
  local shift = false
  local letterKeys = {}
  local function press(key)
    if key == "shift" then
      shift = not shift
      for i, k in ipairs(letterKeys) do
        k.button:setText(shift and k.char:upper() or k.char)
      end
      return
    end
    if #key == 1 and shift then key = key:upper() end
    onKey(key)
  end
  for r, row in ipairs(keyboard) do
    local x = 1
    local y = keyTop + r - 1
    for i, entry in ipairs(row) do
      if type(entry) == "string" then
        for c = 1, #entry do
          local char = entry:sub(c, c)
          local button = newButton(char, x, y, keyW, 1, colors.gray, function() press(char) end)
          root:add(button)
          if char:match("%a") then table.insert(letterKeys, { char = char, button = button }) end
          x = x + keyW
        end
      else
        local color = colors.lightGray
        local name = entry.name
        if entry.key == "enter" then
          color = colors.green
          name = enterName or name
        elseif entry.key == "clear" then
          color = colors.red
        end
        root:add(newButton(name, x, y, keyW * entry.units, 1, color, function() press(entry.key) end))
        x = x + keyW * entry.units
      end
    end
  end
end

--[[
Job form: one row per parameter, then Start.
--]]

showJobForm = function(id, job)
  local t = turtles[id]
  if not t then return showMain() end
  if not t.forms[job.id] then t.forms[job.id] = turtlectl.jobDefaults(job) end
  local values = t.forms[job.id]
  local root = newRoot(t.label)
  local w, h = display.getSize()
  addHeader(root, w, job.name .. " on " .. t.label, function() showTurtle(id) end)

  local top = 3
  local labelW = math.min(12, math.floor(w / 3))
  -- When the five number buttons do not fit beside the label, each
  -- parameter takes two rows: the label, then its controls.
  local narrow = w - labelW - 1 < 20
  local rowsPer = narrow and 2 or 1
  local startH = (h - top >= #job.params * (rowsPer + 1) + 3) and 3 or 1
  local gap = (h - top - startH >= #job.params * (rowsPer + 1)) and (rowsPer + 1) or rowsPer
  local cellW = math.max(3, math.floor(((narrow and (w - 1)) or (w - labelW - 1)) / 5))
  local valueButtons = {}

  local function valueText(param)
    local v = values[param.name]
    if param.type == "bool" then return v and "true" or "false" end
    return tostring(v)
  end

  for i, param in ipairs(job.params) do
    local y = top + (i - 1) * gap
    root:add(newLabel(param.label, 1, y, narrow and (w - 1) or labelW, colors.lightGray))
    local x = labelW + 2
    if narrow then x, y = 2, y + 1 end
    if param.type == "number" then
      local small = (param.step and param.step[1]) or 1
      local big = (param.step and param.step[2]) or 10
      local function adjust(delta)
        local v = (tonumber(values[param.name]) or param.default) + delta
        if param.min and v < param.min then v = param.min end
        if param.max and v > param.max then v = param.max end
        values[param.name] = v
        valueButtons[i]:setText(valueText(param))
      end
      root:add(newButton("-" .. big, x, y, cellW - 1, 1, colors.blue, function() adjust(-big) end))
      root:add(newButton("-" .. small, x + cellW, y, cellW - 1, 1, colors.blue, function() adjust(-small) end))
      valueButtons[i] = newLabel(valueText(param), x + cellW * 2, y, cellW - 1, colors.yellow)
      valueButtons[i]:setTextAlign("center")
      root:add(valueButtons[i])
      root:add(newButton("+" .. small, x + cellW * 3, y, cellW - 1, 1, colors.blue, function() adjust(small) end))
      root:add(newButton("+" .. big, x + cellW * 4, y, cellW - 1, 1, colors.blue, function() adjust(big) end))
    elseif param.type == "bool" then
      local box = guicheckbox.GUICheckbox.new(values[param.name] and "yes" or "no", values[param.name])
      box:setPreferredBounds(x, y, cellW * 2 - 1, 1)
      box:addChangeListener(function(e)
        values[param.name] = e.checked
        box:setText(e.checked and "yes" or "no")
      end)
      root:add(box)
    elseif param.type == "choice" or (param.type == "string" and param.options) then
      -- A dropdown. A text parameter with options also offers Other...
      -- which opens the keyboard, and shows a typed value at the top.
      local options = {}
      for i, o in ipairs(param.options or {}) do options[i] = tostring(o) end
      local custom = param.type == "string"
      local current = values[param.name]
      if custom then
        local known = false
        for _, o in ipairs(options) do
          if o == current then known = true end
        end
        if current ~= nil and current ~= "" and not known then table.insert(options, 1, tostring(current)) end
        table.insert(options, "Discover...")
        table.insert(options, "Other...")
      end
      local longest = 0
      for _, o in ipairs(options) do longest = math.max(longest, #o) end
      local dw = math.min(w - x + 1, math.max(cellW * 2 - 1, longest + 3))
      local dropdown = newDropdown(options, current, x, y, dw)
      dropdown:addSelectListener(function(e)
        if custom and e.value == "Other..." then
          showTextInput(param.label, tostring(values[param.name] or ""), function(text)
            values[param.name] = text
            showJobForm(id, job)
          end, function() showJobForm(id, job) end)
        elseif custom and e.value == "Discover..." then
          showDiscover(id, param, function(name)
            values[param.name] = name
            showJobForm(id, job)
          end, function() showJobForm(id, job) end)
        else
          values[param.name] = e.value
        end
      end)
      root:add(dropdown)
    else
      root:add(newButton(valueText(param), x, y, w - x, 1, colors.purple, function()
        showTextInput(param.label, tostring(values[param.name] or ""), function(text)
          values[param.name] = text
          showJobForm(id, job)
        end, function() showJobForm(id, job) end)
      end))
    end
  end

  local startY = math.min(h - startH + 1, top + #job.params * gap)
  root:add(newButton("Start " .. job.name, 2, startY, w - 2, startH, colors.green, function()
    startJob(t, job)
    showTurtle(id)
  end))

  setScreen(root, { id = id })
end

--[[
Discover: pick a value for a text parameter from what the turtle is
carrying. The turtle is asked for its inventory and the item names are
offered in a dropdown, saplings first. onPick(name) or onCancel().
--]]

-- Distinct item names in an inventory with their counts, saplings
-- first, then the rest, each group sorted.
local function carriedItems(inventory)
  local counts = {}
  for slot, item in pairs(inventory or {}) do
    if type(item) == "table" and item.name then
      counts[item.name] = (counts[item.name] or 0) + (tonumber(item.count) or 0)
    end
  end
  local saplings, others = {}, {}
  for name in pairs(counts) do
    if name:find("sapling") or name:find("propagule") then saplings[#saplings + 1] = name else others[#others + 1] = name end
  end
  table.sort(saplings)
  table.sort(others)
  local names = {}
  for i, name in ipairs(saplings) do names[#names + 1] = name end
  for i, name in ipairs(others) do names[#names + 1] = name end
  return names, counts
end

showDiscover = function(id, param, onPick, onCancel, fresh)
  local t = turtles[id]
  if not t then return showMain() end
  local root = newRoot(t.label)
  local w, h = display.getSize()
  addHeader(root, w, param.label .. " from " .. t.label, onCancel)
  local names, counts = carriedItems(t.inventory)
  local signature = {}
  for i, name in ipairs(names) do signature[i] = name .. "=" .. counts[name] end
  signature = table.concat(signature, ",")

  local dropdown
  if #names == 0 then
    root:add(newLabel(t.inventory and "The turtle is carrying nothing." or "Asking the turtle what it carries...", 2, 3, w - 2, colors.lightGray))
  else
    root:add(newLabel("Touch to pick one of the " .. #names .. " items it carries:", 2, 3, w - 2, colors.lightGray))
    local options, longest = {}, 0
    for i, name in ipairs(names) do
      options[i] = name .. " x" .. counts[name]
      longest = math.max(longest, #options[i])
    end
    dropdown = newDropdown(options, nil, 2, 5, math.min(w - 2, longest + 3))
    dropdown:addSelectListener(function(e) onPick(names[e.index]) end)
    root:add(dropdown)
  end

  if not fresh then turtlectl.requestInventory(id) end
  local ticks = 0
  setScreen(root, {
    id = id,
    onInventory = function()
      -- Only rebuild when what is carried changed, so an open list is
      -- not reset by every reply.
      local newNames, newCounts = carriedItems(t.inventory)
      local newSignature = {}
      for i, name in ipairs(newNames) do newSignature[i] = name .. "=" .. newCounts[name] end
      if table.concat(newSignature, ",") ~= signature then
        showDiscover(id, param, onPick, onCancel, true)
      end
    end,
    tick = function()
      ticks = ticks + 1
      if ticks * animateEvery >= inventoryEvery then
        ticks = 0
        turtlectl.requestInventory(id)
      end
    end,
  })
  if dropdown then dropdown:openList() end
end

--[[
Fuel rules: the items the turtle never burns, with Remove buttons, and
ways to add one from what it carries (Discover) or by name.
--]]

showFuelRules = function(id)
  local t = turtles[id]
  if not t then return showMain() end
  local root = newRoot(t.label)
  local w, h = display.getSize()
  addHeader(root, w, "Fuel rules " .. t.label, function() showTurtle(id) end)
  local status = newLabel("", 1, 2, w, colors.lightGray)
  root:add(status)
  root:add(newLabel("Never burnt as fuel:", 1, 3, w, colors.yellow))

  local bh = (h >= 16) and 3 or 1
  local by = h - bh + 1
  local lastRow = by - 2
  local list = t.fuelBlacklist
  if not list then
    root:add(newLabel("asking the turtle...", 2, 4, w - 2, colors.lightGray))
  elseif #list == 0 then
    root:add(newLabel("nothing, every fuel item may be burnt", 2, 4, w - 2, colors.lightGray))
  else
    -- One row per item in a scroll pane, so long lists fit.
    local rows = guicomponent.GUIComponent.new()
    rows:setBackgroundColor(colors.black)
    rows:setBorder(false)
    rows:setLayout(guilayout.GUIBoxLayout.new("vertical", 0, 0))
    for i, name in ipairs(list) do
      local row = guicomponent.GUIComponent.new()
      row:setBackgroundColor(colors.black)
      row:setBorder(false)
      row:setPreferredBounds(1, 1, w, 1)
      row:setLayout(guilayout.GUIBoxLayout.new("horizontal", 1, 0))
      local label = newLabel(tostring(name), 1, 1, 1, colors.white)
      label:setFlex(1)
      row:add(label)
      row:add(newButton("Remove", 1, 1, 8, 1, colors.red, function()
        turtlectl.sendFuelRules(id, "remove", name)
        t.fuelMessage = "removing " .. tostring(name) .. "..."
        screen.refresh()
      end))
      rows:add(row)
    end
    local pane = guiscrollpane.GUIScrollPane.new()
    pane:setPreferredBounds(2, 4, w - 2, math.max(1, lastRow - 3))
    pane:setContent(rows)
    root:add(pane)
  end

  local bw = math.floor((w - 3) / 2)
  root:add(newButton(w < 40 and "Carried..." or "Add carried item", 2, by, bw, bh, colors.green, function()
    showDiscover(id, { label = "Never burn" }, function(name)
      turtlectl.sendFuelRules(id, "add", name)
      t.fuelMessage = "adding " .. name .. "..."
      showFuelRules(id)
    end, function() showFuelRules(id) end)
  end))
  root:add(newButton(w < 40 and "By name..." or "Add by name", 3 + bw, by, bw, bh, colors.purple, function()
    showTextInput("Never burn", "", function(text)
      if text ~= "" then
        turtlectl.sendFuelRules(id, "add", text)
        t.fuelMessage = "adding " .. text .. "..."
      end
      showFuelRules(id)
    end, function() showFuelRules(id) end)
  end))

  if not list then turtlectl.sendFuelRules(id, "get") end
  setScreen(root, {
    id = id,
    refresh = function() status:setText(t.fuelMessage or "") end,
    onAck = function(msg)
      if msg.job == "fuel" then t.fuelMessage = msg.message or (msg.ok and "ok" or "refused") end
      screen.refresh()
    end,
    onFuelList = function() showFuelRules(id) end,
  })
end

--[[
Text input: edit one value with the keyboard. onDone(text) or onCancel().
--]]

showTextInput = function(prompt, initial, onDone, onCancel)
  local root = newRoot(prompt)
  local w, h = display.getSize()
  addHeader(root, w, prompt, onCancel)
  local editor = newLineEditor(initial)
  local keyTop = h - #keyboard + 1
  local line = newLabel("", 1, math.max(2, math.floor((keyTop + 1) / 2)), w, colors.yellow)
  root:add(line)
  local function refresh()
    line:setText(editor.render("> ", w))
  end
  local function onKey(key)
    if editor.key(key) then return onDone(editor.text) end
    refresh()
  end
  addKeyboard(root, w, keyTop, onKey, "Done")
  hookKeys(root, onKey)
  setScreen(root, { refresh = refresh })
end

showShell = function(id)
  local t = turtles[id]
  if not t then return showMain() end
  local root = newRoot(t.label)
  local w, h = display.getSize()
  addHeader(root, w, "Shell " .. t.label, function() showTurtle(id) end,
    function() sendStop(t); addOutput(t, "[stop sent]"); screen.refresh() end)

  local keyTop = h - #keyboard + 1
  local cmdRow = keyTop - 1
  local outRows = cmdRow - 2 -- rows 2 .. cmdRow-1 show output
  local outLines = {}
  for i = 1, outRows do
    local label = newLabel("", 1, 1 + i, w)
    root:add(label)
    outLines[i] = label
  end
  local cmdLine = newLabel("", 1, cmdRow, w, colors.yellow)
  root:add(cmdLine)

  -- The half typed command line is kept per turtle between visits.
  if not t.editor then t.editor = newLineEditor(t.command) end
  local function onKey(key)
    if t.editor.key(key) then
      if t.editor.text ~= "" then
        addOutput(t, "> " .. t.editor.text)
        turtlectl.sendShell(id, t.editor.text, w)
        t.editor.set("")
      end
    end
    t.command = t.editor.text
    screen.refresh()
  end
  addKeyboard(root, w, keyTop, onKey, "Run")
  hookKeys(root, onKey)

  t.lastStatusMessage = t.message -- only report status changes from now on
  setScreen(root, {
    id = id,
    refresh = function()
      local t = turtles[id]
      local first = math.max(1, #t.output - outRows + 1)
      for i = 1, outRows do
        outLines[i]:setText(t.output[first + i - 1] or "")
      end
      cmdLine:setText(t.editor.render("> ", w))
    end,
    onAck = function(msg)
      if msg.job == "shell" and not msg.ok then addOutput(t, "[refused: " .. (msg.message or "") .. "]") end
      if msg.job == "stop" then addOutput(t, "[" .. (msg.message or "stop") .. "]") end
      screen.refresh()
    end,
    onOutput = function() screen.refresh() end,
    onStatus = function(status)
      if status.state ~= "busy" and status.message and status.message ~= t.lastStatusMessage then
        addOutput(t, "[" .. status.message .. "]")
      end
      t.lastStatusMessage = status.message
      screen.refresh()
    end,
  })
end

--[[
Network and timers
--]]

local function onStatus(msg)
  local id = msg.id
  local isNew = turtles[id] == nil
  local t = getTurtle(id)
  t.label = msg.label or t.label
  t.state = msg.state or "idle"
  t.job = msg.job
  t.message = msg.message
  t.fuel = msg.fuel
  t.fuelLimit = msg.fuelLimit
  if type(msg.alerts) == "table" then t.alerts = msg.alerts end
  t.lastSeen = os.clock()
  if screen and screen.id == id then
    if screen.onStatus then screen.onStatus(msg) elseif screen.refresh then screen.refresh() end
  elseif isNew and screen and screen.isMain then
    showMain()
  elseif icons[id] then
    icons[id]:setInfo(t)
  end
end

local function onAck(sender, msg)
  local t = turtles[sender]
  if not t then return end
  if msg.ok then
    t.message = msg.job .. ": " .. (msg.message or "ok")
  else
    t.message = msg.job .. " refused: " .. (msg.message or "")
    if msg.job ~= "stop" and not turtlectl.moves[msg.job] then
      t.state = "idle"
      t.job = nil
    end
  end
  if screen and screen.id == sender then
    if screen.onAck then screen.onAck(msg) elseif screen.refresh then screen.refresh() end
  end
end

-- The turtle told us which items it never burns.
local function onFuelList(sender, msg)
  local t = turtles[sender]
  if not t or type(msg.blacklist) ~= "table" then return end
  local list = {}
  for i, name in ipairs(msg.blacklist) do list[i] = tostring(name) end
  t.fuelBlacklist = list
  if screen and screen.id == sender and screen.onFuelList then screen.onFuelList() end
end

-- A turtle needs help, or no longer does.
local function onAlert(sender, msg)
  local t = turtles[sender]
  if not t or type(msg.kind) ~= "string" then return end
  if msg.active then
    t.alerts[msg.kind] = msg.message or msg.kind
    t.message = "needs help: " .. (msg.message or msg.kind)
  else
    t.alerts[msg.kind] = nil
    if next(t.alerts) == nil then t.message = "help no longer needed" end
  end
  if screen and screen.id == sender then
    if screen.refresh then screen.refresh() end
  elseif icons[sender] then
    icons[sender]:setInfo(t)
  end
end

local function onOutput(sender, msg)
  local t = turtles[sender]
  if not t then return end
  addOutput(t, tostring(msg.text))
  if screen and screen.id == sender and screen.onOutput then screen.onOutput() end
end

local function onInventory(sender, msg)
  local t = turtles[sender]
  if not t or type(msg.items) ~= "table" then return end
  local before = t.inventory or {}
  local items = {}
  for key, item in pairs(msg.items) do
    local slot = tonumber(key)
    if slot and type(item) == "table" then items[slot] = item end
  end
  t.inventory = items
  t.selected = tonumber(msg.selected)
  if t.inventoryMessage == "asking the turtle..." then t.inventoryMessage = "" end
  if screen and screen.id == sender and screen.onInventory then
    screen.onInventory(screen.slot and before[screen.slot] or nil)
  end
end

local function markOffline()
  local now = os.clock()
  for id, t in pairs(turtles) do
    if t.state ~= "offline" and t.lastSeen and now - t.lastSeen > offlineAfter then
      t.state = "offline"
      t.job = nil
      if icons[id] then icons[id]:setInfo(t) end
      if screen and screen.id == id and screen.refresh then screen.refresh() end
    end
  end
end

local discoverTimer = os.startTimer(0)
local animateTimer = os.startTimer(animateEvery)

app:addEventListener(function(event)
  if event[1] == "rednet_message" then
    local sender, msg, protocol = event[2], event[3], event[4]
    if protocol == turtlectl.PROTOCOL then
      if turtlectl.isMessage(msg, "status") then
        onStatus(msg)
      elseif turtlectl.isMessage(msg, "ack") then
        onAck(sender, msg)
      elseif turtlectl.isMessage(msg, "output") then
        onOutput(sender, msg)
      elseif turtlectl.isMessage(msg, "inventory") then
        onInventory(sender, msg)
      elseif turtlectl.isMessage(msg, "alert") then
        onAlert(sender, msg)
      elseif turtlectl.isMessage(msg, "fuel") then
        onFuelList(sender, msg)
      end
    end
  elseif event[1] == "timer" then
    if event[2] == discoverTimer then
      turtlectl.broadcastDiscover()
      markOffline()
      discoverTimer = os.startTimer(discoverEvery)
    elseif event[2] == animateTimer then
      if screen and screen.tick then screen.tick() end
      animateTimer = os.startTimer(animateEvery)
    end
  end
end)

--[[
Start
--]]

loadRegistry(registryFile)
if monitor then
  print("Turtle control on monitor " .. monitorSide .. ", close with the x on the monitor")
end
app:setUPS(20)
showMain()
app:start()
display.setBackgroundColor(colors.black)
display.setTextColor(colors.white)
display.clear()
display.setCursorPos(1, 1)
