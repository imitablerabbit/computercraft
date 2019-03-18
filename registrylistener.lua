--[[
Registry Listener will create a registry and wait for
register messages from other computers. When it receives
a register message it will save it in the registry file
and update the display.
--]]

--[[
Variables and command line args
--]]

local modem = peripheral.find("modem")
local port = os.getComputerID()
local reg = registry:new()
local file = "registry_store.dat"

-- Parse command line arguments
local args = {...}
if #args > 1 then
  print("Usage: registrylistener [file]")
  return
elseif #args == 1 then
  file = tostring(args[1])
end

--[[
Functions
--]]

-- Clears the screen and displays the registry.
function printRegistry(r)
  term.clear()
  term.setCursorPos(1, 1)
  r:display()
end

--[[
Script start
--]]

-- Load the registry if we already have one.
reg:loadFile(file)
printRegistry(reg)

modem.open(port)
if not modem.isOpen(port) then
  print("Error: Unable to open modem on port "..port)
  return
end

while true do
  local event, side, senderChan, replyChan, 
    message, distance = os.pullEvent("modem_message")
  print("Received: "..message)
  
  fields = {}
  for field in string.gmatch(message, '([^,]+)') do
      table.insert(fields, field)
  end
  
  print("Registering...")
  reg:register(unpack(fields))
  
  print("Saving registry...")
  reg:saveFile(file)
  
  print("Printing regitry...")
  printRegistry(reg)
end