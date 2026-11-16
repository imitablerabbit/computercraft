--[[
Turtle agent runs on a turtle and lets the turtlecontrol monitor
application see and drive it. It answers discover requests, broadcasts
its status every few seconds and runs jobs from the turtlectl catalogue
when told to. A running job can be aborted with the stop command. It
also reports its inventory and selects, refuels from or drops a slot
on request so the controller can look through the turtle's items, and
passes on alerts (out of fuel, no chest, ...) raised with the alert
api so the controller can show that the turtle needs a hand, and lets
the controller see and edit the items it never burns as fuel. How far
along a job is (the progress api) goes out with the status.

The broadcast status and the alerts also go out on the bus (topics
"turtle.status" and "alert", see apis/bus.lua) for the pocket pager
and anything else listening, and a listener that asks with
"alert.sync" gets them again straight away. The turtlectl messages are
unchanged.

The status also carries where the turtle is (nav's position and
heading) once nav has tracked one, for the dispatcher and turtle
control's map. With a wireless modem and gps in range the agent puts
nav in Minecraft coordinates when it starts (the first time nav moves
one block and back to learn the heading; later gps just corrects the
position), and corrects the position after each job, since most jobs
move the turtle without nav.

Usage: turtleagent [heartbeatSeconds]
--]]

local heartbeat = 5
local args = {...}
if args[1] then heartbeat = tonumber(args[1]) or heartbeat end

if not turtlectl.openModem() then
  print("Error: no modem attached")
  return
end

local state = "idle"
local currentJob = nil
local message = nil
local pending = nil -- job table queued by the listener for the worker
local alerts = {}   -- kind -> message of help currently needed
local jobProgress = nil -- the job's latest { done, total, text } (progress api)
local progressSent = 0 -- os.clock() of the last status sent for progress
local progressEvery = 2 -- seconds between status messages for progress alone

-- Publish on the bus, never letting a bus problem stop the agent.
local function publish(topic, payload)
  if bus and bus.publish then pcall(bus.publish, topic, payload) end
end

-- Tell the bus that an alert was raised (active) or is over.
local function publishAlert(kind, text, active)
  if bus and bus.newAlert then publish("alert", bus.newAlert(kind, text, active)) end
end

-- nav's position, when nav has ever tracked one (see apis/nav.lua).
local function navStatus()
  if not (nav and nav.status and fs.exists(nav.StateFile)) then return nil end
  local ok, s = pcall(nav.status)
  return ok and s or nil
end

-- Put nav in Minecraft coordinates with gps, or correct it after a job.
-- Nothing happens (and nothing moves) without a wireless modem and gps.
local function locate(atBoot)
  if not (nav and nav.calibrate) then return end
  if not peripheral.find("modem", function(_, m) return m.isWireless and m.isWireless() end) then return end
  local s = navStatus()
  if s and s.calibrated and s.headingSure then
    pcall(nav.locate)
  elseif atBoot then
    local ok, done, x, y, z, h = pcall(nav.calibrate)
    if ok and done then print("gps: at " .. x .. " " .. y .. " " .. z .. " facing " .. nav.headingName(h)) end
  end
end

local function sendStatus(to)
  local status = turtlectl.newStatus(state, currentJob, message, alerts, jobProgress, navStatus())
  if to then
    rednet.send(to, status, turtlectl.PROTOCOL)
  else
    rednet.broadcast(status, turtlectl.PROTOCOL)
    publish("turtle.status", status)
  end
end

-- Run a shell command line with its output streamed back to whoever
-- asked for it. Returns ok, errorMessage.
local function runShell(task)
  local lines = 0
  local capture = turtlectl.newCaptureTerm(task.width or 39, function(text)
    lines = lines + 1
    if lines <= turtlectl.MaxOutputLines then
      rednet.send(task.from, turtlectl.newOutput(text), turtlectl.PROTOCOL)
    elseif lines == turtlectl.MaxOutputLines + 1 then
      rednet.send(task.from, turtlectl.newOutput("... output truncated"), turtlectl.PROTOCOL)
    end
  end)
  local previous = term.redirect(capture)
  local ok, ran = pcall(shell.run, task.command)
  capture.finish()
  term.redirect(previous)
  if ok and ran then return true end
  if ok then return false, "command failed" end
  return false, tostring(ran)
end

-- Run a job from the catalogue. Returns ok, errorMessage.
local function runJob(job, jobArgs, task)
  if job.id == "shell" then return runShell(task) end
  if job.fn then
    local ok, err = pcall(job.fn, jobArgs)
    if ok then return true end
    return false, tostring(err)
  end
  jobArgs = jobArgs or turtlectl.jobArgs(job)
  local ok, ran = pcall(shell.run, job.program, table.unpack(jobArgs))
  if ok and ran then return true end
  if ok then return false, job.program .. " failed" end
  return false, tostring(ran)
end

-- Do one move action for the controller and report how it went.
local function doMove(sender, action)
  local fn = turtlectl.moves[action]
  if not fn then
    rednet.send(sender, turtlectl.newAck(false, action, "unknown action"), turtlectl.PROTOCOL)
  elseif state == "busy" then
    rednet.send(sender, turtlectl.newAck(false, action, "busy with " .. tostring(currentJob)), turtlectl.PROTOCOL)
  else
    local ok, reason = turtle[fn]()
    if ok and state == "error" then
      state = "idle" -- the turtle is being driven by hand, clear the old failure
      message = nil
    end
    rednet.send(sender, turtlectl.newAck(ok and true or false, action, ok and "ok" or tostring(reason)), turtlectl.PROTOCOL)
    sendStatus(sender) -- fuel changed
  end
end

-- Send the inventory to whoever asked. While a job runs the slots
-- must not be selected for fuel checks, so only cached answers go out.
local function sendInventory(to)
  local items = turtleinv.scan(state ~= "busy")
  rednet.send(to, turtlectl.newInventory(items, turtle.getSelectedSlot()), turtlectl.PROTOCOL)
end

-- Select, refuel from or drop one slot for the controller.
local function doSlot(sender, action, slot)
  slot = tonumber(slot)
  if not turtlectl.slotActions[action] then
    rednet.send(sender, turtlectl.newAck(false, tostring(action), "unknown slot action"), turtlectl.PROTOCOL)
    return
  elseif not slot or slot < turtleinv.MinSlot or slot > turtleinv.MaxSlot then
    rednet.send(sender, turtlectl.newAck(false, action, "bad slot"), turtlectl.PROTOCOL)
    return
  elseif state == "busy" then
    rednet.send(sender, turtlectl.newAck(false, action, "busy with " .. tostring(currentJob)), turtlectl.PROTOCOL)
    return
  end
  local ok, reason = true, nil
  if action == "select" then
    ok = turtle.select(slot)
  else
    local selected = turtle.getSelectedSlot()
    turtle.select(slot)
    if action == "refuel" then
      ok, reason = turtle.refuel(1)
    else
      ok, reason = turtle.drop()
    end
    turtle.select(selected)
  end
  rednet.send(sender, turtlectl.newAck(ok and true or false, action, ok and ("slot " .. slot) or tostring(reason)), turtlectl.PROTOCOL)
  sendInventory(sender)
  sendStatus(sender) -- fuel may have changed
end

-- Show or change which items are never burnt as fuel.
local function doFuel(sender, msg)
  local ok, reason = true, nil
  if msg.action == "add" then
    ok = inventory.addFuelBlacklist(msg.item)
    reason = ok and ("never burning " .. tostring(msg.item)) or "already listed, or not a name"
  elseif msg.action == "remove" then
    ok = inventory.removeFuelBlacklist(msg.item)
    reason = ok and ("may burn " .. tostring(msg.item)) or "not listed"
  elseif msg.action ~= "get" then
    ok, reason = false, "unknown fuel action"
  end
  if msg.action ~= "get" then
    rednet.send(sender, turtlectl.newAck(ok, "fuel", reason), turtlectl.PROTOCOL)
  end
  rednet.send(sender, turtlectl.newFuelList(inventory.FuelBlacklist), turtlectl.PROTOCOL)
end

-- Receive commands, moves, inventory requests and discover requests.
local function listener()
  while true do
    local sender, msg = rednet.receive(turtlectl.PROTOCOL)
    if turtlectl.isMessage(msg, "discover") then
      sendStatus(sender)
    elseif turtlectl.isMessage(msg, "move") then
      doMove(sender, msg.action)
    elseif turtlectl.isMessage(msg, "inventory_request") then
      sendInventory(sender)
    elseif turtlectl.isMessage(msg, "slot") then
      doSlot(sender, msg.action, msg.slot)
    elseif turtlectl.isMessage(msg, "fuel") then
      doFuel(sender, msg)
    elseif turtlectl.isMessage(msg, "command") then
      if msg.job == "stop" then
        if state == "busy" then
          os.queueEvent("turtlectl_stop")
          rednet.send(sender, turtlectl.newAck(true, "stop", "stopping"), turtlectl.PROTOCOL)
        else
          rednet.send(sender, turtlectl.newAck(false, "stop", "nothing running"), turtlectl.PROTOCOL)
        end
      else
        local job = turtlectl.findJob(msg.job)
        if msg.job == "shell" then job = { id = "shell" } end
        if msg.job == "shell" and (type(msg.command) ~= "string" or msg.command == "") then
          rednet.send(sender, turtlectl.newAck(false, msg.job, "missing command line"), turtlectl.PROTOCOL)
        elseif not job then
          rednet.send(sender, turtlectl.newAck(false, msg.job, "unknown job"), turtlectl.PROTOCOL)
        elseif state == "busy" then
          rednet.send(sender, turtlectl.newAck(false, msg.job, "busy with " .. tostring(currentJob)), turtlectl.PROTOCOL)
        elseif job.program and not shell.resolveProgram(job.program) then
          rednet.send(sender, turtlectl.newAck(false, msg.job, "program not installed"), turtlectl.PROTOCOL)
        else
          -- Only plain strings and numbers are passed on as arguments.
          local jobArgs = nil
          if type(msg.args) == "table" then
            jobArgs = {}
            for i, v in ipairs(msg.args) do
              if type(v) ~= "string" and type(v) ~= "number" then v = tostring(v) end
              jobArgs[i] = tostring(v)
            end
          end
          pending = { job = job, args = jobArgs, from = sender,
                      command = msg.command, width = msg.width }
          state = "busy"
          currentJob = job.id
          message = msg.command
          rednet.send(sender, turtlectl.newAck(true, job.id, "starting"), turtlectl.PROTOCOL)
          sendStatus()
          os.queueEvent("turtlectl_job")
        end
      end
    end
  end
end

-- Pass alerts raised by the running program on to the controllers,
-- and keep the latest progress it reported. Progress goes out with the
-- status, at most every progressEvery seconds so a job reporting every
-- block does not flood the network.
local function alertLoop()
  while true do
    local event, kind, text, extra = os.pullEvent()
    if event == "turtle_alert" then
      alerts[kind] = text
      turtlectl.broadcastAlert(kind, text, true)
      publishAlert(kind, text, true)
    elseif event == "turtle_alert_clear" and alerts[kind] then
      alerts[kind] = nil
      turtlectl.broadcastAlert(kind, nil, false)
      publishAlert(kind, nil, false)
    elseif event == "turtle_progress" and state == "busy" then
      jobProgress = { done = kind, total = text, text = extra }
      if os.clock() - progressSent >= progressEvery then
        progressSent = os.clock()
        sendStatus()
      end
    elseif event == "turtle_progress_clear" and jobProgress then
      jobProgress = nil
      sendStatus()
    end
  end
end

-- A finished job no longer needs anything.
local function clearAlerts()
  for kind in pairs(alerts) do
    turtlectl.broadcastAlert(kind, nil, false)
    publishAlert(kind, nil, false)
  end
  alerts = {}
end

-- Answer a listener on the bus that has just started (the pager) with
-- the status and every active alert. receive runs in its own function
-- under parallel, so the other loops still see every event.
local function busLoop()
  if not (bus and bus.subscribe) then return end -- an install from before the bus
  bus.subscribe("alert.sync")
  while true do
    local topic = bus.receive()
    if topic == "alert.sync" then
      sendStatus()
      for kind, text in pairs(alerts) do publishAlert(kind, text, true) end
    end
  end
end

-- Broadcast the status regularly so controllers notice us.
local function heartbeatLoop()
  while true do
    sendStatus()
    sleep(heartbeat)
  end
end

-- Run queued jobs one at a time. The job and a stop watcher run in
-- parallel so a stop command abandons the job coroutine.
local function worker()
  while true do
    while not pending do
      os.pullEvent("turtlectl_job")
    end
    local task = pending
    pending = nil
    print("Starting job " .. task.job.id)
    local ok, err, stopped = true, nil, false
    parallel.waitForAny(
      function() ok, err = runJob(task.job, task.args, task) end,
      function()
        os.pullEvent("turtlectl_stop")
        stopped = true
      end
    )
    if stopped then
      state = "idle"
      message = "stopped"
      print("Job " .. task.job.id .. " stopped")
    elseif ok then
      state = "idle"
      message = "finished " .. task.job.id
      print("Job " .. task.job.id .. " finished")
    else
      state = "error"
      message = err
      print("Job " .. task.job.id .. " failed: " .. tostring(err))
    end
    currentJob = nil
    jobProgress = nil
    clearAlerts()
    locate(false)
    sendStatus()
  end
end

locate(true)
print("Turtle agent " .. os.getComputerID() .. " listening on " .. turtlectl.PROTOCOL)
parallel.waitForAll(listener, heartbeatLoop, worker, alertLoop, busLoop)
