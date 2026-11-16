--[[
Lift dispatches one vehicle, an elevator car or a train, between a line
of stops using redstone only. Each stop has a call input (a button at
that floor wired back to the computer, or one colour of bundled cable),
a send output that makes the vehicle go there (a Create elevator
contact or train station link, pulsed or held) and optionally an
arrived input that is on while the vehicle is at that stop. Calls are
queued once each and served nearest first in the direction of travel
(look, like an elevator), in order (fifo) or running to the end of the
line before turning round (scan). Without arrived inputs the vehicle is
assumed to arrive a set time per stop after it was sent. The queue and
the scheduling are apis/lift.lua; the stops are in /lift.cfg.

The panel shows the stops with the highest at the top, where the
vehicle is ([#]), where it is going (>) and which stops are called
(*), with a Call button for each; touching one calls the vehicle there
like the button at that stop would. Under them are the queue, the
algorithm and Hold (keep the send output on instead of pulsing it).
Every call, departure and arrival is published on the bus as
"base.lift" { event, stop, position, queue, state }; a trip that never
arrives raises an alert.

On a monitor the computer's own screen logs every trip and takes
commands; on the own screen a pasted line runs as a command:
  call <stop>              call the vehicle (a name or a number)
  arrived <stop>           say where the vehicle is now
  stop <name> <call> <send> [arrived]
                           add a stop at the top of the line, or change
                           one; signals are a side (left) or a side and
                           colour (back:white), - for none
  unstop <name>            remove a stop
  algorithm look|fifo|scan, hold on|off, pulse <s>, travel <s>, dwell <s>
  list, help, quit

Usage: lift [monitor|term] [configFile]
--]]

local args = { ... }
local configFile = args[2] or lift.ConfigFile
local config = lift.loadConfig(configFile)

local disp, err = basepanel.display(args[1], 30, 12)
if not disp then
  print("Error: " .. err)
  return
end

local previousTheme = guitheme.isChosen() and guitheme.getTheme() or nil
guitheme.setTheme("dark")

local d = lift.new(config)
local app = guiapplication.GUIApplication.new()
local root, ids
local lastCall, lastArrived = {}, {}

local function save()
  lift.saveConfig(config, configFile)
end

local function status(text)
  if ids and ids.status then ids.status:setText(text) end
end

local function queueText()
  local names = {}
  for _, i in ipairs(d.queue) do names[#names + 1] = d:name(i) end
  return #names > 0 and table.concat(names, ", ") or "empty"
end

local function sigText(sig)
  return circuits.signalText(sig)
end

--[[
The view
--]]

-- Set a text only when it changed: the view is refreshed four times a
-- second.
local function put(c, text, color)
  if c.shown == text and c.shownColor == color then return end
  c.shown, c.shownColor = text, color
  if color then c:setTextColor(color) end
  c:setText(text)
end

local function updateView()
  if not ids then return end
  local line = d:describe()
  local eta = d:eta()
  if eta and not d:hasArrivalInput(d.target) then line = line .. string.format(" (%ds)", math.ceil(eta)) end
  put(ids.where, line)
  put(ids.queue, "Queue: " .. queueText())
  for i, s in ipairs(config.stops) do
    local mark = ids["m" .. i]
    if mark then
      local m = "   "
      if d.position == i and d.state ~= "moving" then m = "[#]"
      elseif d.state == "moving" and d.target == i then m = " > "
      elseif d.position == i then m = "[ ]"
      elseif d:isQueued(i) then m = " * " end
      local here = d.position == i and d.state ~= "moving"
      put(mark, m, here and colors.lime or (d:isQueued(i) and colors.yellow or colors.lightGray))
    end
  end
end

local buildRoot

local function callStop(i)
  local ok, why = d:call(i)
  if not ok then return why end
  os.queueEvent("lift_step")
  return "called " .. d:name(i)
end

buildRoot = function()
  local compact = disp.compact
  local rows = {}
  for i = #config.stops, 1, -1 do
    local s = config.stops[i]
    local row = { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
      { type = "text", id = "m" .. i, text = "   ", w = 3 },
      { type = "text", text = s.name, flex = 1 },
    } }
    if not compact then
      row.children[#row.children + 1] = { type = "text", text = "call " .. sigText(s.call) .. "  send " .. sigText(s.send), w = 28, fgRole = "muted" }
    end
    row.children[#row.children + 1] = { type = "button", text = "Call", w = 6, onPress = function() status(callStop(i)) end }
    rows[#rows + 1] = row
  end
  local algIndex = 1
  for k, a in ipairs(lift.Algorithms) do if a == config.algorithm then algIndex = k end end

  local newRoot
  newRoot, ids = guibuild.build({
    type = "root", title = "Lift", term = disp.term, side = disp.side, dir = "vertical", gap = compact and 0 or 1, children = {
      { type = "text", id = "where", text = "", h = 1 },
      { type = "scroll", flex = 1, children = {
        { type = "box", dir = "vertical", gap = (compact or #rows > 6) and 0 or 1, children = rows },
      } },
      { type = "text", id = "queue", text = "Queue: empty", h = 1, fgRole = "muted" },
      { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
        { type = "dropdown", id = "alg", options = lift.Algorithms, selected = algIndex, w = 6, onSelect = function()
            config.algorithm = ids.alg:getValue()
            save()
            status("Algorithm " .. config.algorithm)
          end },
        { type = "checkbox", id = "hold", text = "Hold", checked = config.hold and true or false, w = 8, onChange = function()
            config.hold = ids.hold:isChecked()
            save()
            status(config.hold and "Send outputs are held on" or "Send outputs are pulsed")
          end },
        { type = "text", id = "status", text = "Touch Call to call the vehicle.", flex = 1, fgRole = "muted" },
      } },
    },
  })
  root = newRoot
  app:setRootContainer(root)
  if app.running then
    root:setStarted(true)
    root:repaint()
  end
  updateView()
end

--[[
Inputs, the dispatcher and the outputs
--]]

-- Read every call and arrived input; rising edges call and arrive.
local function readInputs(first)
  for i, s in ipairs(config.stops) do
    local c = s.call and circuits.readSignal(s.call) or false
    if c and not lastCall[i] and not first then
      local ok, why = d:call(i)
      if not ok then basepanel.log(basepanel.timeText(os.time()) .. " call at " .. s.name .. ": " .. why) end
    end
    lastCall[i] = c
    local a = s.arrived and circuits.readSignal(s.arrived) or false
    if a and not lastArrived[i] then d:arrive(i) end
    lastArrived[i] = a
  end
end

local function describeEvent(e)
  local t = basepanel.timeText(os.time()) .. " "
  if e.event == "call" then return t .. "call at " .. e.name .. " (queue: " .. queueText() .. ")" end
  if e.event == "dispatch" then
    local s = config.stops[e.stop]
    return t .. "sent to " .. e.name .. " from " .. d:name(e.from) .. " (" .. sigText(s.send) .. (config.hold and " held" or " pulse") .. ")"
  end
  if e.event == "arrive" then
    return t .. "at " .. e.name .. (e.assumed and " (by travel time)" or "") .. (e.unexpected and " (moved by hand)" or "")
  end
  if e.event == "pass" then return t .. "passing " .. e.name end
  if e.event == "idle" then return t .. "waiting at " .. e.name end
  if e.event == "lost" then return t .. "never arrived at " .. e.name end
  return t .. e.event .. " " .. tostring(e.name)
end

local function step()
  local events = d:update()
  for _, e in ipairs(events) do
    basepanel.log(describeEvent(e))
    local names = {}
    for _, i in ipairs(d.queue) do names[#names + 1] = d:name(i) end
    basepanel.publish("base.lift", { event = e.event, stop = e.name, index = e.stop, position = d:name(d.position),
                                     queue = names, state = d.state })
    if e.event == "lost" then
      basepanel.setAlert("lift", "The lift never arrived at " .. e.name .. "; check the track or the contact", true)
    elseif e.event == "arrive" and not e.assumed then
      basepanel.setAlert("lift", "The lift is arriving again", false)
    end
  end
  circuits.writeOutputs(d:outputs())
  updateView()
end

local function control()
  readInputs(true)
  -- an arrived input that is on at the start says where the vehicle is
  for i in pairs(lastArrived) do if lastArrived[i] then d.position = i end end
  step()
  local timer = os.startTimer(0.25)
  while true do
    local event, p1 = os.pullEvent()
    if event == "redstone" then
      readInputs()
      step()
    elseif event == "lift_step" then
      step()
    elseif event == "timer" and p1 == timer then
      step()
      timer = os.startTimer(0.25)
    end
  end
end

--[[
Commands
--]]

local helpText = "commands: call <stop>, arrived <stop>, stop <name> <call> <send> [arrived], unstop <name>, algorithm look|fifo|scan, hold on|off, pulse|travel|dwell <s>, list, quit"

local function parseSig(word)
  if word == nil or word == "-" or word == "none" then return nil end
  local sig, why = circuits.parseSignal(word)
  if not sig then error(why, 0) end
  return sig
end

local function command(line)
  local w = basepanel.words(line)
  local cmd = (w[1] or ""):lower()
  if cmd == "help" or cmd == "?" then return helpText
  elseif cmd == "call" then
    local i = d:find(table.concat(w, " ", 2))
    if not i then return "no stop called " .. table.concat(w, " ", 2) end
    return callStop(i)
  elseif cmd == "arrived" then
    local i = d:find(table.concat(w, " ", 2))
    if not i then return "no stop called " .. table.concat(w, " ", 2) end
    d:arrive(i)
    os.queueEvent("lift_step")
    return "the vehicle is at " .. d:name(i)
  elseif cmd == "stop" then
    if #w < 4 then return "stop <name> <call> <send> [arrived]" end
    local ok, s = pcall(function()
      return { name = w[2], call = parseSig(w[3]), send = parseSig(w[4]), arrived = parseSig(w[5]) }
    end)
    if not ok then return s end
    if not s.send then return "a stop needs a send output" end
    local i = d:find(w[2])
    if i and config.stops[i].name:lower() == w[2]:lower() then
      config.stops[i] = s
    else
      config.stops[#config.stops + 1] = s
      i = #config.stops
    end
    save()
    buildRoot()
    return "stop " .. i .. " " .. s.name .. ": call " .. sigText(s.call) .. ", send " .. sigText(s.send) .. ", arrived " .. sigText(s.arrived)
  elseif cmd == "unstop" then
    local i = d:find(table.concat(w, " ", 2))
    if not i then return "no stop called " .. table.concat(w, " ", 2) end
    local s = table.remove(config.stops, i)
    -- renumber the queue and the vehicle's place
    local q = {}
    for _, k in ipairs(d.queue) do if k ~= i then q[#q + 1] = k > i and k - 1 or k end end
    d.queue = q
    if d.position > i then d.position = d.position - 1 elseif d.position == i then d.position = 1 end
    if d.target and d.target >= i then d.state, d.target, d.sending = "idle", nil, nil end
    if s.send then circuits.writeOutputs({ { side = s.send.side, color = s.send.color, on = false } }) end
    lastCall, lastArrived = {}, {}
    readInputs(true)
    save()
    buildRoot()
    return "removed " .. s.name
  elseif cmd == "algorithm" then
    for _, a in ipairs(lift.Algorithms) do
      if w[2] == a then
        config.algorithm = a
        save()
        ids.alg:setValue(a)
        return "algorithm " .. a
      end
    end
    return "algorithm look|fifo|scan"
  elseif cmd == "hold" then
    if w[2] ~= "on" and w[2] ~= "off" then return "hold on|off" end
    config.hold = w[2] == "on"
    save()
    ids.hold:setChecked(config.hold)
    return config.hold and "send outputs are held" or "send outputs are pulsed"
  elseif cmd == "pulse" or cmd == "travel" or cmd == "dwell" then
    local n = tonumber(w[2])
    if not n or n < 0 then return cmd .. " <seconds>" end
    config[cmd] = n
    save()
    return cmd .. " " .. n .. "s"
  elseif cmd == "list" then
    local out = {}
    for i, s in ipairs(config.stops) do
      out[#out + 1] = i .. " " .. s.name .. " (call " .. sigText(s.call) .. ", send " .. sigText(s.send) .. ", arrived " .. sigText(s.arrived) .. ")"
    end
    return d:describe() .. "; queue " .. queueText() .. "; " .. table.concat(out, "; ")
  end
  return "unknown command " .. cmd .. "; " .. helpText
end

buildRoot()
app:setUPS(20)
basepanel.run({
  app = app, display = disp, name = "lift", commands = command,
  loops = { control, basepanel.busLoop({}) },
  onStatus = function(msg) status(msg) end,
})
circuits.writeOutputs((function()
  local off = d:outputs()
  for _, o in ipairs(off) do o.on = false end
  return off
end)())
guitheme.setTheme(previousTheme)
