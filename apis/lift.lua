--[[
Lift is the dispatcher behind the lift program: one vehicle (an
elevator car, a train) serving a line of stops, all driven by
redstone. Each stop has a call input (a button at that floor wired back
to the computer), a send output (the redstone that sends the vehicle
there, such as a Create elevator contact or a train station's redstone
link) and, optionally, an arrived input (a contact that is on while the
vehicle is at that stop). Signals are a side ("left") or a side and a
bundled cable colour ({ side = "back", color = "white" }).

  local d = lift.new(config)
  d:call(3)                 -- someone pressed the button at stop 3
  d:arrive(3)               -- stop 3's arrived input came on
  local events = d:update() -- dispatch, time out pulses, assume arrivals
  circuits.writeOutputs(d:outputs())

Calls are queued once each. The next stop is picked by the config's
algorithm:

  fifo  in the order they were called
  look  the nearest call in the direction of travel, turning round when
        there is nothing more ahead (what elevators do)
  scan  like look, but runs on to the end of the line before turning
        round

The vehicle is sent to one stop at a time. A send output is pulsed for
config.pulse seconds, or with config.hold kept on until the vehicle is
sent somewhere else (for contacts that must stay powered). Where the
vehicle is comes from the arrived inputs; a stop without one is assumed
reached config.travel seconds per stop after it was sent. A trip to a
stop with an arrived input that does not arrive within config.timeout
seconds is reported lost (an alert), and the vehicle is assumed there.
After arriving the vehicle waits config.dwell seconds before the next
trip.

new(config, opts): opts.clock replaces os.clock, for the tests.
--]]

Algorithms = { "look", "fifo", "scan" }

DefaultConfig = {
  algorithm = "look",
  hold = false,
  pulse = 1,
  travel = 4,
  dwell = 3,
  timeout = 60,
  stops = {
    { name = "Ground", call = { side = "left", color = "white" }, send = { side = "back", color = "white" } },
    { name = "Top", call = { side = "left", color = "orange" }, send = { side = "back", color = "orange" } },
  },
}

ConfigFile = "/lift.cfg"

local function copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end

function loadConfig(path)
  path = path or ConfigFile
  local config = copy(DefaultConfig)
  if fs.exists(path) then
    local h = fs.open(path, "r")
    local data = h and textutils.unserialize(h.readAll() or "")
    if h then h.close() end
    if type(data) == "table" then
      for k, v in pairs(data) do config[k] = v end
      return config, false
    end
  end
  saveConfig(config, path)
  return config, true
end

function saveConfig(config, path)
  local h = fs.open(path or ConfigFile, "w")
  if not h then return false end
  h.write(textutils.serialize(config))
  h.close()
  return true
end

--[[
Choosing the next stop
--]]

-- The stop to go to next from position (moving in direction 1 up the
-- list or -1 down it) for the queued stops, and the direction to go
-- in. Returns nil when the queue is empty.
function choose(algorithm, position, direction, queue, stopCount)
  if #queue == 0 then return nil, direction end
  direction = direction or 1
  if algorithm == "fifo" then
    local t = queue[1]
    return t, t > position and 1 or (t < position and -1 or direction)
  end
  local function nearest(dir)
    local best
    for _, s in ipairs(queue) do
      if (s - position) * dir > 0 and (not best or math.abs(s - position) < math.abs(best - position)) then best = s end
    end
    return best
  end
  for _, s in ipairs(queue) do if s == position then return s, direction end end
  local ahead = nearest(direction)
  if ahead then return ahead, direction end
  if algorithm == "scan" then
    -- run on to the end of the line before turning round
    local finish = direction > 0 and stopCount or 1
    if position ~= finish then return finish, direction end
  end
  local back = nearest(-direction)
  return back, -direction
end

--[[
The dispatcher
--]]

local Dispatcher = {}
Dispatcher.__index = Dispatcher

function new(config, opts)
  opts = opts or {}
  return setmetatable({
    config = config,
    clock = opts.clock or os.clock,
    position = 1,
    direction = 1,
    state = "idle",     -- idle, moving or dwell
    queue = {},
    target = nil,
    departed = nil,
    sending = nil,      -- stop whose send output is on
    sendUntil = nil,
    dwellUntil = nil,
    events = {},
  }, Dispatcher)
end

function Dispatcher:stops()
  return self.config.stops
end

function Dispatcher:name(i)
  local s = self.config.stops[i]
  return s and s.name or ("stop " .. tostring(i))
end

-- A stop by number or name (or the start of a name). Returns the index.
function Dispatcher:find(text)
  local n = tonumber(text)
  if n and self.config.stops[n] then return n end
  text = tostring(text or ""):lower()
  for i, s in ipairs(self.config.stops) do if s.name:lower() == text then return i end end
  for i, s in ipairs(self.config.stops) do if s.name:lower():find(text, 1, true) == 1 then return i end end
  return nil
end

function Dispatcher:isQueued(i)
  for _, s in ipairs(self.queue) do if s == i then return true end end
  return false
end

function Dispatcher:emit(kind, stop, extra)
  local e = { event = kind, stop = stop, name = stop and self:name(stop) }
  for k, v in pairs(extra or {}) do e[k] = v end
  self.events[#self.events + 1] = e
  return e
end

-- Someone wants the vehicle at stop i. Returns true, or false and why.
function Dispatcher:call(i)
  if not self.config.stops[i] then return false, "no stop " .. tostring(i) end
  if self:isQueued(i) then return false, self:name(i) .. " is already called" end
  if self.state ~= "moving" and self.position == i then return false, "already at " .. self:name(i) end
  if self.state == "moving" and self.target == i then return false, "already on its way to " .. self:name(i) end
  self.queue[#self.queue + 1] = i
  self:emit("call", i)
  return true
end

-- Take a stop out of the queue (it was served, or the call cancelled).
function Dispatcher:unqueue(i)
  for k = #self.queue, 1, -1 do
    if self.queue[k] == i then table.remove(self.queue, k) end
  end
end

-- Stop i's arrived input came on (or the travel time ran out).
function Dispatcher:arrive(i, assumed)
  if not self.config.stops[i] then return end
  local was = self.position
  self.position = i
  if self.state == "moving" and i == self.target then
    self.state = "dwell"
    self.dwellUntil = self.clock() + (self.config.dwell or 0)
    self:unqueue(i)
    self:emit("arrive", i, { assumed = assumed })
  elseif self.state == "moving" then
    self:emit("pass", i)
  elseif was ~= i then
    -- moved without being sent (by hand, another controller)
    self:unqueue(i)
    self:emit("arrive", i, { unexpected = true })
  end
end

function Dispatcher:hasArrivalInput(i)
  local s = self.config.stops[i]
  return s and s.arrived and s.arrived.side ~= nil
end

-- Move time on: assume arrivals, end the dwell and pulses, and send the
-- vehicle on to the next stop. Returns the events since the last call.
function Dispatcher:update()
  local now = self.clock()
  local cfg = self.config
  if self.state == "moving" then
    if self:hasArrivalInput(self.target) then
      if now - self.departed >= (cfg.timeout or 60) then
        self:emit("lost", self.target)
        self:arrive(self.target, true)
      end
    elseif now >= self.etaAt then
      self:arrive(self.target, true)
    end
  end
  if self.state == "dwell" and now >= self.dwellUntil then
    self.state = "idle"
    if #self.queue == 0 then self:emit("idle", self.position) end
  end
  if self.state == "idle" and #self.queue > 0 then
    local target, dir = choose(cfg.algorithm, self.position, self.direction, self.queue, #cfg.stops)
    if target == self.position then
      -- called to where it already is: nothing to send
      self:unqueue(target)
      self:emit("arrive", target, { already = true })
      self.state = "dwell"
      self.dwellUntil = now + (cfg.dwell or 0)
    elseif target then
      self.direction = dir
      self.target = target
      self:unqueue(target) -- it is the destination now, not a waiting call
      self.state = "moving"
      self.departed = now
      self.etaAt = now + (cfg.travel or 4) * math.abs(target - self.position)
      self.sending = target
      self.sendUntil = (not cfg.hold) and (now + (cfg.pulse or 1)) or nil
      self:emit("dispatch", target, { from = self.position })
    end
  end
  if self.sending and self.sendUntil and now >= self.sendUntil then
    self.sending = nil
    self.sendUntil = nil
  end
  local events = self.events
  self.events = {}
  return events
end

-- The send outputs: { side, color, on } for every stop that has one.
function Dispatcher:outputs()
  local list = {}
  for i, s in ipairs(self.config.stops) do
    if s.send and s.send.side then
      list[#list + 1] = { side = s.send.side, color = s.send.color, on = self.sending == i }
    end
  end
  return list
end

-- Seconds until the vehicle is expected (nil when not moving).
function Dispatcher:eta()
  if self.state ~= "moving" or not self.etaAt then return nil end
  return math.max(0, self.etaAt - self.clock())
end

-- A line saying where the vehicle is and what it is doing.
function Dispatcher:describe()
  if self.state == "moving" then
    return "moving " .. self:name(self.position) .. " -> " .. self:name(self.target)
  elseif self.state == "dwell" then
    return "at " .. self:name(self.position) .. " (doors open)"
  end
  return "at " .. self:name(self.position)
end

-- Check a config. Returns true or nil and why.
function validate(config)
  if type(config.stops) ~= "table" or #config.stops < 2 then return nil, "a lift needs at least two stops" end
  local okAlg = false
  for _, a in ipairs(Algorithms) do if config.algorithm == a then okAlg = true end end
  if not okAlg then return nil, "algorithm must be look, fifo or scan" end
  for i, s in ipairs(config.stops) do
    if type(s.name) ~= "string" or s.name == "" then return nil, "stop " .. i .. " needs a name" end
    if not (s.send and s.send.side) then return nil, s.name .. " needs a send output" end
  end
  return true
end
