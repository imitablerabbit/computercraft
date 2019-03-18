--[[
Registry Display will print out the registry contents
--]]

--[[
Variables and command line args
--]]

local reg = registry:new()
local file -- Use registry default if args not used

-- Parse command line arguments
local args = {...}
if #args > 1 then
  print("Usage: registrydisplay [file]")
  return
elseif #args == 1 then
  file = tostring(args[1])
end

--[[
Script start
--]]

reg:loadFile(file)
reg:display()