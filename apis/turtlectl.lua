--[[
turtlectl is the shared protocol between the turtle control monitor
application (programs/turtlecontrol.lua) and the agent that runs on each
turtle (programs/turtle/turtleagent.lua). Messages are tables sent over
rednet using the PROTOCOL name.

Controller -> turtle:
  { type = "discover" }                   ask every turtle to send a status
  { type = "command", job = "<job id>",   start a job from the catalog below
    args = { ... } }                      (args optional, defaults otherwise)
  { type = "command", job = "stop" }      abort the running job

Turtle -> controller:
  { type = "status", id, label, state, job, message, fuel, fuelLimit }
  { type = "ack", ok = true|false, job, message }

state is one of idle, busy, error.
--]]

PROTOCOL = "turtlectl"

-- Catalogue of jobs that the controller can offer and the agent will run.
-- The controller only sends the job id so a turtle never runs arbitrary
-- commands. program is run through the shell with args, or fn is called
-- directly for jobs that are not standalone programs.
jobs = {
  { id = "stripmine", name = "Strip mine", program = "stripmine",
    args = { "5", "3", "64", "true", "10" } },
  { id = "mineline", name = "Mine line", program = "mineline",
    args = { "64", "true", "10" } },
  { id = "logger", name = "Logger", program = "logger", args = {} },
  { id = "refuel", name = "Refuel", fn = function() inventory.refuelAll() end },
}

-- Find a job in the catalogue by id.
function findJob(id)
  for i, job in ipairs(jobs) do
    if job.id == id then return job end
  end
  return nil
end

-- Open rednet on the first modem found. Returns true when a modem is open.
function openModem()
  if rednet.isOpen() then return true end
  local modem = peripheral.find("modem")
  if not modem then return false end
  rednet.open(peripheral.getName(modem))
  return rednet.isOpen()
end

-- Is the message one of ours?
function isMessage(message, messageType)
  if type(message) ~= "table" then return false end
  if messageType then return message.type == messageType end
  return message.type ~= nil
end

-- Message constructors so both sides agree on the fields.

function newDiscover()
  return { type = "discover" }
end

function newCommand(jobId, args)
  return { type = "command", job = jobId, args = args }
end

function newAck(ok, jobId, message)
  return { type = "ack", ok = ok, job = jobId, message = message }
end

function newStatus(state, jobId, message)
  local status = {
    type = "status",
    id = os.getComputerID(),
    label = os.getComputerLabel() or ("Turtle " .. os.getComputerID()),
    state = state,
    job = jobId,
    message = message,
  }
  if turtle then
    status.fuel = turtle.getFuelLevel()
    status.fuelLimit = turtle.getFuelLimit()
  end
  return status
end

-- Senders

function sendCommand(turtleId, jobId, args)
  return rednet.send(turtleId, newCommand(jobId, args), PROTOCOL)
end

function broadcastDiscover()
  rednet.broadcast(newDiscover(), PROTOCOL)
end
