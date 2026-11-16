--[[
Registry Listener will create a registry and wait for
register messages from other computers. When it receives
a register message it will save it in the registry file
and update the display. Messages come either straight to
this computer's ID as a modem channel (register <thisID>)
or as "registry.join" on the bus (plain register), and a
computer that registers again replaces its old record.

Usage: registrylistener [file]
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

if not modem then
  print("Error: no modem attached")
  return
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

-- Add a record, or replace the one with the same computer ID.
local function upsert(r, id, kind, label)
  id = tostring(id)
  for i, record in ipairs(r.records) do
    if tostring(record[1]) == id then
      r.records[i] = { id, kind, label }
      return
    end
  end
  r:register(id, kind, label)
end

-- Save and show the registry after a change.
local function saved(r)
  print("Saving registry...")
  r:saveFile(file)
  print("Printing regitry...")
  printRegistry(r)
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
bus.open()
bus.subscribe("registry.join")

while true do
  local event = table.pack(os.pullEvent())
  local topic, payload, sender = bus.handle(table.unpack(event, 1, event.n))
  if topic == "registry.join" and type(payload) == "table" then
    local id = tonumber(payload.id) or sender
    print("Joined: "..tostring(id))
    print("Registering...")
    upsert(reg, id, tostring(payload.kind or "unknown"), tostring(payload.label or ""))
    saved(reg)
  elseif event[1] == "modem_message" and event[3] == port and type(event[5]) == "string" then
    -- Only plain register messages: rednet traffic shares this
    -- channel (it is the computer's ID) and carries tables.
    local message = event[5]
    print("Received: "..message)

    local fields = {}
    for field in string.gmatch(message, '([^,]+)') do
        table.insert(fields, field)
    end

    if fields[1] then
      print("Registering...")
      upsert(reg, fields[1], fields[2], fields[3])
      saved(reg)
    end
  end
end
