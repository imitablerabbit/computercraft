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
  turtle  state, a fuel bar (red when low), a progress bar while the
          job reports how far along it is, a fuel history chart on
          wide screens, and buttons for the jobs in turtlectl and Stop.
          On wide screens Items, Move, Shell and Fuel are tabs along
          the top; on compact ones (a pocket computer) they are buttons
          that open screens of their own
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
  map     a top-down view (x east, z south, north up) of the turtles
          that report a calibrated position (see nav), an arrow each in
          the colour of their state, plus the depot's chests and the
          dispatcher's job sites when they are heard on the bus; touch
          a turtle to open it, touch elsewhere to centre there, and
          pan, zoom and Fit with the buttons. Map is on the main
          screen's title bar

Stop, Drop and removing a fuel rule ask for confirmation first.

Turtles are found by their status broadcasts. If a registry file from
registrylistener exists its turtles are shown as offline until heard from.

Usage: turtlecontrol [monitorSide|term] [textScale] [registryFile]
  monitorSide  the monitor to use (default: the first one found, or
               the computer's own screen when there is none); "term"
               forces the computer's own screen
  textScale    the monitor's text scale (default: the largest that
               still gives 50x20 characters, 0.5 on small monitors)
--]]

local args = {...}
local monitorSide = args[1]
local textScale = tonumber(args[2]) -- nil: picked from the monitor size
local registryFile = args[3] or "registry_store.dat"

local discoverEvery = 10 -- seconds between discover broadcasts
local offlineAfter = 20  -- seconds without a status before a turtle is offline
local animateEvery = 0.5 -- seconds between busy animation frames
local maxOutput = 100    -- shell output lines kept per turtle
local inventoryEvery = 3 -- seconds between inventory requests while on the items screen
local fuelFull = 2000    -- fuel the fuel bar shows as full (the number shows the rest)
local fuelLow = 200      -- below this the fuel bar turns red
local fuelSamples = 60   -- fuel levels kept per turtle for the history chart

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
  guitheme.fit(monitor, 50, 20, textScale)
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
                        fuelBlacklist (list of item names, nil until asked),
                        progress ({ done, total, text } while the job
                        reports it), fuelHistory (recent fuel levels) }
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
local showInventory, showItemDetail, showDiscover, showFuelRules, openTab, showMap

-- What the map shows besides turtles, from the bus: the depot's chests
-- (depot.chests) and the dispatcher's queue (fleet.queue).
local depotChests = {}
local fleetSites = {}

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

-- Wide screens show a turtle's screens as tabs; compact ones (a pocket
-- computer, a small monitor) as separate screens.
local function isTabbed()
  local w, h = display.getSize()
  return not guitheme.isCompact(w, h)
end

-- A one row bar, for fuel and job progress.
local function newBar(x, y, w)
  local bar = guiprogressbar.GUIProgressBar.new(0, 1)
  bar:setPreferredBounds(x, y, math.max(1, w), 1)
  bar:setBackgroundColor(colors.black)
  bar:setFillColor(colors.green)
  bar:setEmptyColor(colors.gray)
  bar:setWarnColor(colors.red)
  bar:setTextColor(colors.white)
  return bar
end

-- Ask before doing something that cannot be undone; yes names the
-- action and is drawn red.
local function confirm(parent, title, message, yes, onYes)
  guidialog.confirm(parent, title, message, onYes, nil, { yes = yes, no = "Cancel", danger = true })
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

-- The fuel bar: fuelFull or more fills it, below fuelLow it is red,
-- and the label has the real numbers.
local function showFuel(bar, t)
  local fuel = tonumber(t.fuel)
  if t.fuel == "unlimited" then
    bar.warnBelow = nil
    bar:setProgress(1, 1, "unlimited")
    return
  end
  local full = math.max(1, math.min(tonumber(t.fuelLimit) or fuelFull, fuelFull))
  bar.warnBelow = fuel and fuelLow or nil
  bar:setProgress(fuel or 0, full, fuelText(t))
end

-- "12/64 layer 1 of 2" from a progress report.
local function progressText(p)
  local parts = {}
  if p.done and p.total then parts[#parts + 1] = p.done .. "/" .. p.total
  elseif p.done then parts[#parts + 1] = tostring(p.done) end
  if p.text then parts[#parts + 1] = tostring(p.text) end
  return table.concat(parts, " ")
end

-- The job progress bar, shown only while the turtle reports progress;
-- blank (under it) shows otherwise.
local function showProgress(bar, blank, t)
  local p = t.progress
  if type(p) == "table" and t.state == "busy" then
    local total = tonumber(p.total)
    bar.visible = true
    if total and total > 0 then
      bar:setProgress(math.min(tonumber(p.done) or 0, total), total, progressText(p))
    else
      bar:setProgress(0, 1, progressText(p))
    end
  else
    bar:setVisible(false)
    blank:repaint()
  end
end

local function sendStop(t)
  turtlectl.sendCommand(t.id, "stop")
  t.message = "stop sent..."
end

-- Stop the turtle's job, asking first when it is running one. after is
-- called once the stop is sent.
local function stopTurtle(parent, t, after)
  if t.state ~= "busy" then
    sendStop(t)
    if after then after() end
    return
  end
  confirm(parent, "Stop " .. t.label,
    "Stop " .. tostring(t.job or "the job") .. " on " .. t.label .. "? The turtle stays where it is.", "Stop",
    function()
      sendStop(t)
      if after then after() end
    end)
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
  root:add(newButton("Map", w - 5, 1, 4, 1, colors.blue, function() showMap() end))
  setScreen(root, {
    isMain = true,
    tick = function() for id, icon in pairs(tiles) do icon:tick() end end,
  })
  icons = tiles
end

--[[
Map screen: a top-down view of the turtles, the depot's chests and the
dispatcher's job sites. Positions are the Minecraft coordinates the
agents report (nav), so turtles that never calibrated are left out.
The view (centre and blocks per character) is kept between visits;
nil fits everything in.
--]]

local mapView = nil
local stateColors = { idle = colors.lime, busy = colors.orange, error = colors.red, offline = colors.gray }
local chestMarks = {
  fuel = { "F", colors.orange }, dump = { "D", colors.brown }, materials = { "M", colors.cyan },
}

-- Everything to draw, as { x, z, char, color, turtle, label }, turtles last.
local function mapMarks()
  local marks = {}
  for _, s in ipairs(fleetSites) do
    local running = s.state ~= "queued"
    table.insert(marks, { x = s.site.x, z = s.site.z, char = running and "#" or "x",
      color = running and colors.orange or colors.yellow })
  end
  for _, c in ipairs(depotChests) do
    local m = chestMarks[c.role] or { "C", colors.white }
    table.insert(marks, { x = c.x, z = c.z, char = m[1], color = m[2] })
  end
  for _, t in ipairs(sortedTurtles()) do
    local p = t.pos
    if p and p.calibrated and tonumber(p.x) and tonumber(p.z) then
      local color = stateColors[t.state] or colors.white
      if alertText(t) then color = colors.red end
      table.insert(marks, { x = p.x, z = p.z, char = fleet.headingArrow(p.heading), color = color, turtle = t.id, label = t.label })
    end
  end
  return marks
end

-- The map itself: a component that draws the marks and reports
-- touches as onTurtle(id) or onPlace(x, z).
local function newMapView(x, y, w, h, onTurtle, onPlace)
  local map = guicomponent.GUIComponent.new()
  map:setPreferredBounds(x, y, w, h)
  map:setBorder(false)
  map:setBackgroundColor(colors.black)
  map.cells = {} -- "col,row" -> turtle id drawn there
  map.ui = { paint = function()
    if not map.term then return end
    local old = term.redirect(map.term)
    local mw, mh = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()
    local marks = mapMarks()
    local view = mapView
    if not view then
      local points = {}
      for i, m in ipairs(marks) do points[i] = { x = m.x, z = m.z } end
      view = fleet.fitView(points, mw, mh)
    end
    map.view = view
    -- Chunk borders every 16 blocks, faintly, when they are far enough apart.
    if view.scale <= 4 then
      for col = 1, mw do
        for row = 1, mh do
          local wx, wz = fleet.unproject(view, mw, mh, col, row)
          if wx % 16 < view.scale and wz % 16 < view.scale then
            term.setCursorPos(col, row)
            term.setTextColor(colors.gray)
            term.write("+")
          end
        end
      end
    end
    if #marks == 0 then
      -- Nothing placed yet: say why rather than show an empty map.
      local lines = { "No positions yet:", "turtles report them", "once gps has located", "them (see nav)" }
      for i, text in ipairs(lines) do
        term.setCursorPos(math.max(1, math.floor((mw - #text) / 2) + 1), math.floor(mh / 2) - 2 + i)
        term.setTextColor(colors.lightGray)
        term.write(text)
      end
    end
    map.cells = {}
    local taken = {}
    for _, m in ipairs(marks) do
      local col, row = fleet.project(view, mw, mh, m.x, m.z)
      if col then
        term.setCursorPos(col, row)
        term.setTextColor(m.color)
        term.write(m.char)
        taken[col .. "," .. row] = true
        if m.turtle then map.cells[col .. "," .. row] = m.turtle end
      end
    end
    -- Turtle names beside their arrows where there is room.
    for _, m in ipairs(marks) do
      local col, row = fleet.project(view, mw, mh, m.x, m.z)
      if col and m.label and mw >= 30 then
        local text = m.label:sub(1, math.max(0, mw - col - 1))
        local free = true
        for i = 1, #text do free = free and not taken[(col + i) .. "," .. row] end
        if free and #text > 0 then
          term.setCursorPos(col + 1, row)
          term.setTextColor(colors.lightGray)
          term.write(text)
          for i = 1, #text do map.cells[(col + i) .. "," .. row] = m.turtle end
        end
      end
    end
    term.redirect(old)
  end }
  local function touched(e)
    if e.x < map.ax or e.x >= map.ax + map.w or e.y < map.ay or e.y >= map.ay + map.h then return end
    local col, row = e.x - map.ax + 1, e.y - map.ay + 1
    -- a turtle on the cell, or right next to it (fingers are wide)
    for _, d in ipairs({ { 0, 0 }, { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
      local id = map.cells[(col + d[1]) .. "," .. (row + d[2])]
      if id then return onTurtle(id) end
    end
    if map.view then onPlace(fleet.unproject(map.view, map.w, map.h, col, row)) end
  end
  map:addMouseClickListener(touched)
  map:addMonitorTouchListener(touched)
  return map
end

showMap = function()
  local root = newRoot("Fleet map")
  local w, h = display.getSize()
  local wide = w >= 40
  local title = newLabel("", 1, 1, w - 7, colors.yellow)
  root:add(title)
  root:add(newButton("Back", w - 5, 1, 6, 1, colors.gray, function() showMain() end))
  local legendRows = wide and 1 or 0
  local map
  local function redraw()
    map:repaint()
    local placed, total = 0, 0
    for _, t in pairs(turtles) do
      total = total + 1
      if t.pos and t.pos.calibrated then placed = placed + 1 end
    end
    local scale = map.view and map.view.scale or 1
    local text = "Map 1:" .. scale .. (wide and (" (" .. placed .. " of " .. total .. " turtles placed)") or "")
    if map.view and wide then text = text .. " " .. map.view.cx .. "," .. map.view.cz end
    title:setText(text)
  end
  map = newMapView(1, 2, w, h - 2 - legendRows, function(id) showTurtle(id) end, function(x, z)
    local v = map.view
    mapView = { cx = x, cz = z, scale = v.scale }
    redraw()
  end)
  root:add(map)
  if wide then
    root:add(newLabel("^>v< turtle  F fuel  D dump  M materials  x site", 1, h - 1, w, colors.gray))
  end
  local function current() return mapView or map.view or { cx = 0, cz = 0, scale = 1 } end
  local function pan(dx, dz)
    local v = current()
    local step = math.max(1, math.floor(math.min(map.w, map.h) / 3)) * v.scale
    mapView = { cx = v.cx + dx * step, cz = v.cz + dz * step, scale = v.scale }
    redraw()
  end
  local buttons = {
    { "<", function() pan(-1, 0) end }, { ">", function() pan(1, 0) end },
    { "^", function() pan(0, -1) end }, { "v", function() pan(0, 1) end },
    { "+", function() mapView = fleet.zoom(current(), 0.5) redraw() end },
    { "-", function() mapView = fleet.zoom(current(), 2) redraw() end },
    { "Fit", function() mapView = nil redraw() end },
  }
  local gap = (w >= #buttons * 4) and 1 or 0
  local bw = math.floor((w - (#buttons - 1) * gap) / #buttons)
  for i, b in ipairs(buttons) do
    local color = (gap == 0 and i % 2 == 0) and colors.cyan or colors.blue
    if b[1] == "Fit" then color = colors.green end
    root:add(newButton(b[1], 1 + (i - 1) * (bw + gap), h, bw, 1, color, b[2]))
  end
  setScreen(root, { isMap = true, refresh = redraw })
end

--[[
Turtle screen. Its top part shows the turtle's state, fuel and job
progress; under it are the job buttons. On wide screens the turtle's
screens are tabs (Jobs, Items, Move, Shell, Fuel) with Back at the
right of the tab row; on compact screens Items, Fuel, Move, Shell and
Back are more buttons and each opens a screen of its own.
--]]

-- The status part at the top of a turtle screen in parent, from row
-- top: the icon with lines beside it, or text lines alone when there
-- is no room for the icon. wide adds a fuel history chart. Returns the
-- first free row and a table with refresh(t) and tick().
local function addTurtleStatus(parent, t, w, h, top, wide)
  local iconW, iconH = guiturtleicon.GUITurtleIcon.MinWidth, guiturtleicon.GUITurtleIcon.MinHeight
  local s = {}
  local nextRow, barX, barY, barW
  if w >= iconW * 2 and h - top + 1 >= iconH + 4 then
    s.icon = guiturtleicon.GUITurtleIcon.new(t)
    s.icon:setPreferredBounds(1, top, iconW, iconH)
    s.icon:setBorder(false)
    parent:add(s.icon)
    local textX = iconW + 1
    local textW = w - textX
    s.title = newLabel(t.label .. " (#" .. t.id .. ")", textX, top + 1, textW, colors.yellow)
    s.state = newLabel("", textX, top + 2, textW)
    s.job = newLabel("", textX, top + 3, textW)
    s.fuel = newBar(textX, top + 4, textW)
    s.message = newLabel("", textX, top + 5, textW, colors.lightGray)
    barX, barY, barW = textX, top + 6, textW
    if wide and textW >= 12 then
      s.history = guisparkline.GUISparkline.new(fuelSamples)
      s.history:setPreferredBounds(textX, top + 7, textW, 2)
      s.history:setBackgroundColor(colors.black)
      s.history:setEmptyColor(colors.black)
      s.history:setFillColor(colors.green)
      s.history:setTextColor(colors.gray)
      s.history:setShowRange(true)
    end
    nextRow = top + iconH
  else
    s.title = newLabel(t.label .. " (#" .. t.id .. ")", 1, top, w, colors.yellow)
    s.state = newLabel("", 1, top + 1, w)
    s.fuel = newBar(1, top + 2, w)
    barX, barY, barW = 1, top + 3, w
    nextRow = top + 4
  end
  s.progressBlank = newLabel("", barX, barY, barW)
  s.progress = newBar(barX, barY, barW)
  s.progress:setFillColor(colors.cyan)
  for _, k in ipairs({ "title", "state", "job", "fuel", "message", "progressBlank", "progress", "history" }) do
    if s[k] then parent:add(s[k]) end
  end

  function s.refresh(t)
    if s.icon then s.icon:setInfo(t) end
    local help = alertText(t)
    if s.job then
      s.state:setText("State: " .. (t.state or "?") .. (help and ", needs help" or ""))
      s.job:setText("Job:   " .. (t.job or "-"))
      s.message:setTextColor(help and colors.red or colors.lightGray)
      s.message:setText(help and ("NEEDS HELP: " .. help) or (t.message or ""))
    else
      s.state:setTextColor(help and colors.red or colors.white)
      s.state:setText(help and ("HELP: " .. help) or ((t.state or "?") .. " " .. (t.job or "")))
    end
    showFuel(s.fuel, t)
    showProgress(s.progress, s.progressBlank, t)
    if s.history then s.history:setSamples(t.fuelHistory or {}) end
  end
  function s.tick()
    if s.icon then s.icon:tick() end
  end
  return nextRow, s
end

-- Buttons for actions ({ name, color, fn }) from row top to the bottom,
-- three to a row on wider screens.
local function addActionButtons(parent, actions, w, h, top)
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
    parent:add(newButton(action.name, x, y, bw, bh, action.color, action.fn))
  end
end

-- One button per job in the catalogue, then Stop.
local function jobActions(parent, id)
  local t = turtles[id]
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
  return actions, { name = "Stop", color = colors.red, fn = function()
    stopTurtle(parent, t, function() if screen.refresh then screen.refresh() end end)
  end }
end

-- The Jobs part of a turtle screen: status and job buttons. nav adds
-- the buttons that open the other screens (compact screens).
local function buildJobs(parent, id, w, h, top, nav)
  local t = turtles[id]
  local nextRow, status = addTurtleStatus(parent, t, w, h, top, not nav)
  local actions, stop = jobActions(parent, id)
  if nav then
    table.insert(actions, { name = "Items", color = colors.orange, fn = function() showInventory(id) end })
    table.insert(actions, { name = "Fuel", color = colors.brown, fn = function() showFuelRules(id) end })
    table.insert(actions, { name = "Move", color = colors.green, fn = function() showMove(id) end })
    table.insert(actions, { name = "Shell", color = colors.purple, fn = function() showShell(id) end })
    table.insert(actions, stop)
    table.insert(actions, { name = "Back", color = colors.gray, fn = function() showMain() end })
  else
    table.insert(actions, stop)
  end
  addActionButtons(parent, actions, w, h, nextRow)
  return {
    tick = status.tick,
    refresh = function() status.refresh(turtles[id]) end,
  }
end

-- Builders for the parts of a turtle screen that are tabs on wide
-- screens: builder(parent, id, w, h, top) fills rows top..h of parent
-- and returns the screen handlers (refresh, tick, onAck ...).
local tabBuilders = {}
local tabNames = { "Jobs", "Items", "Move", "Shell", "Fuel" }

showTurtle = function(id, tabName)
  local t = turtles[id]
  if not t then return showMain() end
  local root = newRoot(t.label)
  local w, h = display.getSize()
  if not isTabbed() then
    local handlers = buildJobs(root, id, w, h, 1, true)
    handlers.id = id
    return setScreen(root, handlers)
  end

  -- Tabs along the top with Back at the right end. Each tab is built
  -- afresh in its own container whenever it is selected.
  local tabs = guitabs.GUITabs.new()
  tabs:setPreferredBounds(1, 1, w, h)
  tabs:setStripReserve(7)
  root:add(tabs)
  -- a child of the tabs so it is drawn again after the tab row
  tabs:add(newButton("Back", w - 5, 1, 6, 1, colors.gray, function() showMain() end))
  for i, name in ipairs(tabNames) do
    local panel = guicomponent.GUIComponent.new()
    panel:setBackgroundColor(colors.black)
    panel:setBorder(false)
    panel:setPreferredBounds(1, 2, w, h - 1)
    tabs:addTab(name, panel)
  end
  tabs:addChangeListener(function(e)
    local panel = e.component
    panel:removeAll()
    -- a fresh body each time, so key listeners of the last one go too
    local body = guicomponent.GUIComponent.new()
    body:setBackgroundColor(colors.black)
    body:setBorder(false)
    body:setPreferredBounds(1, 1, w, h - 1)
    panel:add(body)
    local handlers = tabBuilders[e.title](body, id, w, h - 1, 1) or {}
    handlers.id = id
    handlers.tabs = tabs
    handlers.tab = e.title
    screen = handlers
    panel:repaint()
    if screen.refresh then screen.refresh() end
  end)
  setScreen(root, { id = id })
  tabs:select(tabs:indexOf(tabName or "Jobs") or 1, true)
end

-- Show one of a turtle's tabs: switch to it when its tabbed screen is
-- open (building it again), otherwise open the screen on that tab.
openTab = function(id, name)
  if screen and screen.tabs and screen.id == id then
    screen.tabs:select(screen.tabs:indexOf(name), true)
  else
    showTurtle(id, name)
  end
end

tabBuilders.Jobs = function(parent, id, w, h, top)
  return buildJobs(parent, id, w, h, top, false)
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

-- The move pad in parent from row top (a status line, then the pad).
local function buildMove(parent, id, w, h, top)
  local t = turtles[id]
  local status = newLabel("", 1, top, w, colors.lightGray)
  parent:add(status)

  local padTop, gap = top + 1, 1
  local pad, cols, rows = movePad, 7, 3
  if w < 7 * 4 + 6 then pad, cols, rows = movePadNarrow, 4, 4 end
  local bw = math.floor((w - gap * (cols - 1)) / cols)
  local bh = math.floor((h - padTop + 1 - gap * (rows - 1)) / rows)
  bh = math.max(1, math.min(4, bh))
  for i, key in ipairs(pad) do
    local x = 1 + (key.col - 1) * (bw + gap)
    local y = padTop + (key.row - 1) * (bh + gap)
    local color = colors.blue
    if key.action:find("dig") then color = colors.brown
    elseif key.action:find("place") or key.action == "suck" or key.action == "drop" then color = colors.cyan end
    parent:add(newButton(key.name, x, y, bw, bh, color, function()
      if t.state == "busy" then
        t.lastMove = "busy with " .. tostring(t.job) .. ", stop it first"
      else
        turtlectl.sendMove(id, key.action)
        t.lastMove = key.action .. "..."
      end
      screen.refresh()
    end))
  end

  return {
    refresh = function()
      local t = turtles[id]
      status:setText("Fuel " .. fuelText(t) .. "  " .. (t.lastMove or "touch a button"))
    end,
    onAck = function(msg)
      t.lastMove = msg.job .. ": " .. (msg.message or (msg.ok and "ok" or "failed"))
      screen.refresh()
    end,
  }
end
tabBuilders.Move = buildMove

showMove = function(id)
  if isTabbed() then return openTab(id, "Move") end
  local t = turtles[id]
  if not t then return showMain() end
  local root = newRoot(t.label)
  local w, h = display.getSize()
  addHeader(root, w, "Move " .. t.label, function() showTurtle(id) end)
  local handlers = buildMove(root, id, w, h, 2)
  handlers.id = id
  setScreen(root, handlers)
end

--[[
Items screen: the turtle's inventory grid, polled while open.
--]]

-- The inventory grid in parent from row top, asked for again every
-- few seconds while it shows.
local function buildInventory(parent, id, w, h, top)
  local t = turtles[id]
  local status = newLabel("", 1, top, w, colors.lightGray)
  parent:add(status)
  local grid = guiinventorygrid.GUIInventoryGrid.new(t.inventory, t.selected)
  grid:setPreferredBounds(1, top + 1, w, h - top)
  grid:addSelectListener(function(e)
    if e.item then showItemDetail(id, e.slot) end
  end)
  parent:add(grid)

  turtlectl.requestInventory(id)
  t.inventoryMessage = t.inventory and "" or "asking the turtle..."
  local ticks = 0
  return {
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
  }
end
tabBuilders.Items = buildInventory

showInventory = function(id)
  if isTabbed() then return openTab(id, "Items") end
  local t = turtles[id]
  if not t then return showMain() end
  local root = newRoot(t.label)
  local w, h = display.getSize()
  addHeader(root, w, "Items " .. t.label, function() showTurtle(id) end)
  local handlers = buildInventory(root, id, w, h, 2)
  handlers.id = id
  setScreen(root, handlers)
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
  local drop = act("drop")
  root:add(newButton("Drop", bx + (bw + 1) * 3, by, bw, bh, colors.red, function()
    if t.state == "busy" then return drop() end -- refused anyway, no need to ask
    confirm(root, "Drop", "Drop " .. tostring(item.count or "the") .. " " .. turtleinv.shortName(item) .. " from slot " .. slot .. " in front of " .. t.label .. "?", "Drop", drop)
  end))

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

  -- The rows come from apis/jobform.lua; text values open the on
  -- screen keyboard and Discover... the turtle's items.
  local function back() showJobForm(id, job) end
  local startY, startH = jobform.add(root, job, values, {
    top = 3, w = w, h = h,
    onText = function(param)
      showTextInput(param.label, tostring(values[param.name] or ""), function(text)
        values[param.name] = text
        back()
      end, back)
    end,
    onDiscover = function(param)
      showDiscover(id, param, function(name)
        values[param.name] = name
        back()
      end, back)
    end,
  })
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

-- The fuel rules in parent from row top: a status line, the list with
-- Remove buttons (each asks first) and the two Add buttons at the bottom.
local function buildFuelRules(parent, id, w, h, top)
  local t = turtles[id]
  local status = newLabel("", 1, top, w, colors.lightGray)
  parent:add(status)
  parent:add(newLabel("Never burnt as fuel:", 1, top + 1, w, colors.yellow))

  local bh = (h >= 16) and 3 or 1
  local by = h - bh + 1
  local lastRow = by - 2
  local list = t.fuelBlacklist
  if not list then
    parent:add(newLabel("asking the turtle...", 2, top + 2, w - 2, colors.lightGray))
  elseif #list == 0 then
    parent:add(newLabel("nothing, every fuel item may be burnt", 2, top + 2, w - 2, colors.lightGray))
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
        confirm(parent, "Remove fuel rule", "Let " .. t.label .. " burn " .. tostring(name) .. " as fuel again?", "Remove", function()
          turtlectl.sendFuelRules(id, "remove", name)
          t.fuelMessage = "removing " .. tostring(name) .. "..."
          screen.refresh()
        end)
      end))
      rows:add(row)
    end
    local pane = guiscrollpane.GUIScrollPane.new()
    pane:setPreferredBounds(2, top + 2, w - 2, math.max(1, lastRow - top - 1))
    pane:setContent(rows)
    parent:add(pane)
  end

  local bw = math.floor((w - 3) / 2)
  local compact = guitheme.isCompact(w)
  parent:add(newButton(compact and "Carried..." or "Add carried item", 2, by, bw, bh, colors.green, function()
    showDiscover(id, { label = "Never burn" }, function(name)
      turtlectl.sendFuelRules(id, "add", name)
      t.fuelMessage = "adding " .. name .. "..."
      showFuelRules(id)
    end, function() showFuelRules(id) end)
  end))
  parent:add(newButton(compact and "By name..." or "Add by name", 3 + bw, by, bw, bh, colors.purple, function()
    showTextInput("Never burn", "", function(text)
      if text ~= "" then
        turtlectl.sendFuelRules(id, "add", text)
        t.fuelMessage = "adding " .. text .. "..."
      end
      showFuelRules(id)
    end, function() showFuelRules(id) end)
  end))

  if not list then turtlectl.sendFuelRules(id, "get") end
  return {
    refresh = function() status:setText(t.fuelMessage or "") end,
    onAck = function(msg)
      if msg.job == "fuel" then t.fuelMessage = msg.message or (msg.ok and "ok" or "refused") end
      screen.refresh()
    end,
    onFuelList = function() showFuelRules(id) end,
  }
end
tabBuilders.Fuel = buildFuelRules

showFuelRules = function(id)
  if isTabbed() then return openTab(id, "Fuel") end
  local t = turtles[id]
  if not t then return showMain() end
  local root = newRoot(t.label)
  local w, h = display.getSize()
  addHeader(root, w, "Fuel rules " .. t.label, function() showTurtle(id) end)
  local handlers = buildFuelRules(root, id, w, h, 2)
  handlers.id = id
  setScreen(root, handlers)
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

-- The shell in parent from row top: output lines, the command line
-- and the keyboard. stop adds a Stop button at the end of the command
-- line (the separate screen has one in its header instead).
local function buildShell(parent, id, w, h, top, stop)
  local t = turtles[id]
  local keyTop = h - #keyboard + 1
  local cmdRow = keyTop - 1
  local outRows = cmdRow - top -- rows top .. cmdRow-1 show output
  local outLines = {}
  for i = 1, outRows do
    local label = newLabel("", 1, top + i - 1, w)
    parent:add(label)
    outLines[i] = label
  end
  local cmdW = stop and (w - 7) or w
  local cmdLine = newLabel("", 1, cmdRow, cmdW, colors.yellow)
  parent:add(cmdLine)
  if stop then
    parent:add(newButton("Stop", w - 5, cmdRow, 6, 1, colors.red, function()
      stopTurtle(parent, t, function() addOutput(t, "[stop sent]"); screen.refresh() end)
    end))
  end

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
  addKeyboard(parent, w, keyTop, onKey, "Run")
  hookKeys(parent, onKey)

  t.lastStatusMessage = t.message -- only report status changes from now on
  return {
    refresh = function()
      local t = turtles[id]
      local first = math.max(1, #t.output - outRows + 1)
      for i = 1, outRows do
        outLines[i]:setText(t.output[first + i - 1] or "")
      end
      cmdLine:setText(t.editor.render("> ", cmdW))
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
  }
end
tabBuilders.Shell = function(parent, id, w, h, top)
  return buildShell(parent, id, w, h, top, true)
end

showShell = function(id)
  if isTabbed() then return openTab(id, "Shell") end
  local t = turtles[id]
  if not t then return showMain() end
  local root = newRoot(t.label)
  local w, h = display.getSize()
  addHeader(root, w, "Shell " .. t.label, function() showTurtle(id) end,
    function() stopTurtle(root, t, function() addOutput(t, "[stop sent]"); screen.refresh() end) end)
  local handlers = buildShell(root, id, w, h, 2, false)
  handlers.id = id
  setScreen(root, handlers)
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
  -- Older agents send no progress; that reads as none.
  t.progress = type(msg.progress) == "table" and msg.progress or nil
  -- Where nav says the turtle is (agents from before positions send none).
  t.pos = type(msg.pos) == "table" and msg.pos or nil
  if tonumber(msg.fuel) then
    t.fuelHistory = t.fuelHistory or {}
    table.insert(t.fuelHistory, tonumber(msg.fuel))
    while #t.fuelHistory > fuelSamples do table.remove(t.fuelHistory, 1) end
  end
  t.lastSeen = os.clock()
  if screen and screen.id == id then
    if screen.onStatus then screen.onStatus(msg) elseif screen.refresh then screen.refresh() end
  elseif screen and screen.isMap then
    screen.refresh()
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
    -- The depot's chests and the dispatcher's sites, for the map.
    if bus and bus.handle then
      local topic, payload = bus.handle(table.unpack(event, 1, event.n))
      if topic == "depot.chests" and type(payload) == "table" and type(payload.chests) == "table" then
        depotChests = payload.chests
        if screen and screen.isMap then screen.refresh() end
      elseif topic == "fleet.queue" and type(payload) == "table" and type(payload.entries) == "table" then
        fleetSites = {}
        for _, e in ipairs(payload.entries) do
          local active = e.state == "queued" or e.state == "moving" or e.state == "running"
          if active and type(e.site) == "table" then table.insert(fleetSites, e) end
        end
        if screen and screen.isMap then screen.refresh() end
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
if bus and bus.subscribe then
  -- Ask the depot and the dispatcher for what the map shows; they also
  -- send it now and then by themselves.
  bus.subscribe("depot.chests")
  bus.subscribe("fleet.queue")
  pcall(bus.publish, "depot.list", {})
  pcall(bus.publish, "fleet.list", {})
end
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
