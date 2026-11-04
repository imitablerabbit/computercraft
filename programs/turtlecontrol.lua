--[[
Turtle control is a touch screen dashboard for the turtles running
turtleagent. It runs on a computer with a modem and an advanced monitor.
The main screen shows an icon per turtle that changes with what the
turtle is doing. Touching an icon opens that turtle's screen with the
jobs it can be told to run.

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
Turtle records: id -> { id, label, state, job, message, fuel, lastSeen }
--]]

local turtles = {}

local function sortedTurtles()
  local list = {}
  for id, t in pairs(turtles) do table.insert(list, t) end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

-- Seed the list from the registry so known turtles show as offline.
local function loadRegistry(file)
  if not fs.exists(file) then return end
  local reg = registry.new()
  reg:loadFile(file)
  for i, record in pairs(reg.records or {}) do
    local id, ctype, label = tonumber(record[1]), record[2], record[3]
    if id and ctype and ctype:find("turtle") then
      if label == "" then label = nil end
      turtles[id] = { id = id, label = label or ("Turtle " .. id), state = "offline" }
    end
  end
end

--[[
Screens
--]]

local app = guiapplication.GUIApplication.new()
local icons = {}        -- id -> GUITurtleIcon on the main screen
local detail = nil      -- state of the open turtle screen, if any
local showMain, showTurtle

local function setScreen(root)
  app:setRootContainer(root)
  root:setStarted(true)
  root:repaint()
end

local function newRoot(title)
  local root = guirootcontainer.GUIRootContainer.new(monitor, monitorSide)
  root:setTitle(title)
  root:setBackgroundColor(colors.black)
  root:setBorderColor(colors.gray)
  root:setTextColor(colors.white)
  return root
end

local function newLabel(text, x, y, w, color)
  local label = guitext.GUIText.new(text)
  label:setPreferredBounds(x, y, w, 1)
  label:setBorder(false)
  label:setBackgroundColor(colors.black)
  label:setTextColor(color or colors.white)
  return label
end

local function newButton(text, x, y, w, h, color)
  local button = guibutton.GUIButton.new(text)
  button:setPreferredBounds(x, y, w, h)
  button:setBackgroundColor(color or colors.blue)
  button.pressColor = colors.lightGray
  button:setTextColor(colors.white)
  button:setBorderColor(colors.gray)
  return button
end

-- Main screen: a grid of turtle icons.
showMain = function()
  icons = {}
  detail = nil
  local root = newRoot("Turtle Control")
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
      icons[t.id] = icon
    end
  end
  setScreen(root)
end

-- Turtle screen: status lines and job buttons.
showTurtle = function(id)
  local t = turtles[id]
  if not t then return showMain() end
  icons = {}
  detail = nil
  local root = newRoot(t.label .. " (#" .. id .. ")")
  root:setDecorations(false)
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
    local textW = math.max(1, w - textX)
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

  -- Job buttons in two columns under the header, then Stop and Back.
  local gap = 1
  local columns = 2
  local bw = math.floor((w - gap * (columns + 1)) / columns)
  local rows = math.ceil(#turtlectl.jobs / columns) + 1 -- jobs plus Stop/Back
  local bh = math.floor((h - top + 1 - (rows - 1) * gap) / rows)
  bh = math.max(1, math.min(3, bh))
  local buttons = {}
  for i, job in ipairs(turtlectl.jobs) do
    local col = (i - 1) % columns
    local row = math.floor((i - 1) / columns)
    local x = gap + 1 + col * (bw + gap)
    local y = top + row * (bh + gap)
    local button = newButton(job.name, x, y, bw, bh, colors.blue)
    button:setBorder(bh >= 3)
    button:addButtonListener(function()
      if t.state == "busy" then
        lines.message:setText("Busy, stop it first")
        return
      end
      turtlectl.sendCommand(id, job.id)
      t.state = "busy"
      t.job = job.id
      t.message = "sent " .. job.id .. "..."
      detail.refresh()
    end)
    root:add(button)
    table.insert(buttons, button)
  end
  local lastRow = math.floor((#turtlectl.jobs - 1) / columns) + 1
  local y = top + lastRow * (bh + gap)
  if y + bh - 1 > h then y = h - bh + 1 end
  local stop = newButton("Stop", gap + 1, y, bw, bh, colors.red)
  stop:setBorder(bh >= 3)
  stop:addButtonListener(function()
    turtlectl.sendCommand(id, "stop")
    t.message = "stop sent..."
    detail.refresh()
  end)
  local back = newButton("Back", gap * 2 + bw + 1, y, bw, bh, colors.gray)
  back:setBorder(bh >= 3)
  back:addButtonListener(function() showMain() end)
  root:add(stop)
  root:add(back)

  setScreen(root)
  detail = {
    id = id,
    icon = icon,
    tick = function() if icon then icon:tick() end end,
    refresh = function()
      local t = turtles[id]
      if icon then icon:setInfo(t) end
      local fuel = t.fuel and tostring(t.fuel) or "?"
      if t.fuelLimit then fuel = fuel .. " / " .. t.fuelLimit end
      if lines.job then
        lines.state:setText("State: " .. (t.state or "?"))
        lines.job:setText("Job:   " .. (t.job or "-"))
        lines.fuel:setText("Fuel:  " .. fuel)
        lines.message:setText(t.message or "")
      else
        lines.state:setText((t.state or "?") .. " " .. (t.job or ""))
        lines.fuel:setText("Fuel: " .. fuel)
      end
    end,
  }
  detail.refresh()
end

--[[
Network and timers
--]]

local function onStatus(msg)
  local id = msg.id
  local isNew = turtles[id] == nil
  local t = turtles[id] or { id = id }
  turtles[id] = t
  t.label = msg.label or t.label or ("Turtle " .. id)
  t.state = msg.state or "idle"
  t.job = msg.job
  t.message = msg.message
  t.fuel = msg.fuel
  t.fuelLimit = msg.fuelLimit
  t.lastSeen = os.clock()
  if detail and detail.id == id then
    detail.refresh()
  elseif isNew and not detail then
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
    if msg.job ~= "stop" then
      t.state = "idle"
      t.job = nil
    end
  end
  if detail and detail.id == sender then detail.refresh() end
end

local function markOffline()
  local now = os.clock()
  for id, t in pairs(turtles) do
    if t.state ~= "offline" and t.lastSeen and now - t.lastSeen > offlineAfter then
      t.state = "offline"
      t.job = nil
      if icons[id] then icons[id]:setInfo(t) end
      if detail and detail.id == id then detail.refresh() end
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
      end
    end
  elseif event[1] == "timer" then
    if event[2] == discoverTimer then
      turtlectl.broadcastDiscover()
      markOffline()
      discoverTimer = os.startTimer(discoverEvery)
    elseif event[2] == animateTimer then
      for id, icon in pairs(icons) do icon:tick() end
      if detail then detail.tick() end
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
