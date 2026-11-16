--[[
Machines is a dashboard for the energy stores, tanks and inventories a
computer can see, next to it or on its wired network. Each machine gets
a gauge per thing it reports (energy, fluid, slots used) with a small
chart of its recent history; touch a machine's name for the Details tab,
which shows every reading it offers. Thresholds from the config raise
alerts on the bus ("alert", kind "power" for energy by default) and can
switch a redstone output while they last, such as a backup generator
that comes on below 20% energy and goes off again above 90%. The
Alerts tab lists what is active and the rules. The discovery, readings
and threshold logic are apis/machines.lua; the config is
/machines.cfg.

On a monitor the computer's own screen logs alerts and takes commands;
on the own screen a pasted line runs as a command:
  list                     every machine and its levels
  show <machine>           its details
  rules                    the threshold rules, numbered
  rule <metric> below|above <percent> [clear <percent>] [side or side:colour] [machine]
                           add a rule, e.g. rule energy below 20 clear 90 top,
                           replacing one for the same machine, metric and direction
  unrule <n>               remove rule n
  capacity <tank> <mB>     how much a tank holds (tanks do not say; without
                           it the gauge is against the most seen in it)
  log <file>|off           keep a CSV of readings, rotated by size
  scan, help, quit

Usage: machines [monitor|term] [configFile]
--]]

local args = { ... }
local configFile = args[2] or machines.ConfigFile
local config = machines.loadConfig(configFile)

local disp, err = basepanel.display(args[1], 36, 14)
if not disp then
  print("Error: " .. err)
  return
end

local previousTheme = guitheme.isChosen() and guitheme.getTheme() or nil
guitheme.setTheme("dark")

local mon = machines.new(config)
local app = guiapplication.GUIApplication.new()
local root, ids
local selected = nil     -- machine name shown in Details
local currentTab = 1
local lastOutputs = {}   -- "side/colour" -> on, to log changes
local alertKinds = {}    -- kinds with an active bus alert

local units = { energy = "FE", fluid = "mB", inventory = "Inv" }

local function status(text)
  if ids and ids.status then ids.status:setText(text) end
end

local function save()
  machines.saveConfig(config, configFile)
end

--[[
The view
--]]

local function gaugeId(name, metric) return "g_" .. name .. "_" .. metric end
local function sparkId(name, metric) return "s_" .. name .. "_" .. metric end

local function updateDetails()
  if not ids or not ids.details then return end
  if not selected then
    ids.detailTitle:setText("Touch a machine on the dashboard.")
    ids.details:setRows({})
    return
  end
  local rows = {}
  for i, r in ipairs(machines.readAll(peripheral, selected)) do rows[i] = { r.method, r.text } end
  local m = mon:find(selected)
  ids.detailTitle:setText(selected .. (m and (" (" .. table.concat(m.types, ", ") .. ")") or " (gone)"))
  ids.details:setRows(rows)
end

local function updateAlerts()
  if not ids or not ids.alerts then return end
  local rows = {}
  for i, a in ipairs(mon:activeAlerts()) do
    rows[i] = { a.kind, a.message, color = colors.red }
  end
  ids.alerts:setRows(rows)
  local rules = {}
  for i, rule in ipairs(config.rules or {}) do rules[#rules + 1] = { i, machines.ruleText(rule) } end
  ids.rules:setRows(rules)
end

local function updateGauges()
  if not ids then return end
  for _, m in ipairs(mon.machines) do
    for _, metric in ipairs(m.metrics) do
      local r = mon.readings[m.name] and mon.readings[m.name][metric]
      local g = ids[gaugeId(m.name, metric)]
      if g then
        local pct = math.floor(machines.fraction(r) * 100 + 0.5)
        g:setValue(pct)
        if not disp.compact then g.readout = pct .. "% " .. machines.readingText(metric, r) end
      end
      local s = ids[sparkId(m.name, metric)]
      local h = mon.history[m.name] and mon.history[m.name][metric]
      if s and h then
        local samples = {}
        for i, v in ipairs(h) do samples[i] = math.floor(v * 100 + 0.5) end
        s:setSamples(samples)
      end
    end
  end
  local n = #mon:activeAlerts()
  ids.summary:setText(#mon.machines .. " machines, " .. (n == 0 and "no alerts" or (n .. " alert" .. (n > 1 and "s" or ""))))
  ids.summary:setTextColor(n > 0 and colors.red or colors.lightGray)
  ids.summary:repaint()
end

local function buildRoot()
  local compact = disp.compact
  local rows = {}
  for _, m in ipairs(mon.machines) do
    local name = m.name
    rows[#rows + 1] = { type = "button", text = name, h = 1, bgRole = "surface", fgRole = "text", onPress = function()
        selected = name
        ids.tabs:select(2)
        updateDetails()
      end }
    for _, metric in ipairs(m.metrics) do
      local row = { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
        { type = "gauge", id = gaugeId(name, metric), dir = "horizontal", min = 0, max = 100, value = 0,
          label = units[metric], flex = 1, warnBelow = metric ~= "inventory" and 20 or nil,
          format = function(v) return v .. "%" end },
      } }
      if not compact then
        row.children[2] = { type = "sparkline", id = sparkId(name, metric), w = math.min(20, math.floor(disp.w / 3)), min = 0, max = 100 }
      end
      rows[#rows + 1] = row
    end
  end
  if #rows == 0 then rows[1] = { type = "text", text = "No machines found. Attach some and press scan.", h = 1, fgRole = "muted" } end

  local dashboard = { type = "scroll", title = "Dashboard", children = {
    { type = "box", dir = "vertical", gap = 0, children = rows },
  } }
  local details = { type = "box", title = "Details", dir = "vertical", gap = 0, children = {
    { type = "text", id = "detailTitle", text = "", h = 1, fgRole = "muted" },
    { type = "table", id = "details", flex = 1, striped = true, emptyText = "Nothing to show.",
      columns = { { title = "Method", width = compact and 10 or 18 }, { title = "Value", flex = 1 } } },
  } }
  local alerts = { type = "box", title = "Alerts", dir = "vertical", gap = 0, children = {
    { type = "table", id = "alerts", flex = 1, emptyText = "All is well.",
      columns = { { title = "Kind", width = 7 }, { title = "Message", flex = 1 } } },
    { type = "table", id = "rules", h = compact and 4 or 6, emptyText = "No rules.",
      columns = { { title = "#", width = 2 }, { title = "Rule", flex = 1 } } },
  } }

  local newRoot
  newRoot, ids = guibuild.build({
    type = "root", title = "Machines", term = disp.term, side = disp.side, dir = "vertical", gap = 0, children = {
      { type = "text", id = "summary", text = "", h = 1 },
      { type = "tabs", id = "tabs", flex = 1, children = { dashboard, details, alerts },
        onChange = function(e)
          currentTab = e.index
          if e.index == 2 then os.queueEvent("machines_details") end
          if e.index == 3 then updateAlerts() end
        end },
      { type = "text", id = "status", text = "Touch a machine for its details.", h = 1, fgRole = "muted" },
    },
  })
  root = newRoot
  -- the gauges show the reading as text instead of the bare number
  for _, m in ipairs(mon.machines) do
    for _, metric in ipairs(m.metrics) do
      local g = ids[gaugeId(m.name, metric)]
      if g then
        local plain = g.getReadout
        g.getReadout = function(self) return self.readout or plain(self) end
      end
    end
  end
  app:setRootContainer(root)
  if app.running then
    root:setStarted(true)
    root:repaint()
  end
  if currentTab ~= 1 then ids.tabs:select(currentTab, false) end
  updateGauges()
  updateAlerts()
end

--[[
Polling
--]]

-- One bus alert per kind, naming every machine in that state.
local function publishAlerts()
  local byKind = {}
  local seen = {}
  for _, a in ipairs(mon:activeAlerts()) do
    -- two rules can say the same thing about one machine
    if not seen[a.kind .. a.machine .. a.metric] then
      seen[a.kind .. a.machine .. a.metric] = true
      byKind[a.kind] = byKind[a.kind] or {}
      table.insert(byKind[a.kind], a.message)
    end
  end
  for kind, messages in pairs(byKind) do
    basepanel.setAlert(kind, table.concat(messages, "; "), true)
    alertKinds[kind] = true
  end
  for kind in pairs(alertKinds) do
    if not byKind[kind] then
      basepanel.setAlert(kind, kind .. " alerts cleared", false)
      alertKinds[kind] = nil
    end
  end
end

local function poll()
  local events = mon:poll()
  for _, e in ipairs(events) do
    basepanel.log(basepanel.timeText(os.time()) .. " " .. e.message)
  end
  if #events > 0 then publishAlerts() end
  for _, o in ipairs(mon:applyOutputs()) do
    local key = o.side .. (o.color and ("/" .. tostring(o.color)) or "")
    if lastOutputs[key] ~= o.on then
      if lastOutputs[key] ~= nil or o.on then
        basepanel.log("output " .. o.side .. (o.color and (":" .. circuits.colorName(circuits.colorOf(o.color))) or "") .. (o.on and " on" or " off"))
      end
      lastOutputs[key] = o.on
    end
  end
  if config.logFile and config.logFile ~= "" then
    local header = "time,machine,metric,value,max"
    for _, line in ipairs(mon:csvLines(os.epoch and os.epoch("utc") or os.clock())) do
      machines.appendLog(config.logFile, line, config.logMaxBytes, header)
    end
  end
  updateGauges()
  if currentTab == 3 then updateAlerts() end
  if currentTab == 2 then updateDetails() end
end

local function rescan()
  mon:scan()
  buildRoot()
end

local function loop()
  poll()
  local timer = os.startTimer(config.interval or 2)
  while true do
    local event, p1 = os.pullEvent()
    if event == "timer" and p1 == timer then
      poll()
      timer = os.startTimer(config.interval or 2)
    elseif event == "peripheral" or event == "peripheral_detach" or event == "machines_scan" then
      rescan()
      poll()
    elseif event == "machines_details" then
      updateDetails()
    end
  end
end

--[[
Commands
--]]

local helpText = "commands: list, show <machine>, rules, rule <metric> below|above <pct> [clear <pct>] [side] [machine], unrule <n>, capacity <tank> <mB>, log <file>|off, scan, quit"

local function command(line)
  local w = basepanel.words(line)
  local cmd = (w[1] or ""):lower()
  if cmd == "help" or cmd == "?" then return helpText
  elseif cmd == "list" then
    local out = {}
    for _, m in ipairs(mon.machines) do
      local parts = {}
      for _, metric in ipairs(m.metrics) do
        local r = mon.readings[m.name] and mon.readings[m.name][metric]
        parts[#parts + 1] = metric .. " " .. math.floor(machines.fraction(r) * 100 + 0.5) .. "%"
      end
      out[#out + 1] = m.name .. ": " .. table.concat(parts, ", ")
    end
    return #out > 0 and table.concat(out, "; ") or "no machines"
  elseif cmd == "show" then
    local m = mon:find(w[2] or "")
    if not m then return "no machine called " .. tostring(w[2]) end
    selected = m.name
    ids.tabs:select(2)
    os.queueEvent("machines_details")
    return "showing " .. m.name
  elseif cmd == "rules" then
    local out = {}
    for i, rule in ipairs(config.rules or {}) do out[#out + 1] = i .. ". " .. machines.ruleText(rule) end
    return #out > 0 and table.concat(out, "; ") or "no rules"
  elseif cmd == "rule" then
    local metric, dir, pct = w[2], w[3], tonumber(w[4])
    local okMetric = false
    for _, mm in ipairs(machines.Metrics) do if mm == metric then okMetric = true end end
    if not okMetric or (dir ~= "below" and dir ~= "above") or not pct then
      return "rule <energy|fluid|inventory> below|above <percent> [clear <percent>] [side or side:colour] [machine]"
    end
    local rule = { machine = "*", metric = metric, kind = metric == "energy" and "power" or metric }
    rule[dir] = pct / 100
    local i = 5
    if w[i] == "clear" then
      local c = tonumber(w[i + 1])
      if not c then return "clear needs a percent" end
      rule.clear = c / 100
      i = i + 2
    end
    if w[i] then
      local sig = circuits.parseSignal(w[i])
      if sig then rule.output = sig; i = i + 1 end
    end
    if w[i] then rule.machine = w[i] end
    -- a rule for the same machine, metric and direction is replaced
    config.rules = config.rules or {}
    local index = #config.rules + 1
    for i, old in ipairs(config.rules) do
      if old.machine == rule.machine and old.metric == rule.metric and (old.below ~= nil) == (rule.below ~= nil) then
        index = i
        for _, a in pairs(mon.active) do if a.rule == old then a.rule = rule end end
      end
    end
    config.rules[index] = rule
    save()
    updateAlerts()
    return "rule " .. index .. ": " .. machines.ruleText(rule)
  elseif cmd == "unrule" then
    local n = tonumber(w[2])
    if not n or not config.rules[n] then return "unrule <n>, see rules" end
    local rule = table.remove(config.rules, n)
    for key, a in pairs(mon.active) do if a.rule == rule then mon.active[key] = nil end end
    if rule.output and rule.output.side then circuits.writeOutputs({ { side = rule.output.side, color = rule.output.color, on = false } }) end
    save()
    publishAlerts()
    updateAlerts()
    return "removed rule " .. n
  elseif cmd == "capacity" then
    local m, n = mon:find(w[2] or ""), tonumber(w[3])
    if not m or not n or n <= 0 then return "capacity <tank> <mB>: tanks do not report how much they hold" end
    config.capacity = config.capacity or {}
    config.capacity[m.name] = n
    save()
    return m.name .. " holds " .. n .. " mB"
  elseif cmd == "log" then
    if not w[2] then return "log <file>|off" end
    config.logFile = w[2] == "off" and "" or w[2]
    save()
    return config.logFile == "" and "not logging" or ("logging to " .. config.logFile)
  elseif cmd == "scan" then
    os.queueEvent("machines_scan")
    return "scanning"
  end
  return "unknown command " .. cmd .. "; " .. helpText
end

mon:scan()
buildRoot()
app:setUPS(20)
basepanel.run({
  app = app, display = disp, name = "machines", commands = command,
  loops = { loop, basepanel.busLoop({}) },
  onStatus = function(msg) status(msg) end,
})
guitheme.setTheme(previousTheme)
