--[[
Remote command sender will send commands to worker computers.
A worker computer must be running the remotelister.lua command
and have a modem correctly connected.
--]]

-- Send remote command to turtle
local modem = peripheral.find("modem")
local port = os.getComputerID()
local ackTimeout = 3

-- Parse command line arguments
local args = {...}
if #args < 2 then
  print("Usage: remotecommand computerID command [args]")
  return
end

local remotePort = tonumber(args[1])
local command = args[2]
for i=3, #args do
  command = command .. " " .. args[i]
end
print("Sending command: "..command)

-- Setup the response receiver
modem.open(port)
if not modem.isOpen(port) then
  print("Error: Unable to open modem on port "..port)
  return
end

-- Send the command to the remote turtle
local timer = os.startTimer(ackTimeout)
modem.transmit(remotePort, port, command)

-- Wait for the ack back or a timeout
local ack
while true do
  local event, p1, p2, p3, p4, p5 = os.pullEvent()
  if event == "modem_message" and p3 == remotePort then
    ack = p4
    break
  elseif event == "timer" and p1 == timer then
    print("Error: didnt reveive an ack back before timeout")
    return
  end
end

if ack == "true" then
  print("Info: received ack back, worker now running command")
elseif ack == "false" then
  print("Error: worker unable to run the command")
  return
end

-- Wait for the finished message from the worker. Other systems
-- should not be sending messages while we run this so fuck em.
while true do
  local event, side, senderChan, replyChan, 
    message, distance = os.pullEvent("modem_message")
  if replyChan == remotePort then
    break
  end
end
