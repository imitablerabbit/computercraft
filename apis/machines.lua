--[[
Machines finds the machines a computer can see (next to it or on its
wired network) and reads the generic peripheral methods CC: Tweaked
gives modded blocks: energy (getEnergy, getEnergyCapacity), fluids
(tanks) and inventories (size, list). It keeps a short history of each
reading and checks them against thresholds, so a program can raise an
alert and switch a redstone output (a backup generator) when a store
runs low, and switch it off again once it is full.

  local m = machines.new(config)
  m:scan()                          -- find the machines
  local events = m:poll()           -- read them all, check thresholds
  for _, e in ipairs(events) do print(e.action, e.machine, e.metric) end
  m:applyOutputs()                  -- redstone for the active alerts

A rule is { machine = "*" (or a name, or part of one), metric =
"energy" | "fluid" | "inventory", below = 0.2, clear = 0.9 } for a
store that must not run low, or { above = 0.9, clear = 0.7 } for one
that must not fill up, with kind (the alert kind, "power" by default
for energy), and output = { side, color } to switch on while the alert
is active. clear is the hysteresis: an alert raised below 20% stays
until 90%, so a generator is not switched on and off at every tick.

Tanks do not say how much they hold in CC: Tweaked, so a fluid level
is measured against the capacity in config.capacity[name] when there
is one and otherwise against the most the tank has been seen to hold.

new(config, opts): opts.peripheral, opts.clock and opts.io (the
redstone API) can be replaced, which is how the tests run it.
--]]

DefaultConfig = {
  interval = 2,       -- seconds between readings
  history = 60,       -- readings kept for the charts
  rules = {
    { machine = "*", metric = "energy", below = 0.2, clear = 0.9, kind = "power" },
    { machine = "*", metric = "inventory", above = 0.95, clear = 0.8, kind = "full" },
  },
  capacity = {},      -- fluid capacity in mB by machine name
  logFile = "",       -- a CSV file of readings, "" for none
  logMaxBytes = 20000,
}

ConfigFile = "/machines.cfg"

Metrics = { "energy", "fluid", "inventory" }

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

-- A short name for a peripheral: thermal:energy_cell_0 -> energy_cell_0.
function shortName(name)
  return (tostring(name):gsub("^[^:]*:", ""))
end

--[[
Discovery and reading
--]]

local skipTypes = { modem = true, monitor = true, computer = true, turtle = true, drive = true,
                    printer = true, speaker = true, peripheral_hub = true }

-- What a peripheral can be read for, from its method names.
function metricsOf(methods)
  local set = {}
  for _, m in ipairs(methods or {}) do set[m] = true end
  local out = {}
  if set.getEnergy and set.getEnergyCapacity then out[#out + 1] = "energy" end
  if set.tanks then out[#out + 1] = "fluid" end
  if set.list and set.size then out[#out + 1] = "inventory" end
  return out, set
end

-- Every peripheral with something to read, sorted by name.
function discover(P)
  P = P or peripheral
  local out = {}
  for _, name in ipairs(P.getNames()) do
    local types = { P.getType(name) }
    local skip = false
    for _, t in ipairs(types) do if skipTypes[t] then skip = true end end
    if not skip then
      local methods = P.getMethods(name) or {}
      local metrics, set = metricsOf(methods)
      if #metrics > 0 then
        out[#out + 1] = { name = name, types = types, methods = set, metrics = metrics }
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- Read one metric of a machine: { value, max, text } or nil and why.
-- seenMax is the most a tank has held, for tanks without a capacity.
function readMetric(P, name, metric, capacity, seenMax)
  if metric == "energy" then
    local ok, v = pcall(P.call, name, "getEnergy")
    local ok2, max = pcall(P.call, name, "getEnergyCapacity")
    if not ok or not ok2 or type(v) ~= "number" then return nil, tostring(v) end
    return { value = v, max = max or 0 }
  elseif metric == "fluid" then
    local ok, tanks = pcall(P.call, name, "tanks")
    if not ok or type(tanks) ~= "table" then return nil, tostring(tanks) end
    local amount, fluid = 0, nil
    for _, t in pairs(tanks) do
      amount = amount + (t.amount or 0)
      fluid = fluid or t.name
    end
    local max = capacity or math.max(seenMax or 0, amount)
    return { value = amount, max = max, fluid = fluid, measured = capacity == nil }
  elseif metric == "inventory" then
    local ok, size = pcall(P.call, name, "size")
    local ok2, list = pcall(P.call, name, "list")
    if not ok or not ok2 or type(list) ~= "table" then return nil, tostring(list) end
    local used, items = 0, 0
    for _, st in pairs(list) do used = used + 1; items = items + (st.count or 0) end
    return { value = used, max = size or 0, items = items }
  end
  return nil, "unknown metric " .. tostring(metric)
end

function fraction(reading)
  if not reading or not reading.max or reading.max <= 0 then return 0 end
  return math.max(0, math.min(1, reading.value / reading.max))
end

-- A short number: 1234567 -> 1.2M.
function shortNumber(v)
  v = tonumber(v) or 0
  local a = math.abs(v)
  if a >= 1e9 then return string.format("%.1fG", v / 1e9) end
  if a >= 1e6 then return string.format("%.1fM", v / 1e6) end
  if a >= 1e4 then return string.format("%.0fk", v / 1e3) end
  if a >= 1e3 then return string.format("%.1fk", v / 1e3) end
  return tostring(math.floor(v + 0.5))
end

function readingText(metric, r)
  if not r then return "?" end
  if metric == "energy" then return shortNumber(r.value) .. "/" .. shortNumber(r.max) .. " FE" end
  if metric == "fluid" then return shortNumber(r.value) .. (r.measured and "" or ("/" .. shortNumber(r.max))) .. " mB" end
  if metric == "inventory" then return r.value .. "/" .. r.max .. " slots" end
  return tostring(r.value)
end

-- Every reading a machine offers, for its details screen: each method
-- that takes no arguments and only reports (get..., is..., list, size,
-- tanks), with what it returned as text.
local readers = { "^get", "^is", "^has", "^list$", "^size$", "^tanks$" }
function readAll(P, name)
  P = P or peripheral
  local out = {}
  local methods = P.getMethods(name) or {}
  table.sort(methods)
  for _, m in ipairs(methods) do
    local reads = false
    for _, pat in ipairs(readers) do if m:match(pat) then reads = true end end
    if reads then
      local res = table.pack(pcall(P.call, name, m))
      if res[1] then
        local parts = {}
        for i = 2, res.n do
          local v = res[i]
          if type(v) == "table" then
            local ok, s = pcall(textutils.serialize, v, { compact = true })
            if not ok then ok, s = pcall(textutils.serialize, v) end
            v = ok and tostring(s):gsub("%s+", " ") or "{...}"
          end
          parts[#parts + 1] = tostring(v)
        end
        out[#out + 1] = { method = m, text = table.concat(parts, ", ") }
      end
    end
  end
  return out
end

--[[
Thresholds with hysteresis
--]]

-- Does a rule apply to this machine and metric?
function ruleMatches(rule, name, metric)
  if rule.metric and rule.metric ~= metric then return false end
  local m = rule.machine
  if m == nil or m == "*" or m == name then return true end
  return tostring(name):find(m, 1, true) ~= nil
end

-- Where a reading stands against a rule, given whether the alert is
-- active now: returns the new active state.
function thresholdState(rule, frac, active)
  if rule.below then
    local clear = rule.clear or math.min(1, rule.below + 0.1)
    if active then return frac < clear end
    return frac < rule.below
  elseif rule.above then
    local clear = rule.clear or math.max(0, rule.above - 0.1)
    if active then return frac > clear end
    return frac > rule.above
  end
  return false
end

function ruleText(rule)
  local pct = function(v) return math.floor(v * 100 + 0.5) .. "%" end
  local s = (rule.machine and rule.machine ~= "*" and (rule.machine .. " ") or "") .. (rule.metric or "any")
  if rule.below then s = s .. " below " .. pct(rule.below) .. ", clear at " .. pct(rule.clear or math.min(1, rule.below + 0.1))
  elseif rule.above then s = s .. " above " .. pct(rule.above) .. ", clear at " .. pct(rule.clear or math.max(0, rule.above - 0.1)) end
  if rule.output and rule.output.side then
    s = s .. ", output " .. rule.output.side .. (rule.output.color and (":" .. rule.output.color) or "")
  end
  return s
end

--[[
The monitor
--]]

local Monitor = {}
Monitor.__index = Monitor

function new(config, opts)
  opts = opts or {}
  return setmetatable({
    config = config,
    p = opts.peripheral or peripheral,
    io = opts.io or redstone,
    clock = opts.clock or os.clock,
    machines = {},
    readings = {},   -- name -> metric -> reading
    history = {},    -- name -> metric -> list of fractions
    seenMax = {},    -- name -> most fluid seen
    active = {},     -- "name/metric/ruleIndex" -> { rule, machine, metric, since }
  }, Monitor)
end

function Monitor:scan()
  self.machines = discover(self.p)
  return self.machines
end

function Monitor:find(text)
  for _, m in ipairs(self.machines) do if m.name == text then return m end end
  for _, m in ipairs(self.machines) do if m.name:find(text, 1, true) then return m end end
  return nil
end

-- Read every machine (in parallel), keep the history and check the
-- rules. Returns the alerts that changed: list of { action = "raise" |
-- "clear", machine, metric, kind, message, rule }.
function Monitor:poll()
  local fns = {}
  local results = {}
  for _, m in ipairs(self.machines) do
    for _, metric in ipairs(m.metrics) do
      fns[#fns + 1] = function()
        local cap = self.config.capacity and self.config.capacity[m.name]
        results[m.name .. "/" .. metric] = { readMetric(self.p, m.name, metric, cap, self.seenMax[m.name]) }
      end
    end
  end
  if storage and storage.runBatched then storage.runBatched(fns) else for _, f in ipairs(fns) do f() end end

  local events = {}
  local keep = self.config.history or 60
  for _, m in ipairs(self.machines) do
    self.readings[m.name] = self.readings[m.name] or {}
    self.history[m.name] = self.history[m.name] or {}
    for _, metric in ipairs(m.metrics) do
      local r = results[m.name .. "/" .. metric] and results[m.name .. "/" .. metric][1]
      self.readings[m.name][metric] = r
      if r then
        if metric == "fluid" then self.seenMax[m.name] = math.max(self.seenMax[m.name] or 0, r.value) end
        local h = self.history[m.name][metric] or {}
        h[#h + 1] = fraction(r)
        while #h > keep do table.remove(h, 1) end
        self.history[m.name][metric] = h
        for i, rule in ipairs(self.config.rules or {}) do
          if ruleMatches(rule, m.name, metric) then
            local key = m.name .. "/" .. metric .. "/" .. i
            local was = self.active[key] ~= nil
            local frac = fraction(r)
            local now = thresholdState(rule, frac, was)
            if now ~= was then
              local kind = rule.kind or (metric == "energy" and "power" or metric)
              local pct = math.floor(frac * 100 + 0.5) .. "%"
              local message
              if now then
                message = shortName(m.name) .. " " .. metric .. " " .. (rule.below and "low" or "high") .. ": " .. pct
                self.active[key] = { rule = rule, machine = m.name, metric = metric, kind = kind, message = message, since = self.clock() }
              else
                message = shortName(m.name) .. " " .. metric .. " back to " .. pct
                self.active[key] = nil
              end
              events[#events + 1] = { action = now and "raise" or "clear", machine = m.name, metric = metric,
                                      kind = kind, message = message, rule = rule, key = key }
            end
          end
        end
      end
    end
  end
  return events
end

-- The alerts active now, oldest first.
function Monitor:activeAlerts()
  local out = {}
  for key, a in pairs(self.active) do out[#out + 1] = a end
  table.sort(out, function(a, b) return a.since < b.since end)
  return out
end

-- The redstone outputs the rules name: on while any alert using that
-- output is active, off otherwise.
function Monitor:outputs()
  local list = {}
  for i, rule in ipairs(self.config.rules or {}) do
    if rule.output and rule.output.side then
      local on = false
      for key, a in pairs(self.active) do if a.rule == rule then on = true end end
      list[#list + 1] = { side = rule.output.side, color = rule.output.color, on = on }
    end
  end
  return list
end

function Monitor:applyOutputs()
  local list = self:outputs()
  if #list > 0 then circuits.writeOutputs(list, self.io) end
  return list
end

--[[
Logging readings to a CSV file, rotated by size: when the file grows
past maxBytes it becomes file.1 (replacing the previous one) and a new
file is started with the header.
--]]
function appendLog(path, line, maxBytes, header)
  if not path or path == "" then return false end
  if maxBytes and fs.exists(path) and fs.getSize(path) + #line > maxBytes then
    if fs.exists(path .. ".1") then fs.delete(path .. ".1") end
    fs.move(path, path .. ".1")
  end
  local fresh = not fs.exists(path)
  local h = fs.open(path, "a")
  if not h then return false end
  if fresh and header then h.writeLine(header) end
  h.writeLine(line)
  h.close()
  return true
end

-- CSV lines for the latest readings: time,machine,metric,value,max.
function Monitor:csvLines(time)
  local out = {}
  for _, m in ipairs(self.machines) do
    for _, metric in ipairs(m.metrics) do
      local r = self.readings[m.name] and self.readings[m.name][metric]
      if r then out[#out + 1] = string.format("%s,%s,%s,%s,%s", tostring(time), m.name, metric, tostring(r.value), tostring(r.max)) end
    end
  end
  return out
end
