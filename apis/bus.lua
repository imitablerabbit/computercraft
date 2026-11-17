--[[
The bus is a shared message channel over rednet for everything in the
base: turtles say how they are, base computers raise alerts, the pocket
pager listens to all of it. A message has a topic (a short dotted name
such as "turtle.status" or "alert") and a payload (any table, string or
number rednet can carry), and goes to every computer in range with the
bus open. Nobody has to know who is listening, so new listeners (a
pager, a log, a dashboard) need no change to the programs that publish.

  bus.open()                          rednet on a modem, false if none
  bus.publish("alert", { ... })       broadcast a message
  bus.subscribe("turtle.*")           topics this computer wants
  local topic, payload, from = bus.receive(5)   next one, nil after 5 s

Messages travel as { topic, payload, from = computer id, label } on the
rednet protocol "bus". A pattern is a whole topic ("alert") or a prefix
ending in * ("turtle.*" matches "turtle.status"; "*" matches all).

Topics in use:
  turtle.status  a turtle's status, the same table turtle control gets
                 (turtlectl.newStatus: id, label, state, job, message,
                 fuel, fuelLimit, alerts, progress); every 5 seconds
                 from turtleagent
  alert          { id, source, kind, message, active } for anything a
                 person should look at; active false when it is over
  alert.sync     a listener that just started asks for the alerts that
                 are active; programs that keep alerts answer by
                 publishing them again (turtleagent does)
  registry.join  { id, label, kind } from the register program
  base.*         base automation; fleet.* the dispatcher

receive pulls events until a bus message for a subscribed topic comes
in, so like rednet.receive it throws away other events. Run it in its
own function under parallel (each function there sees every event, so
nothing is lost for the others), or, in a program with its own
os.pullEvent loop, pass every event to handle instead:

  while true do
    local event = table.pack(os.pullEvent())
    local topic, payload, from = bus.handle(table.unpack(event, 1, event.n))
    if topic == "alert" then ... end
    -- the program's own events as before
  end

Subscriptions belong to the computer, not the program (the API is
loaded once and shared), so a program should still check the topic it
gets back. Rednet does not hand a computer its own broadcasts, so a
computer does not hear what it publishes itself.
--]]

PROTOCOL = "bus"

-- pattern -> true
local subscriptions = {}

local function isModem(name)
  if peripheral.hasType then return peripheral.hasType(name, "modem") == true end
  return peripheral.getType(name) == "modem"
end

-- Open rednet so the bus can be used. Uses a wireless (or ender) modem
-- when there is one, since the bus is meant to reach across the base,
-- otherwise the first modem. Returns true when rednet is open.
function open()
  local first, wireless = nil, nil
  for _, name in ipairs(peripheral.getNames()) do
    if isModem(name) then
      first = first or name
      if not wireless and peripheral.call(name, "isWireless") then wireless = name end
    end
  end
  local name = wireless or first
  if not name then return rednet.isOpen() end
  if not rednet.isOpen(name) then rednet.open(name) end
  return rednet.isOpen(name)
end

-- Is rednet open on any modem?
function isOpen()
  return rednet.isOpen()
end

local function checkTopic(topic, what)
  if type(topic) ~= "string" or topic == "" then
    error("bus: " .. (what or "topic") .. " must be a non-empty string, got " .. tostring(topic), 3)
  end
end

-- The table that goes over rednet.
function newMessage(topic, payload)
  return { topic = topic, payload = payload, from = os.getComputerID(), label = os.getComputerLabel() }
end

-- Is this something that came over the bus? Anything else on the
-- protocol (or a broken message) is ignored.
function isMessage(message)
  return type(message) == "table" and type(message.topic) == "string" and message.topic ~= ""
end

-- Send a message to every computer listening. Opens a modem first if
-- rednet is not open yet. Returns false when there is no modem.
function publish(topic, payload)
  checkTopic(topic)
  if not rednet.isOpen() and not open() then return false end
  rednet.broadcast(newMessage(topic, payload), PROTOCOL)
  return true
end

-- Does pattern (a topic, or a prefix ending in *) match topic?
function matches(pattern, topic)
  if type(pattern) ~= "string" or type(topic) ~= "string" then return false end
  if pattern:sub(-1) == "*" then
    local prefix = pattern:sub(1, -2)
    return topic:sub(1, #prefix) == prefix
  end
  return pattern == topic
end

-- Ask for messages on topics matching pattern.
function subscribe(pattern)
  checkTopic(pattern, "pattern")
  subscriptions[pattern] = true
end

-- Stop asking for pattern; with no pattern, for everything.
function unsubscribe(pattern)
  if pattern == nil then
    subscriptions = {}
  else
    subscriptions[pattern] = nil
  end
end

-- Is some subscription matching topic?
function isSubscribed(topic)
  for pattern in pairs(subscriptions) do
    if matches(pattern, topic) then return true end
  end
  return false
end

-- The patterns subscribed to, sorted.
function getSubscriptions()
  local list = {}
  for pattern in pairs(subscriptions) do list[#list + 1] = pattern end
  table.sort(list)
  return list
end

-- Given an os.pullEvent result, return topic, payload, senderId (and
-- the whole message, for its label) when it is a bus message on a
-- subscribed topic, otherwise nil. The sender is the rednet sender,
-- which is the computer that really sent it.
function handle(event, sender, message, protocol)
  if event ~= "rednet_message" or protocol ~= PROTOCOL then return nil end
  if not isMessage(message) or not isSubscribed(message.topic) then return nil end
  return message.topic, message.payload, sender, message
end

-- Wait for the next bus message on a subscribed topic. Returns topic,
-- payload, senderId (and the message), or nil once timeout seconds
-- have passed (no timeout waits for ever). Other events are dropped:
-- see the top of this file.
function receive(timeout)
  if timeout ~= nil and type(timeout) ~= "number" then
    error("bus: timeout must be a number of seconds, got " .. tostring(timeout), 2)
  end
  local timer = timeout and os.startTimer(timeout)
  while true do
    local event = table.pack(os.pullEvent())
    if event[1] == "timer" and event[2] == timer then return nil end
    local topic, payload, sender, message = handle(table.unpack(event, 1, event.n))
    if topic then
      if timer then os.cancelTimer(timer) end
      return topic, payload, sender, message
    end
  end
end

-- An alert payload, for publishing on "alert". source is the label
-- people know this computer by.
function newAlert(kind, message, active)
  return {
    id = os.getComputerID(),
    source = os.getComputerLabel() or ((turtle and "Turtle " or "Computer ") .. os.getComputerID()),
    kind = kind,
    message = message,
    active = active and true or false,
  }
end
