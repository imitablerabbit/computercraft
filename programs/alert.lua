--[[
Alert raises or clears an alert from the shell, through the alert api.
On a computer that is not a turtle it goes out on the bus, so the
pocket pager shows it; on a turtle running turtleagent the agent
passes it on. Handy in scripts and startup files of base computers,
and for trying the pager.

Usage: alert <kind> <message...>
       alert clear <kind>
--]]

local args = {...}
if #args < 1 or (args[1] == "clear" and #args ~= 2) then
  print("Usage: alert <kind> <message...>")
  print("       alert clear <kind>")
  return
end

if args[1] == "clear" then
  alert.clear(args[2])
  print("Cleared " .. args[2])
else
  local kind = args[1]
  local message = table.concat(args, " ", 2)
  if message == "" then message = nil end
  alert.raise(kind, message)
end
