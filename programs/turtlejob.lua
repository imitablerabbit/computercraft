--[[
Turtle job starts a job from the turtle control catalogue
(apis/turtlectl.lua) on a turtle running turtleagent, or stops the one
it is running, from a computer's shell instead of the touch dashboard.
Arguments after the job are its parameters in order, as the program
takes them; without any the job's defaults are used. It waits for the
turtle's answer and prints it.

Usage: turtlejob <turtleID> <job> [args...]
       turtlejob <turtleID> stop
--]]

local args = {...}
local id = tonumber(args[1])
if not id or not args[2] then
  print("Usage: turtlejob <turtleID> <job> [args...]")
  print("       turtlejob <turtleID> stop")
  return
end
local jobId = args[2]
if jobId ~= "stop" and not turtlectl.findJob(jobId) then
  local names = {}
  for _, job in ipairs(turtlectl.jobs) do names[#names + 1] = job.id end
  print("Unknown job " .. jobId .. ". Jobs: " .. table.concat(names, " "))
  return
end
if not turtlectl.openModem() then
  print("Error: no modem attached")
  return
end

local jobArgs = nil
if #args > 2 then
  jobArgs = {}
  for i = 3, #args do jobArgs[#jobArgs + 1] = args[i] end
end
turtlectl.sendCommand(id, jobId, jobArgs)

-- The agent acknowledges at once; anything else from it (a status)
-- is skipped.
local timer = os.startTimer(5)
while true do
  local event, sender, msg, protocol = os.pullEvent()
  if event == "timer" and sender == timer then
    print("No answer from turtle " .. id .. " (is turtleagent running?)")
    return
  elseif event == "rednet_message" and sender == id and protocol == turtlectl.PROTOCOL
      and turtlectl.isMessage(msg, "ack") then
    print((msg.ok and "OK: " or "Refused: ") .. tostring(msg.job) .. " " .. tostring(msg.message))
    return
  end
end
