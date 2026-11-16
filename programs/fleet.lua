--[[
Fleet queues a job with the dispatcher from any computer with a
wireless modem, over the bus, and lists the dispatcher's queue. It is
the shell's way into the dispatcher, for scripts, startup files and
quick tests.

  fleet add <job> [name=value ...] [at=x,y,z or at=x,y,z,heading]
            [turtle=<id|label>] [priority=n] [return=false]
  fleet list

The job is a catalogue id from apis/turtlectl.lua (quarry, stripmine,
goto ...) and name=value its parameters by name (quarry width=3
depth=2); missing ones take their defaults. at is the site the turtle
goes to first, in Minecraft coordinates, with an optional heading
(north, east, south or west) to face there. It prints the
dispatcher's answer, or that none came within 5 seconds.

Usage: fleet add <job> [name=value ...] [at=x,y,z(,heading)] [turtle=..] [priority=n]
       fleet list
--]]

local args = { ... }

local function usage()
  print("Usage: fleet add <job> [name=value ...] [at=x,y,z(,heading)]")
  print("         [turtle=<id|label>] [priority=n] [return=false]")
  print("       fleet list")
end

if not (bus and bus.open and bus.open()) then
  print("Error: no modem attached")
  return
end

-- Wait up to timeout seconds for a bus message on topic that accept()s.
local function await(topic, accept, timeout)
  bus.subscribe(topic)
  local deadline = os.clock() + timeout
  while true do
    local left = deadline - os.clock()
    if left <= 0 then return nil end
    local t, payload = bus.receive(left)
    if t == topic and type(payload) == "table" and accept(payload) then return payload end
  end
end

if args[1] == "add" and args[2] then
  local spec = { job = args[2], values = {}, ref = os.getComputerID() .. ":" .. math.random(1, 1000000) }
  for i = 3, #args do
    local name, value = args[i]:match("^([%w_]+)=(.*)$")
    if not name then
      usage()
      return
    elseif name == "at" or name == "site" then spec.site = value
    elseif name == "turtle" then spec.turtle = value
    elseif name == "priority" then spec.priority = tonumber(value)
    elseif name == "return" then spec.returnHome = value ~= "false" and value ~= "no"
    else spec.values[name] = value end
  end
  bus.publish("fleet.enqueue", spec)
  local answer = await("fleet.added", function(p) return p.ref == spec.ref end, 5)
  if not answer then error("no answer from a dispatcher", 0) end
  if not answer.ok then error("refused: " .. tostring(answer.message), 0) end
  print("queued #" .. tostring(answer.id) .. " " .. spec.job)
elseif args[1] == "list" then
  bus.publish("fleet.list", {})
  local answer = await("fleet.queue", function() return true end, 5)
  if not answer then error("no answer from a dispatcher", 0) end
  if #answer.entries == 0 then print("the queue is empty") end
  for _, e in ipairs(answer.entries) do
    print("#" .. e.id .. " " .. e.name .. " " .. fleet.siteText(e.site) .. " " .. e.state
      .. (e.turtleLabel and (" " .. e.turtleLabel) or "") .. (e.message and (": " .. e.message) or ""))
  end
else
  usage()
end
