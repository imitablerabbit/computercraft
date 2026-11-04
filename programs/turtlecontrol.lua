--[[
Turtle control is a touch screen dashboard for the turtles running
turtleagent. It runs on a computer with a modem and an advanced monitor.

Screens:
  main    an icon per turtle that changes with what the turtle is doing;
          touch one to open it
  turtle  state and fuel, buttons for the jobs in turtlectl, Move, Shell
          and Stop
  move    a pad of single steps and actions (forward, turn, dig, place ...)
  shell   an on screen keyboard to type a command line that runs on the
          turtle, with its output streamed back

Turtles are found by their status broadcasts. If a registry file from
registrylistener exists its turtles are shown as offline until heard from.

Usage: turtlecontrol [monitorSide] [textScale] [registryFile]
--]]

local args = {...}
local monitorSide = args[1]
local textScale = tonumber(args[2]) or 0.5
local registryFile = args[3] or "registry_store.dat"

local discoverEvery = 10 -- seconds between discover broadcasts
local offlineAfter = 20  -- seconds without a status before a turtle is offline
local animateEvery = 0.5 -- seconds between busy animation frames
local maxOutput = 100    -- shell output lines kept per turtle

--[[
Peripherals
--]]

local monitor
if monitorSide then
  monitor = peripheral.wrap(monitorSide)
else
  monitor = peripheral.find("monitor")
  if monitor then monitorSide = peripheral.getName(monitor) end
end
if not monitor then
  print("Error: no monitor attached")
  return
end
if not monitor.isColor() then
  print("Error: an advanced monitor is needed for touch")
  return
end
if not turtlectl.openModem() then
  print("Error: no modem attached")
  return
end
monitor.setTextScale(textScale)

--[[
Turtle records: id -> { id, label, state, job, message, fuel, lastSeen,
                        output = {}, command = "", lastMove }
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
    t = { id = id, label = "Turtle " .. id, state = "offline", output = {}, command = "" }
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
local showMain, showTurtle, showMove, showShell

local function setScreen(root, handlers)
  icons = {}
  screen = handlers
  app:setRootContainer(root)
  root:setStarted(true)
  root:repaint()
  if screen and screen.refresh then screen.refresh() end
end

local function newRoot(title, decorations)
  local root = guirootcontainer.GUIRootContainer.new(monitor, monitorSide)
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

local function fuelText(t)
  local fuel = t.fuel and tostring(t.fuel) or "?"
  if t.fuelLimit then fuel = fuel .. " / " .. t.fuelLimit end
  return fuel
end

local function sendStop(t)
  turtlectl.sendCommand(t.id, "stop")
  t.message = "stop sent..."
end

--[[
Main screen: a grid of turtle icons.
--]]

showMain = function()
  local root = newRoot("Turtle Control", true)
  local w, h = monitor.getSize()
  local tileW, tileH = guiturtleicon.GUITurtleIcon.MinWidth, guiturtleicon.GUITurtleIcon.MinHeight
  local gap = 1
  if w < tileW + 2 or h < tileH + 2 then
    tileW, tileH, gap = math.max(8, w - 2), 4, 0 -- compact tiles for small monitors
  end
  local columns = math.max(1, math.floor((w - gap) / (tileW + gap)))
  local list = sortedTurtles()
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
  local w, h = monitor.getSize()
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
      else
        turtlectl.sendCommand(id, job.id)
        t.state = "busy"
        t.job = job.id
        t.message = "sent " .. job.id .. "..."
      end
      screen.refresh()
    end })
  end
  table.insert(actions, { name = "Move", color = colors.green, fn = function() showMove(id) end })
  table.insert(actions, { name = "Shell", color = colors.purple, fn = function() showShell(id) end })
  table.insert(actions, { name = "Stop", color = colors.red, fn = function() sendStop(t); screen.refresh() end })
  table.insert(actions, { name = "Back", color = colors.gray, fn = function() showMain() end })

  local gap = 1
  local columns = (w >= 34) and 3 or 2
  local bw = math.floor((w - gap * (columns + 1)) / columns)
  local rows = math.ceil(#actions / columns)
  local bh = math.floor((h - top + 1 - (rows - 1) * gap) / rows)
  bh = math.max(1, math.min(3, bh))
  for i, action in ipairs(actions) do
    local col = (i - 1) % columns
    local row = math.floor((i - 1) / columns)
    local x = gap + 1 + col * (bw + gap)
    local y = top + row * (bh + gap)
    root:add(newButton(action.name, x, y, bw, bh, action.color, action.fn))
  end

  setScreen(root, {
    id = id,
    tick = function() if icon then icon:tick() end end,
    refresh = function()
      local t = turtles[id]
      if icon then icon:setInfo(t) end
      if lines.job then
        lines.state:setText("State: " .. (t.state or "?"))
        lines.job:setText("Job:   " .. (t.job or "-"))
        lines.fuel:setText("Fuel:  " .. fuelText(t))
        lines.message:setText(t.message or "")
      else
        lines.state:setText((t.state or "?") .. " " .. (t.job or ""))
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

showMove = function(id)
  local t = turtles[id]
  if not t then return showMain() end
  local root = newRoot(t.label)
  local w, h = monitor.getSize()
  addHeader(root, w, "Move " .. t.label, function() showTurtle(id) end)
  local status = newLabel("", 1, 2, w, colors.lightGray)
  root:add(status)

  local top, gap = 3, 1
  local cols, rows = 7, 3
  local bw = math.floor((w - gap * (cols - 1)) / cols)
  local bh = math.floor((h - top + 1 - gap * (rows - 1)) / rows)
  bh = math.max(1, math.min(4, bh))
  for i, key in ipairs(movePad) do
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
Shell screen: output pane, command line and an on screen keyboard.
--]]

-- Keyboard rows. A string is one key per character; a table entry is a
-- wider special key with its width in key units.
local keyboard = {
  { "1234567890-=" },
  { "qwertyuiop/" },
  { "asdfghjkl:" },
  { "zxcvbnm.," },
  { { name = "Shift", units = 2, key = "shift" }, { name = "Space", units = 5, key = " " },
    { name = "Bksp", units = 2, key = "bksp" }, { name = "Clear", units = 2, key = "clear" },
    { name = "Run", units = 2, key = "run" } },
}
local keyUnits = 13 -- widest row, in key units

showShell = function(id)
  local t = turtles[id]
  if not t then return showMain() end
  local root = newRoot(t.label)
  local w, h = monitor.getSize()
  addHeader(root, w, "Shell " .. t.label, function() showTurtle(id) end,
    function() sendStop(t); addOutput(t, "[stop sent]"); screen.refresh() end)

  local keyW = math.max(1, math.floor(w / keyUnits))
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

  local shift = false
  local letterKeys = {}
  local function press(key)
    if key == "shift" then
      shift = not shift
      for i, k in ipairs(letterKeys) do
        k.button:setText(shift and k.char:upper() or k.char)
      end
    elseif key == "bksp" then
      t.command = t.command:sub(1, -2)
    elseif key == "clear" then
      t.command = ""
    elseif key == "run" then
      if t.command ~= "" then
        addOutput(t, "> " .. t.command)
        turtlectl.sendShell(id, t.command, w)
        t.command = ""
      end
    else
      if shift then key = key:upper() end
      t.command = t.command .. key
    end
    screen.refresh()
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
        if entry.key == "run" then color = colors.green elseif entry.key == "clear" then color = colors.red end
        root:add(newButton(entry.name, x, y, keyW * entry.units, 1, color, function() press(entry.key) end))
        x = x + keyW * entry.units
      end
    end
  end

  t.lastStatusMessage = t.message -- only report status changes from now on
  setScreen(root, {
    id = id,
    refresh = function()
      local t = turtles[id]
      local first = math.max(1, #t.output - outRows + 1)
      for i = 1, outRows do
        outLines[i]:setText(t.output[first + i - 1] or "")
      end
      local text = "> " .. t.command .. "_"
      if #text > w then text = text:sub(-w) end
      cmdLine:setText(text)
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
  t.lastSeen = os.clock()
  if screen and screen.id == id then
    if screen.onStatus then screen.onStatus(msg) else screen.refresh() end
  elseif isNew and not screen.id then
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
    if screen.onAck then screen.onAck(msg) else screen.refresh() end
  end
end

local function onOutput(sender, msg)
  local t = turtles[sender]
  if not t then return end
  addOutput(t, tostring(msg.text))
  if screen and screen.id == sender and screen.onOutput then screen.onOutput() end
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
print("Turtle control on monitor " .. monitorSide .. ", close with the x on the monitor")
app:setUPS(20)
showMain()
app:start()
monitor.setBackgroundColor(colors.black)
monitor.clear()
