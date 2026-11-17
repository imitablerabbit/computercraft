--[[
Circuits are named redstone outputs (a side of the computer, or one
colour of bundled cable on a side) that the doors program switches:
lights, doors, gates, bells. Each has a mode:

  manual    on or off from the panel, remembered in the config
  schedule  on between two times of the Minecraft day (os.time()), for
            example lights on at 18:30 and off at 6:00, across midnight
  sensor    follows a redstone input (a pressure plate, a daylight
            sensor, a button), staying on for delay seconds after the
            input goes off, so a door closes 3 s after the plate is left
  pulse     on for length seconds when pressed on the panel (or when
            its input, if it has one, comes on), then off again

  local c = circuits.new(config)
  c:toggle("Hall lights")           -- the panel touched it
  local changes = c:update()        -- work out every state, set outputs
  for _, ch in ipairs(changes) do print(ch.name, ch.state, ch.reason) end

Toggling a schedule or sensor circuit overrides it until its own rule
next changes its mind (the schedule's next on or off time, the sensor's
next change), so lights switched off by hand come on again at dusk.

A circuit with invert set drives its output the other way round (an
output that is on while the circuit is off). Several circuits can share
a side when each has its own bundled colour.

new(config, opts): opts.clock (seconds, default os.clock), opts.time
(the time of day in hours, default os.time) and opts.io (the redstone
API) can be replaced, which is how the tests run it.
--]]

Modes = { "manual", "schedule", "sensor", "pulse" }

Sides = { "top", "bottom", "left", "right", "front", "back" }

-- The bundled colours by name, in the order of their values.
ColorNames = { "white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray",
               "lightGray", "cyan", "purple", "blue", "brown", "green", "red", "black" }

DefaultConfig = {
  circuits = {
    { name = "Lights", mode = "manual", output = { side = "back" } },
  },
}

ConfigFile = "/doors.cfg"

local function copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end

function loadConfig(path)
  path = path or ConfigFile
  if fs.exists(path) then
    local h = fs.open(path, "r")
    local data = h and textutils.unserialize(h.readAll() or "")
    if h then h.close() end
    if type(data) == "table" and type(data.circuits) == "table" then return data, false end
  end
  local config = copy(DefaultConfig)
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
Signals: { side = "left" } or { side = "back", color = "white" }
--]]

-- A colour name ("white", "lightBlue"), a colours value, or nil.
function colorOf(c)
  if c == nil or c == "" or c == "none" then return nil end
  if type(c) == "number" then return c end
  local v = colors[c] or (colours and colours[c])
  if type(v) == "number" then return v end
  for i, name in ipairs(ColorNames) do
    if name:lower() == tostring(c):lower() then return math.floor(2 ^ (i - 1)) end
  end
  return nil
end

function colorName(c)
  if c == nil then return nil end
  if type(c) == "string" then return c end
  for i, name in ipairs(ColorNames) do if math.floor(2 ^ (i - 1)) == c then return name end end
  return tostring(c)
end

-- Parse "back" or "back:white" into a signal, or nil and why.
function parseSignal(text)
  if type(text) == "table" then return text end
  local side, color = tostring(text or ""):match("^(%a+):?(%w*)$")
  if not side then return nil, "bad signal " .. tostring(text) end
  side = side:lower()
  local okSide = false
  for _, s in ipairs(Sides) do if s == side then okSide = true end end
  if not okSide then return nil, "no side called " .. side end
  if color ~= "" then
    if not colorOf(color) then return nil, "no colour called " .. color end
    return { side = side, color = colorName(colorOf(color)) }
  end
  return { side = side }
end

function signalText(sig)
  if not sig or not sig.side then return "-" end
  if sig.color then return sig.side .. ":" .. colorName(sig.color) end
  return sig.side
end

-- Is a signal on? A bundled colour reads that colour of the cable.
function readSignal(sig, io)
  io = io or redstone
  if not sig or not sig.side then return false end
  local c = colorOf(sig.color)
  if c then return io.testBundledInput(sig.side, c) end
  return io.getInput(sig.side)
end

-- Set outputs from a list of { side, color, on }. Plain sides are on if
-- any entry for them is on; bundled sides get the colours that are on.
-- Only the sides listed are written.
function writeOutputs(list, io)
  io = io or redstone
  local plain, bundled = {}, {}
  for _, o in ipairs(list) do
    local c = colorOf(o.color)
    if c then
      bundled[o.side] = bundled[o.side] or 0
      if o.on then bundled[o.side] = colors.combine(bundled[o.side], c) end
    else
      plain[o.side] = plain[o.side] or o.on
    end
  end
  for side, on in pairs(plain) do
    if bundled[side] == nil and io.getOutput(side) ~= on then io.setOutput(side, on) end
  end
  for side, mask in pairs(bundled) do
    if io.getBundledOutput(side) ~= mask then io.setBundledOutput(side, mask) end
  end
end

--[[
Time of day
--]]

-- "18:30" -> 18.5; numbers pass through. nil for bad input.
function parseTime(v)
  if type(v) == "number" then return v % 24 end
  local h, m = tostring(v or ""):match("^(%d+):(%d%d)$")
  if not h then
    local n = tonumber(v)
    return n and n % 24 or nil
  end
  h, m = tonumber(h), tonumber(m)
  if h > 24 or m > 59 then return nil end
  return (h + m / 60) % 24
end

function timeText(t)
  t = parseTime(t) or 0
  local h = math.floor(t)
  local m = math.floor((t - h) * 60 + 0.5)
  if m == 60 then h, m = h + 1, 0 end
  return string.format("%02d:%02d", h % 24, m)
end

-- Is now (hours) inside on..off? When off is before on the period
-- runs across midnight. Equal times mean never.
function inSchedule(now, on, off)
  now, on, off = parseTime(now), parseTime(on), parseTime(off)
  if not (now and on and off) or on == off then return false end
  if on < off then return now >= on and now < off end
  return now >= on or now < off
end

--[[
The controller
--]]

local Controller = {}
Controller.__index = Controller

function new(config, opts)
  opts = opts or {}
  local c = setmetatable({
    config = config,
    clock = opts.clock or os.clock,
    time = opts.time or os.time,
    io = opts.io or redstone,
    state = {},  -- name -> { on, override, auto, lastActive, pulseUntil, lastInput, reason }
  }, Controller)
  return c
end

function Controller:list()
  return self.config.circuits
end

function Controller:find(name)
  name = tostring(name or ""):lower()
  for i, def in ipairs(self.config.circuits) do
    if def.name:lower() == name then return def, i end
  end
  for i, def in ipairs(self.config.circuits) do
    if def.name:lower():find(name, 1, true) == 1 then return def, i end
  end
  return nil
end

function Controller:stateOf(def)
  local st = self.state[def.name]
  if not st then
    st = { on = false }
    self.state[def.name] = st
  end
  return st
end

function Controller:isOn(name)
  local def = self:find(name)
  return def and self:stateOf(def).on or false
end

-- What a circuit's own rule says now, and why.
function Controller:auto(def, st, now, input)
  local mode = def.mode
  if mode == "manual" then
    return def.state and true or false, "manual"
  elseif mode == "schedule" then
    local on = inSchedule(self.time(), def.on, def.off)
    return on, on and ("schedule until " .. timeText(def.off)) or ("schedule from " .. timeText(def.on))
  elseif mode == "sensor" then
    if input then
      st.lastActive = now
      return true, "sensor"
    end
    local delay = tonumber(def.delay) or 0
    if st.lastActive and now - st.lastActive < delay then
      return true, string.format("closing in %.0fs", delay - (now - st.lastActive))
    end
    return false, "sensor"
  elseif mode == "pulse" then
    if input and not st.lastInput then st.pulseUntil = now + (tonumber(def.length) or 1) end
    local on = st.pulseUntil ~= nil and now < st.pulseUntil
    if not on then st.pulseUntil = nil end
    return on, on and "pulse" or "ready"
  end
  return false, "unknown mode " .. tostring(mode)
end

-- Work out every circuit's state, drive the outputs and return the
-- changes as a list of { name, state, mode, reason }.
function Controller:update()
  local now = self.clock()
  local changes = {}
  for _, def in ipairs(self.config.circuits) do
    local st = self:stateOf(def)
    local input = def.input and readSignal(def.input, self.io) or false
    local auto, reason = self:auto(def, st, now, input)
    st.lastInput = input
    -- an override lasts until the rule itself changes its mind
    if st.override ~= nil and st.auto ~= nil and auto ~= st.auto then st.override = nil end
    st.auto = auto
    local on = auto
    if st.override ~= nil then
      on = st.override
      reason = "by hand"
    end
    st.reason = reason
    if on ~= st.on then
      st.on = on
      changes[#changes + 1] = { name = def.name, state = on, mode = def.mode, reason = reason }
    end
  end
  self:apply()
  return changes
end

-- Set the outputs from the current states.
function Controller:apply()
  local list = {}
  for _, def in ipairs(self.config.circuits) do
    local st = self:stateOf(def)
    if def.output and def.output.side then
      local on = st.on
      if def.invert then on = not on end
      list[#list + 1] = { side = def.output.side, color = def.output.color, on = on }
    end
  end
  writeOutputs(list, self.io)
end

-- The panel touched a circuit: flip a manual one, fire a pulse, or
-- override a schedule or sensor until its rule next changes.
function Controller:toggle(name)
  local def = self:find(name)
  if not def then return nil, "no circuit called " .. tostring(name) end
  return self:set(def.name, not self:stateOf(def).on)
end

-- Switch a circuit on or off by hand. Returns the def.
function Controller:set(name, on)
  local def = self:find(name)
  if not def then return nil, "no circuit called " .. tostring(name) end
  local st = self:stateOf(def)
  if def.mode == "manual" then
    def.state = on and true or false
  elseif def.mode == "pulse" then
    if on then st.pulseUntil = self.clock() + (tonumber(def.length) or 1) else st.pulseUntil = nil end
  else
    st.override = on and true or false
    if st.override == st.auto then st.override = nil end
  end
  return def
end

-- Check a circuit definition. Returns true or nil and why.
function validate(def)
  if type(def) ~= "table" then return nil, "not a table" end
  if type(def.name) ~= "string" or def.name == "" then return nil, "a circuit needs a name" end
  local okMode = false
  for _, m in ipairs(Modes) do if def.mode == m then okMode = true end end
  if not okMode then return nil, def.name .. ": mode must be manual, schedule, sensor or pulse" end
  if not def.output or not parseSignal(def.output) then return nil, def.name .. ": needs an output side" end
  if def.mode == "schedule" and (not parseTime(def.on) or not parseTime(def.off)) then
    return nil, def.name .. ": a schedule needs on and off times like 18:30"
  end
  if def.mode == "sensor" and not (def.input and def.input.side) then return nil, def.name .. ": a sensor needs an input side" end
  return true
end

-- Make a circuit from command words: name mode output [args...]
--   manual   <out>
--   schedule <out> <on> <off>
--   sensor   <out> <in> [delay]
--   pulse    <out> [seconds] [in]
-- Returns the def or nil and why.
function fromWords(name, mode, out, a, b)
  mode = tostring(mode or ""):lower()
  local output, why = parseSignal(out)
  if not output then return nil, why end
  local def = { name = name, mode = mode, output = output }
  if mode == "schedule" then
    def.on, def.off = parseTime(a), parseTime(b)
    if not def.on or not def.off then return nil, "schedule needs on and off times, e.g. 18:30 6:00" end
    def.on, def.off = timeText(def.on), timeText(def.off)
  elseif mode == "sensor" then
    local input, why2 = parseSignal(a)
    if not input then return nil, why2 or "sensor needs an input side" end
    def.input = input
    def.delay = tonumber(b) or 3
  elseif mode == "pulse" then
    def.length = tonumber(a) or 1
    if b then
      local input, why2 = parseSignal(b)
      if not input then return nil, why2 end
      def.input = input
    end
  end
  local ok, why3 = validate(def)
  if not ok then return nil, why3 end
  return def
end

-- One line describing a circuit's rule.
function describe(def)
  local s = def.mode .. " " .. signalText(def.output)
  if def.mode == "schedule" then s = s .. " " .. timeText(def.on) .. "-" .. timeText(def.off)
  elseif def.mode == "sensor" then s = s .. " from " .. signalText(def.input) .. " +" .. (def.delay or 0) .. "s"
  elseif def.mode == "pulse" then s = s .. " " .. (def.length or 1) .. "s" .. (def.input and (" on " .. signalText(def.input)) or "") end
  if def.invert then s = s .. " inverted" end
  return s
end
