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
  { type = "status", id, label, state, job, message, fuel, fuelLimit,
    alerts, progress }                    progress is { done, total, text }
                                          while a job reports it (see the
                                          progress api), absent otherwise
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
-- Each param has a name, a label for the form, a type (number, bool,
-- string or choice) and a default. Numbers may give min, max and step
-- (the small and big step of the form's buttons, default 1 and 10).
-- Choices list their options, or give optionsFor(values), a function of
-- the form's current values, when they depend on other params. Params
-- become the program's arguments in order, unless arg says which
-- argument a param is.
-- Where the chest is, for jobs that empty the turtle (see
-- inventory.ChestSides).
local chestSides = { "left", "right", "behind", "below", "above" }
-- The same, or "depot": empty at a depot's nearest dump chest instead
-- (apis/depot.lua), for the jobs that support it.
local chestOrDepot = { "left", "right", "behind", "below", "above", "depot" }
-- Which turtle side is wired to a machine, for jobs that pulse redstone
-- (see reconstruct.PulseSides).
local pulseSides = { "left", "right", "back", "top", "bottom" }

-- Where the turtle stands on the near edge of a quarry or flatten
-- footprint (excavate.Starts).
local starts = { "left", "middle", "right" }

-- The chest sides outside a quarry or flatten box (the same test as
-- excavate.chestConflict). A quarry is all below the turtle, so only
-- below is out; flatten clears the turtle's own layer, so left and
-- right depend on the width and where the turtle starts. The turtle
-- refuses the others anyway; this keeps them out of the form.
local function excavateChestSides(dir)
  return function(values)
    local width = tonumber(values.width) or 1
    local x0, x1 = 0, width - 1
    if values.start == "right" then x0, x1 = 1 - width, 0
    elseif values.start == "middle" then
      local left = math.floor((width - 1) / 2)
      x0, x1 = -left, width - 1 - left
    end
    local sides = {}
    for i, side in ipairs(chestSides) do
      local inside
      if dir == "down" then
        inside = side == "below"
      else
        inside = side == "above" or (side == "left" and -1 >= x0) or (side == "right" and 1 <= x1)
      end
      if not inside then table.insert(sides, side) end
    end
    table.insert(sides, "depot")
    return sides
  end
end

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
    { name = "chest", label = "Chest", type = "choice", options = chestOrDepot, default = "left" },
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
    { name = "start", label = "Start", type = "choice", options = starts, default = "left", arg = 5 },
    { name = "chest", label = "Chest", type = "choice", optionsFor = excavateChestSides("down"), default = "left", arg = 4 },
  } },
  { id = "flatten", name = "Flatten", program = "flatten", params = {
    { name = "width", label = "Width", type = "number", default = 8, min = 1 },
    { name = "length", label = "Length", type = "number", default = 8, min = 1 },
    { name = "height", label = "Height", type = "number", default = 4, min = 1 },
    { name = "start", label = "Start", type = "choice", options = starts, default = "left", arg = 5 },
    { name = "chest", label = "Chest", type = "choice", optionsFor = excavateChestSides("up"), default = "left", arg = 4 },
  } },
  { id = "logger", name = "Logger", program = "logger", params = {
    { name = "width", label = "Width", type = "number", default = 10, min = 1 },
    { name = "height", label = "Height", type = "number", default = 7, min = 1 },
    { name = "sapling", label = "Sapling", type = "string", default = "minecraft:oak_sapling", options = saplings },
    { name = "sleep", label = "Sleep secs", type = "number", default = 60, min = 0, step = { 10, 60 } },
    { name = "dump", label = "Dump items", type = "bool", default = true },
    { name = "chest", label = "Chest", type = "choice", options = chestSides, default = "behind" },
  } },
  { id = "reconstruct", name = "Reconstruct", program = "reconstruct", params = {
    { name = "input", label = "Input chest", type = "choice", options = chestSides, default = "behind" },
    { name = "output", label = "Output chest", type = "choice", options = chestSides, default = "right" },
    { name = "pulse", label = "Pulse side", type = "choice", options = pulseSides, default = "left" },
    { name = "stacks", label = "Stacks", type = "number", default = 0, min = 0 },
  } },
  -- Tunnel, rail, bridge, farm and lavafuel: see the programs of the
  -- same names and their engines in apis/.
  { id = "tunnel", name = "Tunnel", program = "tunnel", params = {
    { name = "length", label = "Length", type = "number", default = 32, min = 1 },
    { name = "width", label = "Width", type = "number", default = 3, min = 1, max = 5 },
    { name = "height", label = "Height", type = "number", default = 3, min = 2, max = 5 },
    { name = "torchGap", label = "Torch gap", type = "number", default = 8, min = 0 },
    { name = "chest", label = "Chest", type = "choice", options = chestSides, default = "behind" },
    { name = "returnHome", label = "Return", type = "bool", default = true },
    { name = "plug", label = "Plug lava", type = "bool", default = true },
  } },
  { id = "rail", name = "Rail", program = "rail", params = {
    { name = "length", label = "Length", type = "number", default = 64, min = 1 },
    { name = "poweredGap", label = "Powered gap", type = "number", default = 0, min = 0 },
    { name = "torchGap", label = "Torch gap", type = "number", default = 0, min = 0 },
  } },
  { id = "bridge", name = "Bridge", program = "bridge", params = {
    { name = "length", label = "Length", type = "number", default = 32, min = 1 },
    { name = "walls", label = "Walls", type = "choice", options = { "none", "rails", "walls" }, default = "none" },
    { name = "untilGround", label = "Until ground", type = "number", default = 0, min = 0 },
    { name = "block", label = "Block", type = "string", default = "any",
      options = { "any", "minecraft:cobblestone", "minecraft:oak_planks", "minecraft:stone_bricks" } },
  } },
  -- The farm's chest cannot be below (the corner crop) nor on the right
  -- of a field wider than one block (farm.chestConflict).
  { id = "farm", name = "Farm", program = "farm", params = {
    { name = "width", label = "Width", type = "number", default = 9, min = 1 },
    { name = "length", label = "Length", type = "number", default = 9, min = 1 },
    { name = "crop", label = "Sow", type = "choice", options = { "wheat", "carrots", "potatoes", "beetroots", "none" }, default = "wheat" },
    { name = "sleep", label = "Sleep secs", type = "number", default = 300, min = 0, step = { 60, 300 } },
    { name = "passes", label = "Passes", type = "number", default = 0, min = 0 },
    { name = "chest", label = "Chest", type = "choice", default = "behind", optionsFor = function(values)
      local sides = {}
      for i, side in ipairs(chestSides) do
        if side ~= "below" and (side ~= "right" or (tonumber(values.width) or 1) <= 1) then table.insert(sides, side) end
      end
      return sides
    end },
  } },
  { id = "lavafuel", name = "Lava fuel", program = "lavafuel", params = {
    { name = "target", label = "Target fuel", type = "number", default = 5000, min = 100, step = { 100, 1000 } },
    { name = "range", label = "Range", type = "number", default = 16, min = 1 },
    { name = "mode", label = "Mode", type = "choice", options = { "refuel", "depot" }, default = "refuel" },
    { name = "chest", label = "Chest", type = "choice", options = chestSides, default = "behind" },
    { name = "width", label = "Width", type = "number", default = 1, min = 1 },
  } },
  -- Coordinates are text so the keyboard can type them; facing gps
  -- finds position and facing with an existing constellation instead.
  -- Height 0 climbs as high as possible (up to y=250).
  { id = "gpsdeploy", name = "GPS deploy", program = "gpsdeploy", params = {
    { name = "x", label = "X", type = "string", default = "0" },
    { name = "y", label = "Y", type = "string", default = "64" },
    { name = "z", label = "Z", type = "string", default = "0" },
    { name = "facing", label = "Facing", type = "choice", options = { "gps", "north", "east", "south", "west" }, default = "gps" },
    { name = "height", label = "Height", type = "number", default = 0, min = 0, max = 319, step = { 10, 50 } },
  } },
  -- build: a blueprint by name (a file, or one in /blueprints such as
  -- the examples), the chest side relative to the start (or none) and
  -- whether to dig out what is in the way.
  { id = "build", name = "Build", program = "build", params = {
    { name = "file", label = "Blueprint", type = "string", default = "hut", options = { "hut", "watchtower" } },
    { name = "chest", label = "Chest", type = "choice", options = { "behind", "left", "right", "below", "above", "none" }, default = "behind" },
    { name = "clear", label = "Clear", type = "bool", default = false },
  } },
  -- goto: a position in nav's coordinates (Minecraft's once calibrated),
  -- as text so far-off coordinates can be typed.
  { id = "goto", name = "Go to", program = "goto", params = {
    { name = "x", label = "X", type = "string", default = "0" },
    { name = "y", label = "Y", type = "string", default = "64" },
    { name = "z", label = "Z", type = "string", default = "0" },
    { name = "dig", label = "Dig", type = "bool", default = false },
  } },
  -- depot: unload at the nearest dump chest, or take fuel up to the
  -- target at the nearest fuel chest, of a depot (programs/depot.lua),
  -- coming back to where the turtle was.
  { id = "depot", name = "Depot", program = "depot", params = {
    { name = "action", label = "Action", type = "choice", options = { "unload", "refuel" }, default = "unload" },
    { name = "target", label = "Fuel to", type = "number", default = 2000, min = 0, step = { 100, 1000 } },
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
-- program expects, in param order (or each param's arg position).
-- Missing values use the defaults.
function jobArgs(job, values)
  values = values or {}
  local args = {}
  for i, param in ipairs(job.params or {}) do
    local v = values[param.name]
    if v == nil then v = param.default end
    local n = param.arg or i
    if param.type == "bool" then
      args[n] = v and "true" or "false"
    else
      args[n] = tostring(v)
    end
  end
  return args
end

-- The options a choice param offers right now, given the form's values.
function paramOptions(param, values)
  if param.optionsFor then return param.optionsFor(values or {}) end
  return param.options or {}
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
-- currently needs (see the alert api). progress is the running job's
-- latest { done, total, text } from the progress api, or nil; older
-- controllers ignore it. pos is where nav thinks the turtle is, {
-- x, y, z, heading, calibrated } (Minecraft coordinates once
-- calibrated, see nav.status), or nil when it has never tracked one;
-- the dispatcher and the fleet map use it, older controllers ignore it.
function newStatus(state, jobId, message, alerts, progress, pos)
  local status = {
    type = "status",
    id = os.getComputerID(),
    label = os.getComputerLabel() or ("Turtle " .. os.getComputerID()),
    state = state,
    job = jobId,
    message = message,
    alerts = alerts or {},
  }
  if type(progress) == "table" then
    status.progress = { done = progress.done, total = progress.total, text = progress.text }
  end
  if type(pos) == "table" and tonumber(pos.x) and tonumber(pos.y) and tonumber(pos.z) then
    status.pos = { x = pos.x, y = pos.y, z = pos.z, heading = pos.heading, calibrated = pos.calibrated and true or false }
  end
  if turtle then
    status.fuel = turtle.getFuelLevel()
    status.fuelLimit = turtle.getFuelLimit()
  end
  return status
end

-- Fuel rules: ask for ("get") or change ("add" / "remove" an item name)
-- the turtle's fuel blacklist. The turtle answers with newFuelList.
function newFuelRules(action, item)
  return { type = "fuel", action = action, item = item }
end

function newFuelList(blacklist)
  local list = {}
  for i, b in ipairs(blacklist or {}) do list[i] = b end
  return { type = "fuel", blacklist = list }
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

function sendFuelRules(turtleId, action, item)
  return rednet.send(turtleId, newFuelRules(action, item), PROTOCOL)
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
