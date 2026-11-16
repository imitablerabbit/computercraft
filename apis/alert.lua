--[[
Alerts let a program say that a person is needed: the turtle is out of
fuel, there is no chest to empty into, the torches ran out, the
furnaces have no power, and so on. raise queues a turtle_alert event
on this computer. On a turtle, turtleagent picks those up and passes
them to turtle control, which shows the turtle in red until the alert
is cleared, and publishes them on the bus for the pocket pager.
Without the agent the alert is just printed on the turtle's screen.

On a computer that is not a turtle (a base computer, a pocket
computer) there is no agent to pass alerts on, so raise and clear also
publish them on the bus topic "alert" themselves, opening a modem if
one is attached, and the pager shows them. Without a modem the alert
is only printed, as before. An unchanged alert (or clear) is sent at
most every RepeatSeconds, so raising in a loop is fine.

Kinds are short words such as "fuel", "chest", "torches", "power";
raising the same kind again replaces the message.
--]]

-- Seconds before the same alert is published again. Programs often
-- raise or clear in a loop; repeating only the unchanged ones this
-- often keeps the network quiet and still reminds a pager that started
-- later.
RepeatSeconds = 30

local published = {} -- kind -> { active, message, at } last published

-- Publish on the bus from a plain computer. Turtles leave that to
-- turtleagent, which knows when a job ends and clears its alerts.
local function publish(kind, message, active)
  if turtle or not bus or not bus.publish then return false end
  local last, now = published[kind], os.clock()
  if last and last.active == active and last.message == message and now - last.at < RepeatSeconds then
    return true
  end
  local ok, sent = pcall(bus.publish, "alert", bus.newAlert(kind, message, active))
  if ok and sent then published[kind] = { active = active, message = message, at = now } end
  return ok and sent
end

-- Tell whoever is watching that a person is needed.
function raise(kind, message)
  message = message or kind
  print("Needs help: " .. message)
  os.queueEvent("turtle_alert", kind, message)
  publish(kind, message, true)
end

-- The problem went away.
function clear(kind)
  os.queueEvent("turtle_alert_clear", kind)
  publish(kind, nil, false)
end
