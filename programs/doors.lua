--[[
Doors is a touch panel for the redstone a computer drives: lights,
doors, gates and bells, each a named circuit on one side of the
computer (or one colour of bundled cable on a side). A circuit is
manual (switched from the panel), on a schedule of the Minecraft day
(lights on 18:30 to 6:00), a sensor that follows a redstone input with
an off delay (a door that closes 3 s after its pressure plate is left)
or a pulse (a bell or a piston, on for a moment). The rules live in
apis/circuits.lua.

The Panel tab has a button per circuit, green when on and gray when
off, with why it is in that state; touching one switches it (a pulse
fires; a schedule or sensor is overridden until its own rule next
changes). The Edit tab changes, adds and removes circuits, which are
kept in /doors.cfg. Every change is published on the bus as
"base.circuit" { name, state, mode, reason }.

On a monitor the computer's own screen logs every change and takes
commands; on the own screen a pasted line runs as a command:
  toggle|on|off <name>      switch a circuit
  add <name> manual <out>
  add <name> schedule <out> <on> <off>     times like 18:30
  add <name> sensor <out> <in> [delay]
  add <name> pulse <out> [seconds] [in]
  remove <name>, list, time, help, quit
<out> and <in> are a side (back) or a side and bundled colour
(back:white). A name may have spaces: add Hall lights schedule right
18:30 6:00.

Usage: doors [monitor|term] [configFile]
--]]

local args = { ... }
local configFile = args[2] or circuits.ConfigFile
local config = circuits.loadConfig(configFile)

local disp, err = basepanel.display(args[1], 36, 14)
if not disp then
  print("Error: " .. err)
  return
end

local previousTheme = guitheme.isChosen() and guitheme.getTheme() or nil
guitheme.setTheme("dark")

local ctl = circuits.new(config)
local app = guiapplication.GUIApplication.new()
local root, ids
local buttons = {}       -- circuit name -> { button, info text }
local draft = nil        -- the circuit being edited (a copy)
local editIndex = nil    -- its index in config.circuits, nil for a new one
local draftTouched = false -- the draft was changed on screen
local currentTab = 1

local function save()
  circuits.saveConfig(config, configFile)
end

local function status(text)
  if ids and ids.status then ids.status:setText(text) end
end

--[[
The panel
--]]

local function paintCircuit(def)
  local b = buttons[def.name]
  if not b then return end
  local st = ctl:stateOf(def)
  local label = def.name .. (st.on and "  ON" or "  off")
  local info = st.reason or def.mode
  -- repaint only what changed: this runs twice a second
  if b.label == label and b.infoText == info then return end
  b.label, b.infoText = label, info
  b.button:setBackgroundColor(st.on and colors.green or colors.gray)
  b.button:setTextColor(st.on and colors.black or colors.white)
  b.button:setText(label)
  if b.info then b.info:setText(info) end
end

local lastClock
local function paintAll()
  for _, def in ipairs(config.circuits) do paintCircuit(def) end
  local clock = "Time " .. basepanel.timeText(os.time())
  if ids and ids.clock and clock ~= lastClock then
    lastClock = clock
    ids.clock:setText(clock)
  end
end

-- Apply the rules and tell everyone what changed.
local function step()
  local changes = ctl:update()
  for _, ch in ipairs(changes) do
    basepanel.log(basepanel.timeText(os.time()) .. " " .. ch.name .. (ch.state and " on" or " off") .. " (" .. tostring(ch.reason) .. ")")
    basepanel.publish("base.circuit", { name = ch.name, state = ch.state, mode = ch.mode, reason = ch.reason })
  end
  paintAll()
end

local function control()
  step()
  local timer = os.startTimer(0.5)
  while true do
    local event, p1 = os.pullEvent()
    if event == "redstone" or event == "doors_step" then
      step()
    elseif event == "timer" and p1 == timer then
      step()
      timer = os.startTimer(0.5)
    end
  end
end

local function touch(name)
  local def, why = ctl:toggle(name)
  if not def then return why end
  save()
  os.queueEvent("doors_step")
  return "switched " .. def.name
end

--[[
The editor
--]]

local sideOptions = { table.unpack(circuits.Sides) }
local inputSideOptions = { "none", table.unpack(circuits.Sides) }
local colorOptions = { "none", table.unpack(circuits.ColorNames) }

local buildRoot -- forward

local function copyDef(def)
  return textutils.unserialize(textutils.serialize(def))
end

local function showDraft()
  if not ids or not ids.ename then return end
  local d = draft
  ids.ename:setText(d.name or "")
  ids.emode:setValue(d.mode or "manual")
  ids.eoutSide:setValue(d.output and d.output.side or "back")
  ids.eoutColor:setValue(d.output and d.output.color or "none")
  ids.einSide:setValue(d.input and d.input.side or "none")
  ids.einColor:setValue(d.input and d.input.color or "none")
  ids.eon:setText(circuits.timeText(d.on or "18:30"))
  ids.eoff:setText(circuits.timeText(d.off or "6:00"))
  local secs = d.mode == "pulse" and (d.length or 1) or (d.delay or 3)
  ids.esecs:setText(tostring(secs) .. "s")
  ids.einvert:setChecked(d.invert and true or false)
end

local function editCircuit(index)
  editIndex = index
  draftTouched = false
  if index and config.circuits[index] then
    draft = copyDef(config.circuits[index])
  else
    draft = { name = "Circuit " .. (#config.circuits + 1), mode = "manual", output = { side = "back" } }
    editIndex = nil
  end
  showDraft()
end

local function readDraft()
  local d = draft
  draftTouched = true
  d.name = ids.ename:getText()
  d.mode = ids.emode:getValue()
  d.output = { side = ids.eoutSide:getValue() }
  if ids.eoutColor:getValue() ~= "none" then d.output.color = ids.eoutColor:getValue() end
  if ids.einSide:getValue() ~= "none" then
    d.input = { side = ids.einSide:getValue() }
    if ids.einColor:getValue() ~= "none" then d.input.color = ids.einColor:getValue() end
  else
    d.input = nil
  end
  d.on = d.on or "18:30"
  d.off = d.off or "06:00"
  d.invert = ids.einvert:isChecked() or nil
  return d
end

local function stepTime(field, delta)
  readDraft()
  local t = circuits.parseTime(draft[field]) or 0
  draft[field] = circuits.timeText((t + delta) % 24)
  showDraft()
end

local function stepSecs(delta)
  readDraft()
  if draft.mode == "pulse" then
    draft.length = math.max(0.5, (draft.length or 1) + delta * 0.5)
  else
    draft.delay = math.max(0, (draft.delay or 3) + delta)
  end
  showDraft()
end

local function saveDraft()
  local d = readDraft()
  if d.mode ~= "schedule" then d.on, d.off = nil, nil end
  if d.mode ~= "sensor" then d.delay = nil end
  if d.mode ~= "pulse" then d.length = nil end
  local ok, why = circuits.validate(d)
  if not ok then return status(why) end
  for i, other in ipairs(config.circuits) do
    if i ~= editIndex and other.name:lower() == d.name:lower() then return status("There is already a circuit called " .. d.name) end
  end
  if editIndex then
    config.circuits[editIndex] = d
  else
    config.circuits[#config.circuits + 1] = d
    editIndex = #config.circuits
  end
  save()
  buildRoot(2)
  status("Saved " .. d.name)
  os.queueEvent("doors_step")
end

local function removeCircuit(index)
  local def = config.circuits[index]
  if not def then return end
  -- leave its output off
  local list = { { side = def.output.side, color = def.output.color, on = false } }
  table.remove(config.circuits, index)
  ctl.state[def.name] = nil
  circuits.writeOutputs(list)
  save()
  return def
end

--[[
Building the screen (again whenever circuits are added or removed)
--]]

local function circuitNames()
  local out = {}
  for _, def in ipairs(config.circuits) do out[#out + 1] = def.name end
  out[#out + 1] = "(new circuit)"
  return out
end

buildRoot = function(tab)
  local compact = disp.compact
  buttons = {}
  local rows = {}
  for _, def in ipairs(config.circuits) do
    local name = def.name
    local row = { type = "box", dir = "horizontal", gap = 1, h = compact and 1 or 3, children = {
      { type = "button", id = "c_" .. name, text = name, flex = 1, border = not compact, onPress = function()
          status(touch(name))
        end },
    } }
    if not compact then
      row.children[2] = { type = "box", dir = "vertical", w = disp.w >= 56 and 28 or 22, children = {
        { type = "text", text = circuits.describe(def), h = 1, fgRole = "muted" },
        { type = "text", id = "i_" .. name, text = "", h = 1 },
      } }
    end
    rows[#rows + 1] = row
  end
  if #rows == 0 then rows[1] = { type = "text", text = "No circuits yet: add one in Edit.", h = 1, fgRole = "muted" } end

  local panel = { type = "scroll", title = "Panel", children = {
    { type = "box", dir = "vertical", gap = compact and 0 or 1, padding = compact and 0 or 1, children = rows },
  } }

  local label = function(text) return { type = "text", text = text, w = compact and 7 or 9, fgRole = "muted" } end
  local edit = { type = "scroll", title = "Edit", children = {
    { type = "box", dir = "vertical", gap = 1, padding = compact and 0 or 1, children = {
      { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
        { type = "dropdown", id = "epick", options = circuitNames(), flex = 1, onSelect = function()
            local i = ids.epick:getSelectedIndex()
            editCircuit(i <= #config.circuits and i or nil)
          end },
        { type = "button", text = "Del", w = 5, onPress = function()
            if not editIndex then return status("Nothing to delete.") end
            local name = config.circuits[editIndex].name
            guidialog.confirm(root, "Delete", "Delete " .. name .. "? Its output is switched off.", function()
              removeCircuit(editIndex)
              editIndex = nil
              buildRoot(2)
              status("Deleted " .. name)
            end, nil, { yes = "Delete", no = "Keep", danger = true })
          end },
      } },
      { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
        label("Name"), { type = "input", id = "ename", text = "", border = false, flex = 1, h = 1, bgRole = "surface" } } },
      { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
        label("Mode"), { type = "dropdown", id = "emode", options = circuits.Modes, flex = 1 } } },
      { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
        label("Output"), { type = "dropdown", id = "eoutSide", options = sideOptions, flex = 1 },
        { type = "dropdown", id = "eoutColor", options = colorOptions, flex = 1 } } },
      { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
        label("Input"), { type = "dropdown", id = "einSide", options = inputSideOptions, flex = 1 },
        { type = "dropdown", id = "einColor", options = colorOptions, flex = 1 } } },
      { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
        label("On at"), { type = "button", text = "-", w = 3, onPress = function() stepTime("on", -0.5) end },
        { type = "text", id = "eon", text = "", w = 5, align = "center" },
        { type = "button", text = "+", w = 3, onPress = function() stepTime("on", 0.5) end } } },
      { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
        label("Off at"), { type = "button", text = "-", w = 3, onPress = function() stepTime("off", -0.5) end },
        { type = "text", id = "eoff", text = "", w = 5, align = "center" },
        { type = "button", text = "+", w = 3, onPress = function() stepTime("off", 0.5) end } } },
      { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
        label(compact and "Delay" or "Delay/len"), { type = "button", text = "-", w = 3, onPress = function() stepSecs(-1) end },
        { type = "text", id = "esecs", text = "", w = 5, align = "center" },
        { type = "button", text = "+", w = 3, onPress = function() stepSecs(1) end } } },
      { type = "checkbox", id = "einvert", text = "Invert the output", h = 1 },
      { type = "button", text = "Save", h = 1, onPress = saveDraft },
    } },
  } }

  local newRoot
  newRoot, ids = guibuild.build({
    type = "root", title = "Doors", term = disp.term, side = disp.side, dir = "vertical", gap = 0, children = {
      { type = "text", id = "clock", text = "Time " .. basepanel.timeText(os.time()), h = 1, fgRole = "muted" },
      { type = "tabs", id = "tabs", flex = 1, children = { panel, edit },
        onChange = function(e) currentTab = e.index or currentTab end },
      { type = "text", id = "status", text = "Touch a circuit to switch it.", h = 1, fgRole = "muted" },
    },
  })
  root = newRoot
  lastClock = nil
  for _, def in ipairs(config.circuits) do
    buttons[def.name] = { button = ids["c_" .. def.name], info = ids["i_" .. def.name] }
  end
  app:setRootContainer(root)
  if app.running then
    root:setStarted(true)
    root:repaint()
  end
  currentTab = tab or currentTab
  if currentTab ~= 1 then ids.tabs:select(currentTab) end
  if editIndex and config.circuits[editIndex] then ids.epick:setValue(config.circuits[editIndex].name) end
  if editIndex == nil then ids.epick:setValue("(new circuit)") end
  if not draft or (editIndex == nil and not draftTouched) then
    editCircuit(#config.circuits > 0 and 1 or nil)
  else
    showDraft()
  end
  if editIndex then ids.epick:setValue(config.circuits[editIndex].name) end
  paintAll()
end

--[[
Commands
--]]

local helpText = "commands: toggle|on|off <name>, add <name> <mode> <out> [...], remove <name>, list, time, quit"

local function command(line)
  local w = basepanel.words(line)
  local cmd = (w[1] or ""):lower()
  local rest = table.concat(w, " ", 2)
  if cmd == "help" or cmd == "?" then return helpText
  elseif cmd == "toggle" or cmd == "switch" then
    return touch(rest)
  elseif cmd == "on" or cmd == "off" then
    local def, why = ctl:set(rest, cmd == "on")
    if not def then return why end
    save()
    os.queueEvent("doors_step")
    return def.name .. " set " .. cmd
  elseif cmd == "add" then
    -- the name runs up to the mode word, so it may have spaces
    local m
    for i = 3, #w do
      for _, mode in ipairs(circuits.Modes) do
        if not m and w[i]:lower() == mode then m = i end
      end
    end
    if not m or not w[m + 1] then return "add <name> <mode> <out> [...]" end
    local name = table.concat(w, " ", 2, m - 1)
    local existing = ctl:find(name)
    if existing and existing.name:lower() == name:lower() then return "there is already a circuit called " .. name end
    local def, why = circuits.fromWords(name, w[m], w[m + 1], w[m + 2], w[m + 3])
    if not def then return why end
    config.circuits[#config.circuits + 1] = def
    save()
    buildRoot()
    os.queueEvent("doors_step")
    return "added " .. def.name .. ": " .. circuits.describe(def)
  elseif cmd == "remove" or cmd == "delete" then
    local def, index = ctl:find(rest)
    if not def then return "no circuit called " .. rest end
    removeCircuit(index)
    if editIndex == index then editIndex, draft = nil, nil end
    buildRoot()
    return "removed " .. def.name
  elseif cmd == "list" then
    local out = {}
    for _, def in ipairs(config.circuits) do
      out[#out + 1] = def.name .. " " .. (ctl:stateOf(def).on and "ON" or "off") .. " [" .. circuits.describe(def) .. "]"
    end
    return #out > 0 and table.concat(out, "; ") or "no circuits"
  elseif cmd == "time" then
    return "it is " .. basepanel.timeText(os.time())
  end
  return "unknown command " .. cmd .. "; " .. helpText
end

buildRoot(1)
app:setUPS(20)
basepanel.run({
  app = app, display = disp, name = "doors", commands = command,
  loops = { control, basepanel.busLoop({}) },
  onStatus = function(msg) status(msg) end,
})
-- leave every output as it is: lights stay on, doors stay shut
guitheme.setTheme(previousTheme)
