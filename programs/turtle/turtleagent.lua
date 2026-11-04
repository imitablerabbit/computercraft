--[[
Turtle agent runs on a turtle and lets the turtlecontrol monitor
application see and drive it. It answers discover requests, broadcasts
its status every few seconds and runs jobs from the turtlectl catalogue
when told to. A running job can be aborted with the stop command. It
also reports its inventory and selects, refuels from or drops a slot
on request so the controller can look through the turtle's items, and
passes on alerts (out of fuel, no chest, ...) raised with the alert
api so the controller can show that the turtle needs a hand, and lets
the controller see and edit the items it never burns as fuel.

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

local function sendStatus(to)
  local status = turtlectl.newStatus(state, currentJob, message, alerts)
  if to then
    rednet.send(to, status, turtlectl.PROTOCOL)
  else
    rednet.broadcast(status, turtlectl.PROTOCOL)
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

-- Pass alerts raised by the running program on to the controllers.
local function alertLoop()
  while true do
    local event, kind, text = os.pullEvent()
    if event == "turtle_alert" then
      alerts[kind] = text
      turtlectl.broadcastAlert(kind, text, true)
    elseif event == "turtle_alert_clear" and alerts[kind] then
      alerts[kind] = nil
      turtlectl.broadcastAlert(kind, nil, false)
    end
  end
end

-- A finished job no longer needs anything.
local function clearAlerts()
  for kind in pairs(alerts) do
    turtlectl.broadcastAlert(kind, nil, false)
  end
  alerts = {}
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
    clearAlerts()
    sendStatus()
  end
end

print("Turtle agent " .. os.getComputerID() .. " listening on " .. turtlectl.PROTOCOL)
parallel.waitForAll(listener, heartbeatLoop, worker, alertLoop)
