--[[
Alerts let a program say that the turtle needs a hand: it is out of
fuel, there is no chest to empty into, the torches ran out, and so on.
raise queues a turtle_alert event on this computer. turtleagent picks
those up and passes them to turtle control, which shows the turtle in
red until the alert is cleared. Without the agent the alert is just
printed on the turtle's screen.

Kinds are short words such as "fuel", "chest", "torches", "saplings";
raising the same kind again replaces the message.
--]]

-- Tell whoever is watching that the turtle needs help.
function raise(kind, message)
  message = message or kind
  print("Needs help: " .. message)
  os.queueEvent("turtle_alert", kind, message)
end

-- The problem went away.
function clear(kind)
  os.queueEvent("turtle_alert_clear", kind)
end
