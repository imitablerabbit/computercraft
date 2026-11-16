--[[
Storage is a touch panel for a network of chests: a computer with a
wired modem on the same cable as the chests, an input chest where
items are put to be stored and an output chest where requested items
come out. Every other inventory on the network is storage. The index,
the searching and the moving of items is apis/storage.lua.

The Items tab lists everything in storage with its count. Touch a row
to pick an item, then 1, 16, 64, Stack or All to send that many to the
output chest (or type a number in the box and press Get). The list can
be narrowed with the search box and sorted by name or count. Deposit
moves everything in the input chest into storage, topping up stacks of
the same item first; Auto deposits by itself every few seconds. The bar
at the top is how many storage slots are used, and turning red (with
an "alert" on the bus) when nearly full. The Settings tab picks the
input and output chests, the auto deposit interval and the alert level,
kept in /storage.cfg.

A turtle with a wired modem on the same network can ask for items over
the bus ("base.storage.request"): `storage request coal 16` on the
turtle, or storage.request(item, count) from a program such as a
builder restocking. The items are pushed straight into the turtle
(turtle_<id> on the network) and the answer says how many came.

On a monitor the computer's own screen logs what happens and takes
commands: get <item> [count|stack|all], deposit, find <text>, refresh,
auto <seconds>, input <chest>, output <chest>, list, help, quit. On the
own screen a pasted line runs as a command.

Usage: storage [monitor|term] [input output]
       storage request <item> [count]
  monitor  the monitor to use (default: the first advanced one, or the
           computer's own screen); "term" forces the own screen
  input, output  peripheral names of the input and output chests,
           saved to the config (e.g. minecraft:chest_6 minecraft:chest_7)
--]]

local args = { ... }

if args[1] == "request" then
  if not args[2] then
    print("Usage: storage request <item> [count]")
    return
  end
  local count = tonumber(args[3] or "1")
  if not count or count < 1 then
    print("Error: the count must be a number above 0")
    return
  end
  print("Asking storage for " .. count .. " " .. args[2] .. "...")
  local moved, message = storage.request(args[2], math.floor(count), 10)
  print("Got " .. moved .. (message and (": " .. message) or ""))
  return
end

local config = storage.loadConfig()
if args[2] then config.input = args[2] end
if args[3] then config.output = args[3] end
if args[2] or args[3] then storage.saveConfig(config) end

local disp, err = basepanel.display(args[1], 36, 16)
if not disp then
  print("Error: " .. err)
  return
end

local previousTheme = guitheme.isChosen() and guitheme.getTheme() or nil
guitheme.setTheme("dark")

local store = storage.new(config)
local app = guiapplication.GUIApplication.new()
local root, ids

local jobs = {}          -- work for the worker loop, in order
local selectedKey = nil  -- key of the picked item
local sortBy = "count"
local query = ""
local autoStep = { 0, 10, 30, 60, 120, 300 }

local function status(text, role)
  if not ids then return end
  ids.status:setText(text)
end

local function queue(job)
  -- one refresh or deposit waiting is enough
  for _, j in ipairs(jobs) do
    if (job[1] == "refresh" or job[1] == "deposit") and j[1] == job[1] then return end
  end
  jobs[#jobs + 1] = job
  os.queueEvent("storage_job")
end

--[[
The view
--]]

local function updateCapacity()
  local used, total = store:capacity()
  local at = config.alertAt or 0.9
  ids.cap:setProgress(used, math.max(1, total), "Used " .. used .. "/" .. total .. " slots")
  ids.cap:setFillColor((total > 0 and used / total >= at) and colors.red or colors.green)
  ids.cap:repaint()
end

local function updateList()
  local found = store:search(query, sortBy)
  local rows, selectIndex = {}, nil
  for i, item in ipairs(found) do
    rows[i] = { item.displayName, item.count, key = item.key }
    if item.key == selectedKey then selectIndex = i end
  end
  ids.items:sortBy(nil)
  ids.items:setRows(rows)
  if selectIndex then ids.items:select(selectIndex) else ids.items:select(nil) end
  ids.sort:setText(sortBy == "count" and "By count" or "By name")
end

local function updateSelected()
  local item = selectedKey and store:index()[selectedKey]
  if item then
    local where = {}
    for chest, n in pairs(item.chests) do where[#where + 1] = chest:gsub("^minecraft:", "") .. " " .. n end
    table.sort(where)
    ids.picked:setText(item.displayName .. " x" .. item.count .. " (" .. table.concat(where, ", ") .. ")")
  else
    ids.picked:setText(selectedKey and "None left." or "Touch an item to pick it.")
  end
end

local function updateView()
  if not ids then return end
  updateCapacity()
  updateList()
  updateSelected()
end

--[[
Work, done in the worker loop because peripheral calls are slow
--]]

local function publishAlert(what, used, total)
  if what == "raise" then
    basepanel.setAlert("storage", string.format("Storage nearly full: %d/%d slots used", used, total), true)
  elseif what == "clear" then
    basepanel.setAlert("storage", string.format("Storage has room again: %d/%d slots used", used, total), false)
  end
end

local function describeGet(item, moved, why, target)
  local name = item and item.displayName or "items"
  if moved > 0 and not why then return "Sent " .. moved .. " " .. name .. " to " .. target end
  return "Sent " .. moved .. " " .. name .. ": " .. (why or "nothing moved")
end

local function doJob(job)
  local kind = job[1]
  if kind == "refresh" then
    status("Indexing chests...")
    store:refresh()
    local used, total = store:capacity()
    status("Indexed " .. #store.names .. " chests, " .. used .. "/" .. total .. " slots used.")
  elseif kind == "deposit" then
    if not job.quiet then status("Depositing...") end
    local stored, left, why = store:deposit()
    if stored > 0 or left > 0 or not job.quiet then
      local msg = "Deposited " .. stored .. " items" .. (left > 0 and (", " .. left .. " left: " .. (why or "?")) or "")
      if why and stored == 0 and left == 0 then msg = "Deposit: " .. why end
      basepanel.log(msg)
      status(msg)
    end
  elseif kind == "get" then
    local item = store:find(job.key)
    local target = job.target or config.output
    local moved, why = store:withdraw(job.key, job.amount, target)
    local msg = describeGet(item, moved, why, target)
    basepanel.log(msg)
    status(msg)
  elseif kind == "request" then
    local p = job.payload
    local target = storage.requestTarget(p, job.sender, peripheral.isPresent)
    local moved, why = 0, "no target on the network for computer " .. tostring(job.sender)
    if target then moved, why = store:withdraw(p.item, p.count or 1, target) end
    local msg = "Request from " .. tostring(job.sender) .. ": " .. moved .. " " .. tostring(p.item) .. (why and (" (" .. why .. ")") or "")
    basepanel.log(msg)
    status(msg)
    basepanel.publish("base.storage.result", { requestId = p.requestId, to = job.sender, item = p.item,
                                               moved = moved, ok = moved > 0, message = why })
  end
  publishAlert(store:checkSpace())
  updateView()
end

local function worker()
  queue({ "refresh" })
  while true do
    if #jobs == 0 then os.pullEvent("storage_job") end
    local job = table.remove(jobs, 1)
    if job then
      local ok, e = pcall(doJob, job)
      if not ok then status("Error: " .. tostring(e)); basepanel.log("Error: " .. tostring(e)) end
    end
  end
end

-- Auto deposit and the full re-index now and then.
local function timers()
  local lastDeposit, lastRefresh = os.clock(), os.clock()
  while true do
    sleep(1)
    local now = os.clock()
    local every = tonumber(config.autoDeposit) or 0
    if every > 0 and now - lastDeposit >= every then
      lastDeposit = now
      if store:inputCount() > 0 then queue({ "deposit", quiet = true }) end
    end
    if (config.refresh or 0) > 0 and now - lastRefresh >= config.refresh then
      lastRefresh = now
      queue({ "refresh" })
    end
  end
end

-- Requests from turtles over the bus.
local requests = basepanel.busLoop({ "base.storage.request" }, function(topic, payload, sender)
  if topic == "base.storage.request" and type(payload) == "table" and payload.item then
    queue({ "request", payload = payload, sender = sender })
  end
end)

--[[
Actions from the panel and the command line
--]]

local function get(amount)
  if not selectedKey then return status("Touch an item first.") end
  local item = store:index()[selectedKey]
  local n = storage.parseAmount(amount, item)
  if not n then return status("Bad amount: " .. tostring(amount)) end
  if not config.output or config.output == "" then return status("Set the output chest in Settings.") end
  status("Sending " .. n .. "...")
  queue({ "get", key = selectedKey, amount = n })
end

local function setSearch(text)
  query = text or ""
  ids.search:setText(query)
  updateList()
end

local function autoText(short)
  local every = tonumber(config.autoDeposit) or 0
  if short then return every > 0 and ("A:" .. every .. "s") or "A:off" end
  return every > 0 and ("Auto " .. every .. "s") or "Auto off"
end

local function saveSettings()
  storage.saveConfig(config)
  ids.auto:setText(autoText(disp.compact))
  if ids.autoSet then ids.autoSet:setText(autoText()) end
  ids.alertAt:setText(math.floor((config.alertAt or 0.9) * 100 + 0.5) .. "%")
end

-- Step the auto deposit interval; with wrap, past the longest goes
-- back to off (the one button on the Items tab cycles through them).
local function stepAuto(dir, wrap)
  local cur = tonumber(config.autoDeposit) or 0
  local idx = 1
  for i, v in ipairs(autoStep) do if v <= cur then idx = i end end
  idx = idx + dir
  if wrap and idx > #autoStep then idx = 1 end
  idx = math.max(1, math.min(#autoStep, idx))
  config.autoDeposit = autoStep[idx]
  saveSettings()
end

local function chestOptions()
  local opts = { "(none)" }
  for _, name in ipairs(store:inventories()) do opts[#opts + 1] = name end
  return opts
end

local helpText = "commands: get <item> [n|stack|all], deposit, find <text>, refresh, auto <s>, input <chest>, output <chest>, list, quit"

local function command(line)
  local w = basepanel.words(line)
  local cmd = (w[1] or ""):lower()
  if cmd == "help" or cmd == "?" then return helpText
  elseif cmd == "get" or cmd == "take" then
    if not w[2] then return "get <item> [count|stack|all]" end
    local amountWord = w[#w]
    local nameWords = {}
    for i = 2, #w do nameWords[#nameWords + 1] = w[i] end
    if #w > 2 and storage.parseAmount(amountWord, { count = math.huge, maxCount = 64 }) then
      table.remove(nameWords)
    else
      amountWord = "1"
    end
    local item, why = store:find(table.concat(nameWords, " "))
    if not item then return why end
    selectedKey = item.key
    updateSelected()
    local n = storage.parseAmount(amountWord, item)
    queue({ "get", key = item.key, amount = n })
    return "Getting " .. n .. " " .. item.displayName
  elseif cmd == "deposit" then
    queue({ "deposit" })
    return "Depositing"
  elseif cmd == "find" or cmd == "search" then
    setSearch(table.concat(w, " ", 2))
    return #store:search(query) .. " items match " .. query
  elseif cmd == "refresh" then
    queue({ "refresh" })
    return "Indexing"
  elseif cmd == "auto" then
    local n = tonumber(w[2])
    if not n or n < 0 then return "auto <seconds> (0 turns it off)" end
    config.autoDeposit = math.floor(n)
    saveSettings()
    return autoText()
  elseif cmd == "input" or cmd == "output" then
    if not w[2] then return cmd .. " is " .. tostring(config[cmd]) end
    if not peripheral.hasType(w[2], "inventory") then return w[2] .. " is not an inventory" end
    config[cmd] = w[2]
    saveSettings()
    ids[cmd .. "Pick"]:setOptions(chestOptions())
    ids[cmd .. "Pick"]:setValue(w[2])
    queue({ "refresh" })
    return cmd .. " chest is now " .. w[2]
  elseif cmd == "list" then
    local out = {}
    for i, item in ipairs(store:search(query, sortBy)) do
      if i > 10 then break end
      out[#out + 1] = item.count .. " " .. item.displayName
    end
    return #out > 0 and table.concat(out, ", ") or "storage is empty"
  end
  return "unknown command " .. cmd .. "; " .. helpText
end

--[[
Building the screen
--]]

local compact = disp.compact
local amountButtons = {}
for _, a in ipairs({ { "1", 1 }, { "16", 16 }, { "64", 64 }, { compact and "Stk" or "Stack", "stack" }, { "All", "all" } }) do
  amountButtons[#amountButtons + 1] = { type = "button", text = a[1], onPress = function() get(a[2]) end }
end

local itemsTab = {
  type = "box", title = "Items", dir = "vertical", gap = 0, children = {
    { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
      { type = "text", text = "Find:", w = 5, fgRole = "muted" },
      { type = "input", id = "search", text = "", border = false, flex = 1, h = 1, bgRole = "surface",
        onDone = function() query = ids.search:getText(); updateList() end },
      { type = "button", id = "sort", text = "By count", w = 9, onPress = function()
          sortBy = sortBy == "count" and "name" or "count"
          updateList()
        end },
    } },
    { type = "table", id = "items", flex = 1, striped = true, emptyText = "Nothing stored (yet).",
      columns = { { title = "Item", flex = 1 }, { title = "Count", width = 7, align = "right" } },
      onSelect = function(e)
        selectedKey = e.row.key
        updateSelected()
      end },
    { type = "text", id = "picked", text = "Touch an item to pick it.", h = 1, fgRole = "muted" },
    { type = "grid", rows = 1, columns = 5, gap = 1, h = 1, children = amountButtons },
    { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
      { type = "input", id = "amount", text = "", border = false, w = compact and 4 or 6, h = 1, bgRole = "surface" },
      { type = "button", text = "Get", w = compact and 4 or 5, onPress = function() get(ids.amount:getText()) end },
      { type = "button", text = "Deposit", flex = 1, onPress = function() queue({ "deposit" }) end },
      { type = "button", id = "auto", text = autoText(compact), flex = 1, onPress = function() stepAuto(1, true) end },
    } },
  },
}

local settingsTab = {
  type = "box", title = "Settings", dir = "vertical", gap = 1, padding = compact and 0 or 1, children = {
    { type = "text", text = "Input chest (deposit from)", h = 1, fgRole = "muted" },
    { type = "dropdown", id = "inputPick", options = chestOptions(), h = 1, onSelect = function()
        local v = ids.inputPick:getValue()
        config.input = v == "(none)" and "" or v
        saveSettings()
        queue({ "refresh" })
      end },
    { type = "text", text = "Output chest (items come out)", h = 1, fgRole = "muted" },
    { type = "dropdown", id = "outputPick", options = chestOptions(), h = 1, onSelect = function()
        local v = ids.outputPick:getValue()
        config.output = v == "(none)" and "" or v
        saveSettings()
        queue({ "refresh" })
      end },
    { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
      { type = "text", text = "Auto deposit", w = 13, fgRole = "muted" },
      { type = "button", text = "-", w = 3, onPress = function() stepAuto(-1) end },
      { type = "text", id = "autoSet", text = autoText(), w = 10, align = "center" },
      { type = "button", text = "+", w = 3, onPress = function() stepAuto(1) end },
    } },
    { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
      { type = "text", text = "Alert when", w = 13, fgRole = "muted" },
      { type = "button", text = "-", w = 3, onPress = function()
          config.alertAt = math.max(0.5, (config.alertAt or 0.9) - 0.05); saveSettings()
        end },
      { type = "text", id = "alertAt", text = "", w = 10, align = "center" },
      { type = "button", text = "+", w = 3, onPress = function()
          config.alertAt = math.min(1, (config.alertAt or 0.9) + 0.05); saveSettings()
        end },
    } },
    { type = "button", text = "Re-index now", h = 1, onPress = function() queue({ "refresh" }) end },
  },
}

root, ids = guibuild.build({
  type = "root", title = "Storage", term = disp.term, side = disp.side, dir = "vertical", gap = 0, children = {
    { type = "progress", id = "cap", value = 0, max = 1, h = 1 },
    { type = "tabs", id = "tabs", flex = 1, children = { itemsTab, settingsTab } },
    { type = "text", id = "status", text = "Starting...", h = 1, fgRole = "muted" },
  },
})
app:setRootContainer(root)
app:setUPS(20)
ids.inputPick:setValue(config.input ~= "" and config.input or "(none)")
ids.outputPick:setValue(config.output ~= "" and config.output or "(none)")
saveSettings()
if config.input == "" or config.output == "" then
  ids.tabs:select(2)
  status("Pick the input and output chests.")
end

basepanel.run({
  app = app, display = disp, name = "storage", commands = command,
  loops = { worker, timers, requests },
  onStatus = function(msg) status(msg) end,
})
guitheme.setTheme(previousTheme)
