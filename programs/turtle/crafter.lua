--[[
Crafter crafts for the storage program. Put a crafty turtle (one with
a crafting table equipped) beside the storage's crafting chest, with
the chest in front of it, on top of it or below it, and run crafter.
The storage computer moves a recipe's ingredients into the chest and
asks over the bus; the turtle takes them, crafts, and puts what it made
back in the chest, where the storage puts it away. See
apis/crafting.lua.

The turtle needs a modem the storage computer can reach: a wireless
one (with a wireless modem on the storage computer too), or a wired
modem block touching it on the storage cable. Nothing else may be in
the turtle; it puts whatever it holds in the chest when it starts.

Usage: crafter [front|top|bottom]
--]]

local args = { ... }
local station, err = crafting.turtleIO(args[1])
if not station then
  print("Error: " .. err)
  print("Usage: crafter [front|top|bottom]")
  return
end
if not bus.open() then
  print("Error: no modem. The crafter needs a modem the storage computer can reach.")
  return
end

local id = os.getComputerID()
local function say(text)
  local t = textutils.formatTime(os.time(), true)
  print(("[%s] %s"):format(t, text))
end

local function hello(busy)
  bus.publish("base.craft.hello", { id = id, label = os.getComputerLabel(), busy = busy and true or false })
end

if not crafting.emptyInto(station) then say("Could not put everything in the chest.") end
bus.subscribe("base.craft.job")
bus.subscribe("base.craft.ping")
say("Crafting from the chest " .. (station.side == "front" and "in front" or station.side == "top" and "above" or "below") .. ".")
hello(false)

local lastHello = os.clock()
while true do
  local topic, payload, sender = bus.receive(30)
  if topic == "base.craft.ping" then
    hello(false)
    lastHello = os.clock()
  elseif topic == "base.craft.job" and type(payload) == "table" and (payload.to == nil or payload.to == id) then
    say("Crafting " .. tostring(payload.crafts) .. "x " .. tostring(payload.name or "?") .. " for " .. tostring(sender))
    hello(true)
    local result = crafting.runJob(payload, station)
    result.jobId = payload.jobId
    result.to = sender
    bus.publish("base.craft.done", result)
    if result.ok then
      local out = result.output
      say("Made " .. crafting.itemsFrom({ output = out }, result.crafted) .. " " .. (out and (out.displayName or out.name) or "items"))
    else
      say("Stopped after " .. result.crafted .. ": " .. tostring(result.why))
    end
    hello(false)
    lastHello = os.clock()
  end
  if os.clock() - lastHello >= 30 then
    hello(false)
    lastHello = os.clock()
  end
end
