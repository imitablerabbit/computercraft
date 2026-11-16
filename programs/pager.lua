--[[
Pager shows everything in the base that needs a person, on an advanced
pocket computer with a wireless modem (it works on any computer's own
screen too). It listens on the bus (apis/bus.lua) for alerts from
turtles and base computers and for turtle statuses.

The Alerts tab lists the active alerts newest first with their source,
kind, message and age. When a new one comes in the title bar and the
bottom line flash and, if the pocket computer has a speaker upgrade
(or a speaker is attached), it plays a few notes. Touch an alert for
the whole message and an Acknowledge button, which silences it on this
pager: it turns grey and does not flash again until it clears or its
message changes. Acknowledgements are kept in pager_acks.dat, so they
survive a restart.

The Turtles tab lists every turtle heard with its state, a fuel bar and
the job's progress, as a small fleet view.

A turtle not heard from for 30 seconds is greyed out, with its alerts.
Turtles send their status every 5 seconds, so a grey turtle is out of
range, off or broken. Computers that only send alerts say nothing in
between, so they are never greyed.

Usage: pager
--]]

local args = {...}
if #args > 0 then
  print("Usage: pager")
  return
end

local AckFile = "pager_acks.dat"
local StaleSeconds = 30
local FuelFull = 2000 -- a full fuel bar, as on the turtle control screen
local FuelLow = 200
local FlashTimes = 8 -- half second steps of flashing for a new alert

if not bus.open() then
  print("Error: no modem attached. The pager needs a wireless modem.")
  return
end

--[[
State
--]]

local sources = {} -- id -> { id, label, heard, periodic }
local turtles = {} -- id -> latest turtle.status payload
local alerts = {}  -- key -> { key, id, source, kind, message, since }
local acks = {}    -- key -> message acknowledged (saved in AckFile)

local function now() return os.clock() end
local function alertKey(id, kind) return tostring(id) .. ":" .. tostring(kind) end

local function loadAcks()
  if not fs.exists(AckFile) then return end
  local h = fs.open(AckFile, "r")
  if not h then return end
  local data = textutils.unserialize(h.readAll() or "")
  h.close()
  if type(data) == "table" then
    for key, message in pairs(data) do
      if type(key) == "string" and type(message) == "string" then acks[key] = message end
    end
  end
end

local function saveAcks()
  local h = fs.open(AckFile, "w")
  if not h then return end
  h.write(textutils.serialize(acks))
  h.close()
end

local function isAcked(a)
  return acks[a.key] ~= nil and acks[a.key] == a.message
end

-- A source is stale when it sends a regular status (turtles do) and
-- has not been heard for StaleSeconds.
local function isStale(id)
  local s = sources[id]
  return s ~= nil and s.periodic and now() - s.heard > StaleSeconds
end

local function ageText(seconds)
  seconds = math.max(0, math.floor(seconds))
  if seconds < 60 then return seconds .. "s" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
  return math.floor(seconds / 3600) .. "h"
end

local function sourceName(id)
  local s = sources[id]
  return (s and s.label) or ("#" .. tostring(id))
end

--[[
Screen
--]]

local w, h = term.getSize()
local compact = guitheme.isCompact(w, h)
local previousTheme = guitheme.isChosen() and guitheme.getTheme() or nil
guitheme.setTheme("dark")

local app = guiapplication.GUIApplication.new()
local root, ids
local turtleRows = {} -- id -> { name, fuel, job } components
local flashLeft, flashTimer = 0, nil
local flashText = nil

local columns
if compact then
  columns = { { title = "From", width = 7 }, { title = "Kind", width = 5 },
              { title = "Message", flex = 1 }, { title = "Age", width = 3, align = "right" } }
else
  columns = { { title = "Source", width = 12 }, { title = "Kind", width = 8 },
              { title = "Message", flex = 1 }, { title = "Age", width = 4, align = "right" } }
end

local refreshAlerts, refreshTurtles, showDetails

-- Only the tab on screen is updated. Components of the other tab still
-- have windows on the screen, and resizing them would draw over it, so
-- that tab is refreshed when it is shown again.
local AlertsTab, TurtlesTab = 1, 2
local function showing(tab) return ids.tabs:getSelected() == tab end

local alertsTab = {
  type = "box", title = "Alerts", dir = "vertical", children = {
    { type = "table", id = "alerts", flex = 1, columns = columns, rows = {},
      emptyText = "No alerts.",
      onSelect = function(e) showDetails(e.row.key) end },
  },
}

local turtlesTab = {
  type = "scroll", title = "Turtles", id = "turtlePane", children = {
    { type = "box", id = "turtleList", dir = "vertical", gap = 1, children = {
      { type = "text", text = "No turtles heard yet.", fgRole = "muted", h = 1 },
    } },
  },
}

root, ids = guibuild.build({
  type = "root", title = "Pager", dir = "vertical", children = {
    { type = "tabs", id = "tabs", flex = 1, children = { alertsTab, turtlesTab },
      onChange = function(e)
        if e.index == AlertsTab then refreshAlerts() else refreshTurtles() end
      end },
    { type = "text", id = "status", text = "Listening...", h = 1, fgRole = "muted" },
  },
})
app:setRootContainer(root)

local function counts()
  local active, fresh = 0, 0
  for _, a in pairs(alerts) do
    active = active + 1
    if not isAcked(a) then fresh = fresh + 1 end
  end
  local nt = 0
  for _ in pairs(turtles) do nt = nt + 1 end
  return active, fresh, nt
end

local tabTitle = "Alerts"
local function refreshStatus()
  local active, fresh, nt = counts()
  local title = fresh > 0 and ("Alerts " .. fresh) or "Alerts"
  if title ~= tabTitle then
    tabTitle = title
    ids.tabs:setTabTitle(AlertsTab, title) -- repaints the tabs, so only on a change
  end
  if flashLeft > 0 and flashText then
    ids.status:setText(flashText)
  else
    ids.status:setText(active .. " alert" .. (active == 1 and "" or "s") .. ", " .. fresh .. " new, "
      .. nt .. " turtle" .. (nt == 1 and "" or "s"))
  end
end

refreshAlerts = function()
  refreshStatus()
  if not showing(AlertsTab) then return end
  local list = {}
  for _, a in pairs(alerts) do list[#list + 1] = a end
  table.sort(list, function(a, b)
    if a.since ~= b.since then return a.since > b.since end
    return a.key < b.key
  end)
  local rows = {}
  for i, a in ipairs(list) do
    local row = { a.source, a.kind, a.message, ageText(now() - a.since), key = a.key }
    if isStale(a.id) then row.color = colors.gray
    elseif isAcked(a) then row.color = colors.lightGray
    else row.color = colors.red end
    rows[i] = row
  end
  ids.alerts:setRows(rows)
end

-- Grey a bar (stale) or give it back its colour.
local function greyBar(bar, stale, fill)
  if stale then bar:themed("fillColor", "muted") elseif fill then bar:setFillColor(fill)
  else bar:themed("fillColor", "fill") end
end

local function stateColor(t, stale)
  if stale then return colors.gray end
  if next(t.alerts or {}) then return colors.red end
  if t.state == "busy" then return colors.orange end
  if t.state == "error" then return colors.red end
  return colors.lime
end

local function updateTurtleRow(id)
  local r, t = turtleRows[id], turtles[id]
  if not r or not t or not showing(TurtlesTab) then return end
  local stale = isStale(id)
  local text = sourceName(id) .. " " .. tostring(t.state or "?")
  if t.job then text = text .. " " .. tostring(t.job) end
  if stale then text = text .. " (" .. ageText(now() - sources[id].heard) .. ")" end
  r.name:setText(text)
  r.name:setTextColor(stateColor(t, stale))

  if t.fuel == "unlimited" then
    r.fuel.warnBelow = nil
    r.fuel:setProgress(1, 1, "fuel unlimited")
  else
    local fuel = tonumber(t.fuel) or 0
    local full = math.max(1, math.min(tonumber(t.fuelLimit) or FuelFull, FuelFull))
    r.fuel.warnBelow = FuelLow
    r.fuel:setProgress(fuel, full, "fuel " .. tostring(t.fuel or "?"))
  end
  greyBar(r.fuel, stale)

  local p = t.progress
  if type(p) == "table" and t.state == "busy" then
    local parts = {}
    if p.done and p.total then parts[#parts + 1] = p.done .. "/" .. p.total
    elseif p.done then parts[#parts + 1] = tostring(p.done) end
    if p.text then parts[#parts + 1] = tostring(p.text) end
    local total = tonumber(p.total)
    if total and total > 0 then
      r.job:setProgress(math.min(tonumber(p.done) or 0, total), total, table.concat(parts, " "))
    else
      r.job:setProgress(0, 1, table.concat(parts, " "))
    end
  else
    local alertText = nil
    for kind, message in pairs(t.alerts or {}) do alertText = tostring(message) break end
    r.job:setProgress(0, 1, alertText or (t.message and tostring(t.message)) or "no job")
  end
  greyBar(r.job, stale, colors.cyan)
end

-- New components start with a window over the whole screen, and
-- sizing them draws it; building them on a hidden window keeps that off
-- the screen until they are added to the tree.
local offscreen = window.create(term.current(), 1, 1, w, h, false)
local function buildOffscreen(spec)
  local old = term.redirect(offscreen)
  local ok, c, parts = pcall(guibuild.build, spec)
  term.redirect(old)
  if not ok then error(c, 0) end
  return c, parts
end

-- Rebuild the turtle list when a turtle is first heard, sorted by name.
refreshTurtles = function()
  refreshStatus()
  if not showing(TurtlesTab) then return end
  local list = ids.turtleList
  local order = {}
  for id in pairs(turtles) do order[#order + 1] = id end
  table.sort(order, function(a, b)
    local na, nb = sourceName(a):lower(), sourceName(b):lower()
    if na ~= nb then return na < nb end
    return a < b
  end)
  list:removeAll()
  turtleRows = {}
  for _, id in ipairs(order) do
    local row, parts = buildOffscreen({ type = "box", dir = "vertical", w = math.max(1, ids.turtlePane.w - 1), h = 3,
      children = {
        { type = "text", id = "name", text = sourceName(id), h = 1 },
        { type = "progress", id = "fuel", value = 0, max = FuelFull, warnBelow = FuelLow, h = 1 },
        { type = "progress", id = "job", value = 0, max = 1, fill = colors.cyan, h = 1 },
      } })
    list:add(row)
    turtleRows[id] = parts
    updateTurtleRow(id)
  end
  ids.turtlePane:layoutContent()
end

--[[
Flashing and sound for a new alert
--]]

local function setFlash(on)
  if on then
    root:setBorderColor(colors.red)
    ids.status:setBackgroundColor(colors.red)
    ids.status:setTextColor(colors.white)
  else
    root:themed("borderColor", "header", colors.gray)
    ids.status:themed("backgroundColor", "background")
    ids.status:themed("textColor", "muted")
  end
  root:repaint()
end

local function beep()
  local speaker = peripheral.find("speaker")
  if speaker then
    pcall(speaker.playNote, "bell", 3, 18)
    pcall(speaker.playNote, "pling", 3, 12)
  end
end

local function announce(a)
  flashText = "! " .. a.source .. ": " .. a.message
  flashLeft = FlashTimes
  flashTimer = os.startTimer(0.5)
  setFlash(true)
  beep()
  refreshStatus()
end

--[[
Keeping track of alerts
--]]

-- An alert is active. Returns it when it is new or changed and not
-- acknowledged, so the caller can announce it.
local function setAlert(id, source, kind, message)
  local key = alertKey(id, kind)
  local a = alerts[key]
  if a and a.message == message then
    a.source = source
    return nil
  end
  if acks[key] and acks[key] ~= message then
    acks[key] = nil -- the alert changed, so the acknowledgement is over
    saveAcks()
  end
  a = { key = key, id = id, source = source, kind = kind, message = message, since = now() }
  alerts[key] = a
  if isAcked(a) then return nil end
  return a
end

local function clearAlert(id, kind)
  local key = alertKey(id, kind)
  alerts[key] = nil
  if acks[key] then
    acks[key] = nil
    saveAcks()
  end
end

local function heard(id, label, periodic)
  local s = sources[id]
  if not s then
    s = { id = id }
    sources[id] = s
  end
  if type(label) == "string" and label ~= "" then s.label = label end
  s.heard = now()
  s.periodic = s.periodic or periodic
end

local function onAlert(id, payload, label)
  if type(payload) ~= "table" or type(payload.kind) ~= "string" then return end
  local source = type(payload.source) == "string" and payload.source or label
  heard(id, source, false)
  local fresh = nil
  if payload.active then
    fresh = setAlert(id, sourceName(id), payload.kind, tostring(payload.message or payload.kind))
  else
    clearAlert(id, payload.kind)
  end
  refreshAlerts()
  if fresh then announce(fresh) end
  if turtleRows[id] then updateTurtleRow(id) end
end

-- A turtle's status carries all its alerts, so it also tidies up
-- alerts whose clear message was missed.
local function onStatus(id, status, label)
  if type(status) ~= "table" then return end
  local isNew = turtles[id] == nil
  heard(id, status.label or label, true)
  turtles[id] = status
  local fresh = nil
  local current = type(status.alerts) == "table" and status.alerts or {}
  for kind, message in pairs(current) do
    if type(kind) == "string" then
      fresh = setAlert(id, sourceName(id), kind, tostring(message)) or fresh
    end
  end
  for key, a in pairs(alerts) do
    if a.id == id and current[a.kind] == nil then clearAlert(id, a.kind) end
  end
  refreshAlerts()
  if fresh then announce(fresh) end
  if isNew then refreshTurtles() else updateTurtleRow(id) end
end

local function onMessage(topic, payload, sender, message)
  local label = type(message) == "table" and message.label or nil
  if topic == "alert" then
    onAlert(sender, payload, label)
  elseif topic == "turtle.status" then
    onStatus(sender, payload, label)
  end
end

--[[
Details
--]]

showDetails = function(key)
  ids.alerts:select(nil)
  local a = alerts[key]
  if not a then return end
  local lines = { a.message, "", "Since " .. ageText(now() - a.since) .. " ago, computer #" .. tostring(a.id) }
  local s = sources[a.id]
  if s and isStale(a.id) then lines[#lines + 1] = "Not heard for " .. ageText(now() - s.heard) end
  if isAcked(a) then lines[#lines + 1] = "Acknowledged" end
  local buttons = { { text = "Back" } }
  if isAcked(a) then
    buttons[2] = { text = "Unack", onPress = function()
      acks[key] = nil
      saveAcks()
      refreshAlerts()
    end }
  else
    buttons[2] = { text = compact and "Ack" or "Acknowledge", onPress = function()
      if alerts[key] then
        acks[key] = alerts[key].message
        saveAcks()
        if flashText and flashLeft > 0 then flashLeft = 0; setFlash(false) end
        refreshAlerts()
      end
    end }
  end
  local d = guidialog.GUIDialog.new(a.source .. " " .. a.kind, lines, buttons)
  d:show(root)
end

--[[
Events
--]]

local tick = os.startTimer(1)
app:addEventListener(function(event)
  local topic, payload, sender, message = bus.handle(table.unpack(event, 1, event.n))
  if topic then
    onMessage(topic, payload, sender, message)
  elseif event[1] == "timer" and event[2] == tick then
    tick = os.startTimer(1)
    refreshAlerts()
    for id in pairs(turtleRows) do updateTurtleRow(id) end
  elseif event[1] == "timer" and event[2] == flashTimer then
    flashLeft = flashLeft - 1
    if flashLeft > 0 then
      flashTimer = os.startTimer(0.5)
      setFlash(flashLeft % 2 == 0)
    else
      flashTimer = nil
      setFlash(false)
      refreshStatus()
    end
  end
end)

loadAcks()
bus.subscribe("alert")
bus.subscribe("turtle.status")
-- Ask everyone for the alerts that are active now.
bus.publish("alert.sync", {})

app:setUPS(20)
app:start()
guitheme.setTheme(previousTheme)
