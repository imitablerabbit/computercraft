--[[
Register will register the current computer to the
registry defined by the registry ID passed in as a
command line argument. It also announces the computer on the bus
(topic "registry.join", see apis/bus.lua), which every
registrylistener in range hears, so the registry ID can be left out.

Usage: register [registryID]
--]]

--[[
Variables and command line args
--]]

local modem = peripheral.find("modem")
local port = os.getComputerID()

local args = {...}
local registry = nil
if #args > 1 or (args[1] and not tonumber(args[1])) then
  print("Usage: register [registryID]")
  return
elseif args[1] then
  registry = tonumber(args[1])
end

if not modem then
  print("Error: no modem attached")
  return
end

--[[
Functions
--]]

-- Return the type of computer as a string
function getComputerType()
  local t = "normal"
  if term.isColor() then
    t = "advanced"
  end
  if pocket then
    return t.."_pda"
  elseif turtle then
    return t.."_turtle"
  elseif commands then
    return t.."_command"
  else
    return t.."_computer"
  end
end

--[[
Script start
--]]

local id = tostring(os.getComputerID())
local cType = getComputerType()
local label = os.getComputerLabel()
if not label then label = "" end

if registry then
  local message = id..","..cType..","..label
  modem.transmit(registry, port, message)
end
if bus.publish("registry.join", { id = os.getComputerID(), label = label, kind = cType }) then
  print("Announced "..id.." ("..cType..") on the bus")
elseif not registry then
  print("Error: could not open the modem for the bus")
end
