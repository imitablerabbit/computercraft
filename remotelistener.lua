-- Remote command listener
local modem = peripheral.find("modem")
local port = os.getComputerID()

-- Setup the request listener
modem.open(port)
if not modem.isOpen(port) then
  print("Error: Unable to open modem on port "..port)
  return
end

-- Check whether the command exists. The command is
-- assumed to be the first word of the string passed in.
function messageCommandExists(message)
  local x, y = message:find("^%l+")
  if x == nil or y == nil then
    return false
  end
  local command = message:sub(x, y)
  if command == nil then
    return false
  end
  local path = shell.resolveProgram(command)
  if path == nil then
    return false
  end
  return fs.exists(path)
end

-- Listen for the remote requests
while true do
  local event, side, senderChan, replyChan, 
    message, distance = os.pullEvent("modem_message")
  print("Received: "..message)
  if messageCommandExists(message) then      
    modem.transmit(replyChan, port, tostring(true)) -- Ack true
    print("Running command "..message)
    local ok = shell.run(message)
    modem.transmit(replyChan, port, tostring(ok)) -- Command complete
    print("Finished running command "..message)
  else
    print("Warning: command "..message.."does not exist")
    modem.transmit(replyChan, port, tostring(false))
  end
end
