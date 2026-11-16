--[[
Dispatcher keeps a queue of turtle jobs and hands them out to turtles
running turtleagent as they become free. It runs on a computer with a
wireless modem and shows the queue and the turtles on its own screen
(mouse and keyboard). The queue logic is apis/fleet.lua.

A queued job is a job from the turtle control catalogue with its
parameters, an optional site (x y z and heading, in Minecraft
coordinates, where the turtle must stand to start), an optional turtle
(id or label) that must do it, and a priority. Whenever a turtle
reports idle with no alerts and fuel for the trip and the job, it is
given the best job it may take: highest priority, then the nearest
site, then the oldest. A job with a site starts with goto to take the
turtle there; when it reports idle at the site the job is sent, and
afterwards the turtle is sent back to where it was (unless Return is
off). A job that fails is marked failed with the turtle's message and
stays in the list until Retry or Remove; a turtle that goes silent for
60 seconds, or restarts, loses its job, which goes back on the queue
while the turtle was still on its way and fails once it had started
(dispatcher requeue makes those go back on the queue too).

Screen: the queue (job, site, turtle, state and priority; touch a row
to pick it) above the turtles (state, fuel and position as their
agents report it), then Add, Remove, Up and Down (priority), Retry and
Clear (finished ones). Add picks a job from the catalogue, its site,
turtle and priority, and Params... fills in the job's parameters with
the same form as turtle control.

Other computers can queue jobs over the bus ("fleet.enqueue" with {
job, values, site, turtle, priority }, answered with "fleet.added"),
which is what the fleet program does, and ask for the queue
("fleet.list", answered with "fleet.queue"). Every change goes out as
"fleet.job". The queue is kept in fleet_queue.dat.

Usage: dispatcher [requeue]
--]]

local args = { ... }
local queueFile = "fleet_queue.dat"
local publishEvery = 10 -- seconds between fleet.queue messages
local discoverEvery = 30

local fleetQueue = fleet.new({ lostPolicy = args[1] == "requeue" and "requeue" or "fail" })
fleetQueue:loadFile(queueFile)

local opened = (bus and bus.open and bus.open()) or turtlectl.openModem()
if not opened then
  print("Error: no wireless modem attached")
  return
end
if bus and bus.subscribe then
  bus.subscribe("fleet.enqueue")
  bus.subscribe("fleet.list")
end

local display = term.current()
if not display.isColor() then
  print("Error: an advanced computer is needed for the mouse")
  return
end

local app = guiapplication.GUIApplication.new()
local screen = nil -- { refresh = fn } while the main screen shows
local lastNote = "Waiting for turtles"
local queueTimer -- debounce for fleet.queue after changes

local function publish(topic, payload)
  if bus and bus.publish then pcall(bus.publish, topic, payload) end
end

local function publishQueue()
  local list = {}
  for i, e in ipairs(fleetQueue:list()) do list[i] = fleetQueue:summary(e) end
  publish("fleet.queue", { entries = list })
end

-- Send and publish what the queue asks for, and save when it changed.
local function flush()
  for _, a in ipairs(fleetQueue:take()) do
    if a.kind == "send" then
      turtlectl.sendCommand(a.turtle, a.job, a.args)
      local t = fleetQueue.turtles[a.turtle]
      lastNote = "#" .. a.entry .. ": sent " .. a.job .. " to " .. (t and t.label or a.turtle)
    elseif a.kind == "publish" then
      publish(a.topic, a.payload)
      if a.topic == "fleet.job" and (a.payload.state == "done" or a.payload.state == "failed") then
        lastNote = "#" .. a.payload.id .. " " .. a.payload.name .. " " .. a.payload.state
          .. (a.payload.message and (": " .. a.payload.message) or "")
      end
    end
  end
  if fleetQueue.dirty then
    fleetQueue:saveFile(queueFile)
    queueTimer = queueTimer or os.startTimer(0.5)
  end
  if screen then screen.refresh() end
end

--[[
Screen helpers
--]]

local function newRoot(title, decorations)
  local root = guirootcontainer.GUIRootContainer.new(display)
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

local function newButton(text, x, y, w, color, onClick)
  local button = guibutton.GUIButton.new(text)
  button:setPreferredBounds(x, y, math.max(1, w), 1)
  button:setBackgroundColor(color or colors.blue)
  button.pressColor = colors.lightGray
  button:setTextColor(colors.white)
  button:setBorder(false)
  button:addButtonListener(onClick)
  return button
end

local function newInput(text, x, y, w)
  local input = guiinput.GUIInput.new(text or "")
  input:setPreferredBounds(x, y, math.max(2, w), 1)
  input:setBorder(false)
  input:setBackgroundColor(colors.gray)
  input:setTextColor(colors.white)
  return input
end

local function setRoot(root, handlers)
  screen = handlers
  app:setRootContainer(root)
  root:setStarted(true)
  root:repaint()
  if screen and screen.refresh then screen.refresh() end
end

local stateColors = {
  queued = colors.white, moving = colors.yellow, running = colors.orange, returning = colors.yellow,
  done = colors.lime, failed = colors.red,
}

local function posText(p)
  if not p then return "-" end
  local text = p.x .. " " .. p.y .. " " .. p.z
  if p.heading then text = text .. " " .. fleet.headingArrow(p.heading) end
  return text
end

local showMain, showAdd, showParams, showText

-- What is being added: kept while moving between the Add screens.
local draft

local function newDraft()
  local job = turtlectl.jobs[1]
  return { job = job.id, values = turtlectl.jobDefaults(job), x = "", y = "", z = "", heading = "-",
    turtle = "", priority = 0, returnHome = true }
end

--[[
Main screen: the queue and the turtles.
--]]

showMain = function(note)
  if note then lastNote = note end
  local w, h = display.getSize()
  local root = newRoot("Dispatcher", true)
  local avail = h - 3
  local queueH = math.max(3, math.ceil(avail * 0.6))
  local turtlesH = math.max(2, avail - queueH)
  local queue = guitable.GUITable.new({
    { title = "#", width = 3, align = "right" },
    { title = "Job", flex = 1 },
    { title = "Site", width = 14 },
    { title = "Turtle", width = 9 },
    { title = "State", width = 9 },
    { title = "Pri", width = 3, align = "right" },
  })
  queue:setPreferredBounds(1, 2, w, queueH)
  queue:setEmptyText("Nothing queued: Add a job")
  root:add(queue)
  local turtleTable = guitable.GUITable.new({
    { title = "Turtle", flex = 1 },
    { title = "State", width = 7 },
    { title = "Fuel", width = 7, align = "right" },
    { title = "Position", width = 16 },
    { title = "Doing", width = 8 },
  })
  turtleTable:setPreferredBounds(1, 2 + queueH, w, turtlesH)
  turtleTable:setEmptyText("No turtles heard yet")
  root:add(turtleTable)
  local status = newLabel(lastNote, 1, h - 1, w, colors.lightGray)
  root:add(status)

  local selectedId = nil
  queue:addSelectListener(function(e)
    selectedId = e.row and e.row.id
    local entry = selectedId and fleetQueue:get(selectedId)
    if entry then
      status:setText("#" .. entry.id .. " " .. entry.state .. (entry.message and (": " .. entry.message) or ""))
    end
  end)

  local function refresh()
    local rows = {}
    for i, e in ipairs(fleetQueue:list()) do
      local job = turtlectl.findJob(e.job)
      local who = e.turtleLabel or (e.only and ("only " .. e.only)) or "any"
      rows[i] = { e.id, job and job.name or e.job, fleet.siteText(e.site), who, e.state, e.priority,
        id = e.id, color = stateColors[e.state] }
    end
    queue:setRows(rows)
    if selectedId then
      for i, r in ipairs(rows) do
        if r.id == selectedId then queue:select(i, false) end
      end
    end
    local trows = {}
    local ids = {}
    for id in pairs(fleetQueue.turtles) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local t = fleetQueue.turtles[id]
      local doing = t.entry and ("#" .. t.entry) or (t.short and "low fuel") or ""
      local color = (t.state == "idle" and colors.lime) or (t.state == "busy" and colors.orange)
        or (t.state == "error" and colors.red) or colors.gray
      if next(t.alerts or {}) then color = colors.red end
      trows[#trows + 1] = { t.label, t.state, tostring(t.fuel or "?"), posText(t.pos), doing, color = color }
    end
    turtleTable:setRows(trows)
    status:setText(lastNote)
  end

  local function act(fn)
    if not selectedId then return status:setText("Touch a job in the queue first") end
    local ok, err = fn(selectedId)
    if not ok and err then lastNote = err end
    flush()
  end
  local buttons = {
    { "Add", colors.green, function() draft = newDraft() showAdd() end },
    { "Remove", colors.red, function() act(function(id)
      local ok, err = fleetQueue:remove(id)
      if ok then lastNote, selectedId = "Removed #" .. id, nil end
      return ok, err
    end) end },
    { "Up", colors.blue, function() act(function(id) return fleetQueue:bump(id, 1) end) end },
    { "Down", colors.blue, function() act(function(id) return fleetQueue:bump(id, -1) end) end },
    { "Retry", colors.orange, function() act(function(id) return fleetQueue:retry(id, os.clock()) end) end },
    { "Clear", colors.gray, function() fleetQueue:clearFinished() lastNote = "Cleared finished jobs" flush() end },
  }
  local bw = math.floor((w - (#buttons - 1)) / #buttons)
  for i, b in ipairs(buttons) do
    root:add(newButton(b[1], 1 + (i - 1) * (bw + 1), h, bw, b[2], b[3]))
  end
  setRoot(root, { refresh = refresh })
end

--[[
Adding a job: the job, its site, turtle and priority, then Params...
--]]

-- A short line of the draft's parameter values.
local function valuesText(job, values)
  local parts = {}
  for _, p in ipairs(job.params or {}) do
    local v = values[p.name]
    if p.type == "bool" then v = v and "yes" or "no" end
    parts[#parts + 1] = p.name .. "=" .. tostring(v)
  end
  if #parts == 0 then return "(no parameters)" end
  return table.concat(parts, " ")
end

showAdd = function(message)
  local w, h = display.getSize()
  local root = newRoot("Add a job")
  root:add(newLabel("Add a job to the queue", 1, 1, w, colors.yellow))
  local labelW = 10
  local job = turtlectl.findJob(draft.job)
  local row = 3
  local function label(text) root:add(newLabel(text, 1, row, labelW, colors.lightGray)) end

  label("Job")
  local names, ids = {}, {}
  for i, j in ipairs(turtlectl.jobs) do names[i], ids[j.name] = j.name, j.id end
  local jobDrop = jobform.newDropdown(names, job.name, labelW + 1, row, 16)
  jobDrop:addSelectListener(function(e)
    local picked = turtlectl.findJob(ids[e.value])
    if picked and picked.id ~= draft.job then
      draft.job, draft.values = picked.id, turtlectl.jobDefaults(picked)
      showAdd()
    end
  end)
  row = row + 2
  label("Site x y z")
  local fw = 7
  local xs = newInput(draft.x, labelW + 1, row, fw)
  local ys = newInput(draft.y, labelW + 2 + fw, row, fw)
  local zs = newInput(draft.z, labelW + 3 + 2 * fw, row, fw)
  -- Inputs go in before any button: a click is handed to components in
  -- the order they were added, and a button that changes screen must
  -- come after the inputs have dealt with it (losing focus redraws them).
  root:add(xs) root:add(ys) root:add(zs)
  local headingDrop = jobform.newDropdown({ "-", "north", "east", "south", "west" }, draft.heading, labelW + 4 + 3 * fw, row, 8)
  row = row + 1
  root:add(newLabel("blank for no site; - keeps the heading", labelW + 1, row, w - labelW, colors.gray))
  row = row + 2
  label("Turtle")
  local only = newInput(draft.turtle, labelW + 1, row, 12)
  root:add(only)
  root:add(newLabel("id or label, blank: any", labelW + 14, row, w - labelW - 14, colors.gray))
  row = row + 2
  label("Priority")
  local prio = newLabel(tostring(draft.priority), labelW + 5, row, 4, colors.yellow)
  local function setPrio(d)
    draft.priority = draft.priority + d
    prio:setText(tostring(draft.priority))
  end
  root:add(newButton("-", labelW + 1, row, 3, colors.blue, function() setPrio(-1) end))
  root:add(prio)
  root:add(newButton("+", labelW + 10, row, 3, colors.blue, function() setPrio(1) end))
  local ret = guicheckbox.GUICheckbox.new("Return after", draft.returnHome)
  ret:setPreferredBounds(labelW + 16, row, 16, 1)
  ret:addChangeListener(function(e) draft.returnHome = e.checked end)
  row = row + 2
  label("Params")
  root:add(newLabel(valuesText(job, draft.values), labelW + 1, row, w - labelW, colors.white))
  row = row + 1

  -- Keep what was typed when moving to another screen.
  local function keep()
    draft.x, draft.y, draft.z = xs.text, ys.text, zs.text
    draft.heading = headingDrop:getValue()
    draft.turtle = only.text
  end
  local status = newLabel(message or "Click a field to type in it", 1, h - 1, w, message and colors.red or colors.lightGray)
  root:add(status)
  if job.params and #job.params > 0 then
    root:add(newButton("Params...", labelW + 1, row, 11, colors.purple, function() keep() showParams() end))
  end
  root:add(newButton("Add to queue", 1, h, 14, colors.green, function()
    keep()
    local site = nil
    if draft.x ~= "" or draft.y ~= "" or draft.z ~= "" then
      site = draft.x .. "," .. draft.y .. "," .. draft.z
      if draft.heading ~= "-" then site = site .. "," .. draft.heading end
    end
    local entry, err = fleetQueue:add({ job = draft.job, values = draft.values, site = site, turtle = draft.turtle,
      priority = draft.priority, returnHome = draft.returnHome, now = os.clock() })
    if not entry then return showAdd(err) end
    lastNote = "Queued #" .. entry.id .. " " .. job.name
    flush()
    showMain()
  end))
  root:add(newButton("Cancel", 16, h, 8, colors.gray, function() showMain() end))
  root:add(ret)
  -- dropdowns last so their lists open over the rest
  root:add(headingDrop)
  root:add(jobDrop)
  setRoot(root, nil)
end

-- The job's parameters, with the turtle control form.
showParams = function()
  local w, h = display.getSize()
  local job = turtlectl.findJob(draft.job)
  local root = newRoot(job.name)
  root:add(newLabel(job.name .. " parameters", 1, 1, w - 7, colors.yellow))
  root:add(newButton("Back", w - 5, 1, 6, colors.gray, function() showAdd() end))
  local startY, startH = jobform.add(root, job, draft.values, {
    top = 3, w = w, h = h,
    onText = function(param)
      showText(param.label, tostring(draft.values[param.name] or ""), function(text)
        draft.values[param.name] = text
        showParams()
      end)
    end,
  })
  root:add(newButton("Done", 2, startY + startH - 1, w - 2, colors.green, function() showAdd() end))
  setRoot(root, nil)
end

-- Type one text value with the keyboard.
showText = function(title, text, onDone)
  local w, h = display.getSize()
  local root = newRoot(title)
  root:add(newLabel(title .. ": type, then Enter or OK", 1, 1, w, colors.yellow))
  local input = newInput(text, 2, 3, w - 2)
  root:add(input)
  local function done() onDone(input.text) end
  input:addDoneListener(done)
  root:add(newButton("OK", 2, 5, 8, colors.green, done))
  root:add(newButton("Cancel", 11, 5, 8, colors.gray, function() showParams() end))
  setRoot(root, nil)
  input:setActive(true)
  input.cursorPos = #input.text
end

--[[
Network and timers
--]]

local tickTimer = os.startTimer(1)
local publishTimer = os.startTimer(2)
local discoverTimer = os.startTimer(0)

app:addEventListener(function(event)
  local now = os.clock()
  if event[1] == "rednet_message" and event[4] == turtlectl.PROTOCOL then
    local sender, msg = event[2], event[3]
    if turtlectl.isMessage(msg, "status") then
      fleetQueue:onStatus(msg, now)
      flush()
    elseif turtlectl.isMessage(msg, "ack") then
      fleetQueue:onAck(sender, msg, now)
      flush()
    end
  elseif event[1] == "timer" then
    if event[2] == tickTimer then
      fleetQueue:tick(now)
      flush()
      tickTimer = os.startTimer(1)
    elseif event[2] == publishTimer or event[2] == queueTimer then
      publishQueue()
      if event[2] == queueTimer then queueTimer = nil else publishTimer = os.startTimer(publishEvery) end
    elseif event[2] == discoverTimer then
      turtlectl.broadcastDiscover()
      discoverTimer = os.startTimer(discoverEvery)
    end
  elseif bus and bus.handle then
    local topic, payload, from = bus.handle(table.unpack(event, 1, event.n))
    if topic == "fleet.enqueue" and type(payload) == "table" then
      local entry, err = fleetQueue:add({ job = payload.job, values = payload.values, site = payload.site,
        turtle = payload.turtle, priority = payload.priority, returnHome = payload.returnHome, now = now })
      publish("fleet.added", { ref = payload.ref, to = from, ok = entry ~= nil, id = entry and entry.id, message = err })
      if entry then lastNote = "Queued #" .. entry.id .. " " .. entry.job .. " from #" .. tostring(from) end
      flush()
    elseif topic == "fleet.list" then
      publishQueue()
    end
  end
end)

app:setUPS(20)
showMain()
app:start()
