--[[
Basepanel is the shared frame of the base automation programs
(storage, doors, machines, lift): it picks the screen, runs the GUI
next to the program's own loops, and gives the program a command line.

  local disp = basepanel.display(args[1], 40, 16)      -- monitor or own screen
  local root, ids = guibuild.build({ type = "root", term = disp.term, side = disp.side, ... })
  basepanel.run({ app = app, display = disp, name = "storage",
                  commands = function(line) return "did " .. line end,
                  loops = { workerLoop } })

The display is the monitor named by the first argument, or the first
advanced monitor found, or the computer's own screen ("term" forces
it). On a monitor the GUI is touched and the computer's own screen
shows a log of what happens with a command prompt under it; on the own
screen the mouse works the GUI and a pasted line (Ctrl+V) runs as a
command, which is also how a scripted player types into the program.

The GUI's own event loop stops handling an event as soon as its update
interval ends, so button handlers must not do slow work (peripheral
calls yield). Programs queue the work instead and do it in one of the
loops, which run in parallel with the GUI.
--]]

local logWin, promptWin, reading
local mode = "term"
local recent = {}

-- Choose where the GUI goes. Returns { term, side, monitor, w, h,
-- compact } or nil and an error.
function display(arg, minW, minH, scale)
  local mon, side
  if arg == "term" or arg == "screen" then
    mon = nil
  elseif arg and arg ~= "" then
    if not peripheral.hasType(arg, "monitor") then return nil, "no monitor called " .. arg end
    mon, side = peripheral.wrap(arg), arg
  else
    mon = peripheral.find("monitor", function(name, m) return m.isColor() end)
    if mon then side = peripheral.getName(mon) end
  end
  if mon then
    if not mon.isColor() then return nil, "an advanced monitor is needed for touch" end
    local fit = guitheme.fit(mon, minW or 30, minH or 12, scale)
    return { term = mon, side = side, monitor = true, w = fit.w, h = fit.h, compact = fit.compact }
  end
  local w, h = term.getSize()
  if not term.isColor() then return nil, "an advanced computer is needed for the mouse" end
  return { term = term.current(), side = nil, monitor = false, w = w, h = h, compact = guitheme.isCompact(w, h) }
end

-- Say what happened: printed on the computer's own screen when the GUI
-- is on a monitor, and kept in a short list the GUI can show.
function log(text)
  text = tostring(text)
  table.insert(recent, 1, text)
  if #recent > 20 then table.remove(recent) end
  if mode ~= "monitor" then return end
  if logWin then
    local old = term.redirect(logWin)
    print(text)
    term.redirect(promptWin)
    promptWin.restoreCursor()
  else
    print(text)
  end
end

function recentLog()
  return recent
end

-- A clock string for the in-game time os.time() gives (0 to 24).
function timeText(t)
  t = t or os.time()
  local h = math.floor(t) % 24
  local m = math.floor((t - math.floor(t)) * 60 + 0.5)
  if m == 60 then h, m = (h + 1) % 24, 0 end
  return string.format("%02d:%02d", h, m)
end

-- Split a command line into words, keeping "quoted words" together.
function words(line)
  local out = {}
  local s = tostring(line)
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if c:match("%s") then
      i = i + 1
    elseif c == '"' then
      local j = s:find('"', i + 1, true) or (#s + 1)
      out[#out + 1] = s:sub(i + 1, j - 1)
      i = j + 1
    else
      local j = s:find("%s", i) or (#s + 1)
      out[#out + 1] = s:sub(i, j - 1)
      i = j
    end
  end
  return out
end

-- Run the GUI with the program's loops. opts: app, display, name,
-- commands (function(line) returning a message to show), loops (list
-- of functions), onStatus (function(message) for command results on
-- the own screen). Returns when the GUI is closed or a loop ends.
function run(opts)
  local disp = opts.display
  local fns = { function() opts.app:start() end }
  for _, f in ipairs(opts.loops or {}) do fns[#fns + 1] = f end
  local function runCommand(line)
    if not opts.commands or not line or line:match("^%s*$") then return end
    local ok, msg = pcall(opts.commands, line)
    if not ok then msg = "error: " .. tostring(msg) end
    if msg then
      log(msg)
      if opts.onStatus then opts.onStatus(msg) end
    end
  end
  if disp.monitor then
    mode = "monitor"
    local native = term.current()
    local w, h = native.getSize()
    native.clear()
    logWin = window.create(native, 1, 1, w, math.max(1, h - 1))
    promptWin = window.create(native, 1, h, w, 1)
    log((opts.name or "panel") .. " on monitor " .. disp.side .. ". Type a command, or help.")
    fns[#fns + 1] = function()
      term.redirect(promptWin)
      local history = {}
      while true do
        promptWin.clear()
        promptWin.setCursorPos(1, 1)
        promptWin.setTextColor(colors.yellow)
        promptWin.write((opts.name or "") .. "> ")
        promptWin.setTextColor(colors.white)
        local line = read(nil, history)
        if line ~= "" then table.insert(history, line) end
        if line == "quit" or line == "exit" then return end
        runCommand(line)
      end
    end
  else
    mode = "term"
    opts.app:addEventListener(function(event)
      if event[1] == "paste" then
        -- run it after the GUI has handled this event
        os.queueEvent("basepanel_command", event[2])
      elseif event[1] == "basepanel_command" then
        if event[2] == "quit" or event[2] == "exit" then opts.app:stop() else runCommand(event[2]) end
      end
    end)
  end
  parallel.waitForAny(table.unpack(fns))
  if disp.monitor then
    term.redirect(term.native())
    disp.term.setBackgroundColor(colors.black)
    disp.term.clear()
  end
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  mode, logWin, promptWin = "term", nil, nil
end

-- Open rednet on every modem, wired and wireless, so bus messages
-- reach this computer whichever way they come (a turtle on the wired
-- network, a pager over wireless). Returns true when any is open.
function openModems()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "modem") and not rednet.isOpen(name) then pcall(rednet.open, name) end
  end
  return rednet.isOpen()
end

-- Publish on the bus when there is one. Returns true when sent.
function publish(topic, payload)
  if not (bus and bus.publish) then return false end
  if not rednet.isOpen() then openModems() end
  local ok, sent = pcall(bus.publish, topic, payload)
  return ok and sent
end

-- An alert payload as the bus spec has it.
function alertPayload(kind, message, active)
  if bus and bus.newAlert then return bus.newAlert(kind, message, active) end
  return { id = os.getComputerID(), source = os.getComputerLabel() or ("Computer " .. os.getComputerID()),
           kind = kind, message = message, active = active and true or false }
end

-- Keep track of this program's alerts (one per kind), publish
-- changes, and publish the active ones again when a listener asks
-- (alert.sync). Raising a kind again with the same message does
-- nothing; with a new message it is published again.
local activeAlerts = {}
function setAlert(kind, message, active)
  if active and activeAlerts[kind] == message then return false end -- nothing new
  if active then activeAlerts[kind] = message
  elseif activeAlerts[kind] == nil then return false -- nothing to clear
  else activeAlerts[kind] = nil end
  log((active and "ALERT " or "cleared ") .. kind .. ": " .. message)
  publish("alert", alertPayload(kind, message, active))
  return true
end

function activeAlertList()
  local out = {}
  for kind, message in pairs(activeAlerts) do out[#out + 1] = { kind = kind, message = message } end
  table.sort(out, function(a, b) return a.kind < b.kind end)
  return out
end

-- A loop for basepanel.run's loops: listens on the bus for the given
-- topics, calls onMessage(topic, payload, sender) for each and answers
-- alert.sync. Without a bus API it just waits for ever.
function busLoop(topics, onMessage)
  return function()
    if not (bus and bus.subscribe and bus.receive) then
      while true do os.pullEvent("basepanel_never") end
    end
    openModems()
    bus.subscribe("alert.sync")
    for _, t in ipairs(topics or {}) do bus.subscribe(t) end
    while true do
      local topic, payload, sender = bus.receive()
      if topic == "alert.sync" then
        for kind, message in pairs(activeAlerts) do publish("alert", alertPayload(kind, message, true)) end
      elseif topic and onMessage then
        onMessage(topic, payload, sender)
      end
    end
  end
end
