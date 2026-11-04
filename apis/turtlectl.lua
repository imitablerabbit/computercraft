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
  { type = "command", job = "shell",      run a shell command line and send
    command = "ls /", width = 39 }        its output back, wrapped at width
  { type = "move", action = "forward" }   one step or action from moves below

Turtle -> controller:
  { type = "status", id, label, state, job, message, fuel, fuelLimit }
  { type = "ack", ok = true|false, job, message }
  { type = "output", text = "one line" }  a line printed by a shell command

state is one of idle, busy, error.
--]]

PROTOCOL = "turtlectl"

-- Catalogue of jobs that the controller can offer and the agent will run.
-- The controller only sends the job id and argument values so a turtle
-- never runs arbitrary commands. program is run through the shell with
-- one argument per entry of params, in order, or fn is called directly
-- for jobs that are not standalone programs.
--
-- Each param has a name, a label for the form, a type (number, bool or
-- string) and a default. Numbers may give min, max and step (the small
-- and big step of the form's buttons, default 1 and 10).
-- Where the chest is, for jobs that empty the turtle (see
-- inventory.ChestSides).
local chestSides = { "left", "right", "behind", "below", "above" }

-- Saplings the logger form offers; any other name can still be typed.
local saplings = {
  "minecraft:oak_sapling", "minecraft:spruce_sapling", "minecraft:birch_sapling",
  "minecraft:jungle_sapling", "minecraft:acacia_sapling", "minecraft:dark_oak_sapling",
  "minecraft:cherry_sapling", "minecraft:pale_oak_sapling", "minecraft:mangrove_propagule",
  "minecraft:sapling", "ic2:sapling",
}

jobs = {
  { id = "stripmine", name = "Strip mine", program = "stripmine", params = {
    { name = "mines", label = "Mines", type = "number", default = 5, min = 1 },
    { name = "sep", label = "Gap", type = "number", default = 3, min = 1 },
    { name = "length", label = "Length", type = "number", default = 64, min = 1 },
    { name = "torches", label = "Torches", type = "bool", default = true },
    { name = "torchDistance", label = "Torch gap", type = "number", default = 10, min = 1 },
    { name = "chest", label = "Chest", type = "choice", options = chestSides, default = "left" },
  } },
  { id = "mineline", name = "Mine line", program = "mineline", params = {
    { name = "length", label = "Length", type = "number", default = 64, min = 1 },
    { name = "torches", label = "Torches", type = "bool", default = true },
    { name = "torchDistance", label = "Torch gap", type = "number", default = 10, min = 1 },
    { name = "returnHome", label = "Return", type = "bool", default = false },
  } },
  { id = "quarry", name = "Quarry", program = "quarry", params = {
    { name = "width", label = "Width", type = "number", default = 8, min = 1 },
    { name = "length", label = "Length", type = "number", default = 8, min = 1 },
    { name = "depth", label = "Depth", type = "number", default = 8, min = 1 },
    { name = "chest", label = "Chest", type = "choice", options = { "left", "right", "behind", "above" }, default = "left" },
  } },
  { id = "flatten", name = "Flatten", program = "flatten", params = {
    { name = "width", label = "Width", type = "number", default = 8, min = 1 },
    { name = "length", label = "Length", type = "number", default = 8, min = 1 },
    { name = "height", label = "Height", type = "number", default = 4, min = 1 },
    { name = "chest", label = "Chest", type = "choice", options = { "left", "behind", "below" }, default = "left" },
  } },
  { id = "logger", name = "Logger", program = "logger", params = {
    { name = "width", label = "Width", type = "number", default = 10, min = 1 },
    { name = "height", label = "Height", type = "number", default = 7, min = 1 },
    { name = "sapling", label = "Sapling", type = "string", default = "minecraft:oak_sapling", options = saplings },
    { name = "sleep", label = "Sleep secs", type = "number", default = 60, min = 0, step = { 10, 60 } },
    { name = "dump", label = "Dump items", type = "bool", default = true },
    { name = "chest", label = "Chest", type = "choice", options = chestSides, default = "behind" },
  } },
  { id = "refuel", name = "Refuel", fn = function() inventory.refuelAll() end },
}

-- The default value of every param of a job, by param name.
function jobDefaults(job)
  local values = {}
  for i, param in ipairs(job.params or {}) do
    values[param.name] = param.default
  end
  return values
end

-- Turn a table of values by param name into the string arguments the
-- program expects, in param order. Missing values use the defaults.
function jobArgs(job, values)
  values = values or {}
  local args = {}
  for i, param in ipairs(job.params or {}) do
    local v = values[param.name]
    if v == nil then v = param.default end
    if param.type == "bool" then
      args[i] = v and "true" or "false"
    else
      args[i] = tostring(v)
    end
  end
  return args
end

-- Actions the move screen can ask for, mapped to turtle functions. Each
-- is a single step or action; the agent only runs them while idle.
moves = {
  forward = "forward", back = "back", up = "up", down = "down",
  left = "turnLeft", right = "turnRight",
  dig = "dig", digUp = "digUp", digDown = "digDown",
  place = "place", placeUp = "placeUp", placeDown = "placeDown",
  suck = "suck", drop = "drop",
}

-- Most lines of output a single shell command may send back.
MaxOutputLines = 200

-- Actions the inventory screen can ask for on one slot. The agent
-- only runs them while idle.
slotActions = { select = true, refuel = true, drop = true }

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

function newMove(action)
  return { type = "move", action = action }
end

function newOutput(text)
  return { type = "output", text = text }
end

-- Ask a turtle for its inventory; it answers with an inventory message.
function newInventoryRequest()
  return { type = "inventory_request" }
end

-- items is slot -> item from turtleinv.scan, selected the selected slot.
function newInventory(items, selected)
  return { type = "inventory", items = items, selected = selected }
end

function newSlotAction(action, slot)
  return { type = "slot", action = action, slot = slot }
end

-- alerts is a table of kind -> message for the help the turtle
-- currently needs (see the alert api).
function newStatus(state, jobId, message, alerts)
  local status = {
    type = "status",
    id = os.getComputerID(),
    label = os.getComputerLabel() or ("Turtle " .. os.getComputerID()),
    state = state,
    job = jobId,
    message = message,
    alerts = alerts or {},
  }
  if turtle then
    status.fuel = turtle.getFuelLevel()
    status.fuelLimit = turtle.getFuelLimit()
  end
  return status
end

-- A turtle needs help (active) or no longer does.
function newAlert(kind, message, active)
  return { type = "alert", id = os.getComputerID(), kind = kind, message = message, active = active and true or false }
end

-- Senders

function broadcastAlert(kind, message, active)
  rednet.broadcast(newAlert(kind, message, active), PROTOCOL)
end

function sendCommand(turtleId, jobId, args)
  return rednet.send(turtleId, newCommand(jobId, args), PROTOCOL)
end

function broadcastDiscover()
  rednet.broadcast(newDiscover(), PROTOCOL)
end

function sendMove(turtleId, action)
  return rednet.send(turtleId, newMove(action), PROTOCOL)
end

function requestInventory(turtleId)
  return rednet.send(turtleId, newInventoryRequest(), PROTOCOL)
end

function sendSlotAction(turtleId, action, slot)
  return rednet.send(turtleId, newSlotAction(action, slot), PROTOCOL)
end

-- Ask the turtle to run a command line. width is the number of columns
-- the controller can show so output wraps to fit.
function sendShell(turtleId, command, width)
  local msg = newCommand("shell")
  msg.command = command
  msg.width = width
  return rednet.send(turtleId, msg, PROTOCOL)
end

-- A terminal object that is one line high. Everything written to it is
-- handed to onLine as soon as the line is finished (print scrolls it
-- off), so output of a program redirected here streams line by line.
function newCaptureTerm(width, onLine)
  local line, cx = "", 1
  local t = {}
  local function flush()
    onLine((line:gsub("%s+$", "")))
    line, cx = "", 1
  end
  t.write = function(s)
    s = tostring(s)
    if #line < cx - 1 then line = line .. string.rep(" ", cx - 1 - #line) end
    line = line:sub(1, cx - 1) .. s .. line:sub(cx + #s)
    cx = cx + #s
  end
  t.blit = function(s) t.write(s) end
  t.scroll = function(n)
    for i = 1, math.max(1, n or 1) do flush() end
  end
  t.getSize = function() return width, 1 end
  t.getCursorPos = function() return cx, 1 end
  t.setCursorPos = function(x, y) cx = math.max(1, math.floor(x)) end
  t.clear = function() line, cx = "", 1 end
  t.clearLine = t.clear
  t.setCursorBlink = function() end
  t.isColor = function() return false end
  t.isColour = t.isColor
  t.setTextColor = function() end
  t.setTextColour = t.setTextColor
  t.setBackgroundColor = function() end
  t.setBackgroundColour = t.setBackgroundColor
  t.getTextColor = function() return colors.white end
  t.getTextColour = t.getTextColor
  t.getBackgroundColor = function() return colors.black end
  t.getBackgroundColour = t.getBackgroundColor
  t.getPaletteColor = function() return 0, 0, 0 end
  t.getPaletteColour = t.getPaletteColor
  t.setPaletteColor = function() end
  t.setPaletteColour = t.setPaletteColor
  -- Send whatever is left on the current line, if anything.
  t.finish = function()
    if line ~= "" then flush() end
  end
  return t
end
