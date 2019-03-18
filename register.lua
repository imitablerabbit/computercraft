--[[
Register will register the current computer to the
registry defined by the registry ID passed in as a
command line argument.
--]]

--[[
Variables and command line args
--]]

local modem = peripheral.find("modem")
local port = os.getComputerID()

local args = {...}
if #args < 1 then
  print("Usage: register registryID")
  return
end

local registry = tonumber(args[1])

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

local message = id..","..cType..","..label
modem.transmit(registry, port, message)
