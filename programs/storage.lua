--[[
Storage is a touch panel for a network of chests: a computer with a
wired modem on the same cable as the chests, an input chest where
items are put to be stored and an output chest where requested items
come out. Every other inventory on the network is storage. The index,
the searching and the moving of items is apis/storage.lua.

The Items tab lists everything in storage with its count. Touch a row
to pick an item, then 1, 16, 64, Stack or All to send that many to the
output chest (or type a number in the box and press Get). The list can
be narrowed with the search box (touching it on a monitor opens an
on-screen keyboard, which shows how many items match as you type; x
clears it) and sorted by name or count. Deposit
moves everything in the input chest into storage, topping up stacks of
the same item first; Auto deposits by itself every few seconds. The bar
at the top is how many storage slots are used, and turning red (with
an "alert" on the bus) when nearly full. The Settings tab picks the
input and output chests, the auto deposit interval and the alert level,
kept in /storage.cfg. Sort chests condenses partial stacks and puts each
kind of item together, chest by chest in name order, a few moves at a
time so items can still be taken out meanwhile; pressing it again stops.

The input and output chests must be on the same wired network as the
storage chests. A chest touching the computer is also seen under the
side's name (left, top ...), which the chests on the cable cannot
reach, so side chests are not offered or used as storage.

The Craft tab crafts recipes with a crafty turtle running crafter
(programs/turtle/crafter.lua) beside the crafting chest, a chest on the
network picked in Settings. Touch a recipe, then 1, 16, 64 or Max (or a
number and Craft) for that many items. The storage moves the
ingredients into the crafting chest, the turtle crafts them and puts
the results back, and the storage puts them away, a stack's worth of
crafts at a time. The Recipe tab makes and edits recipes: touch a
square of the 3x3 grid, search storage for its item on the on-screen
keyboard, and Save. A recipe learns what it makes the first time it is
crafted, and takes that item's name if it was saved without one.
Recipes are kept in /recipes.cfg (apis/crafting.lua). Built-in recipes
(apis/recipebook.lua: planks, sticks, torches, chests, tools, armour
and more) are listed too; the Craft tab shows the ones storage has the
items for, or All, and Find narrows the list. Editing a built-in recipe
saves a copy, which then takes its place.

A turtle with a wired modem on the same network can ask for items over
the bus ("base.storage.request"): `storage request coal 16` on the
turtle, or storage.request(item, count) from a program such as a
builder restocking. The items are pushed straight into the turtle
(turtle_<id> on the network) and the answer says how many came.

On a monitor the computer's own screen logs what happens and takes
commands: get <item> [count|stack|all], deposit, find <text>, refresh,
sort [stop], craft <recipe> [count|max], craft stop, recipes [all] [text], auto
<seconds>, input <chest>, output <chest>, craftchest <chest>, list,
help, quit. On the
own screen a pasted line runs as a command.

Remote: "storage remote" on a pocket computer (or any computer) with a
wireless or ender modem uses the storage at the base from afar, with
the same Items and Craft tabs. Each remote picks its own chest on the
storage network on its Settings tab, such as an ender chest whose
other half its player carries: Get sends items there, and Deposit
empties that chest into storage. The storage computer needs a wireless
or ender modem too, and keeps whose chest is whose in /storage.cfg, so
several people can each have their own chest and computer. Recipes
are made at the base and can be crafted from a remote. See
apis/remotestorage.lua. At the base, "remotes" lists the remote chests
and "unremote <id>" forgets one.

Usage: storage [monitor|term] [input output]
       storage remote [monitor|term]
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

-- A remote shows the storage at the base (apis/remotestorage.lua).
local remote = args[1] == "remote"
if remote then table.remove(args, 1) end

local config, saveConfig
if remote then
  config = remotestorage.loadConfig()
  saveConfig = remotestorage.saveConfig
else
  config = storage.loadConfig()
  saveConfig = storage.saveConfig
  if args[2] then config.input = args[2] end
  if args[3] then config.output = args[3] end
  if args[2] or args[3] then storage.saveConfig(config) end
end

local disp, err = basepanel.display(args[1], 36, 16)
if not disp then
  print("Error: " .. err)
  return
end

local previousTheme = guitheme.isChosen() and guitheme.getTheme() or nil
guitheme.setTheme("dark")

local store = remote and remotestorage.new(config) or storage.new(config)
local app = guiapplication.GUIApplication.new()
local root, ids

local jobs = {}          -- work for the worker loop, in order
local selectedKey = nil  -- key of the picked item
local sortBy = "count"
local query = ""
local sorting = nil      -- the sort job while one is running
-- A remote has no Recipe tab: recipes are made at the base.
local ItemsTab, CraftTab, RecipeTab, SettingsTab = 1, 2, 3, 4
if remote then RecipeTab, SettingsTab = nil, 3 end

-- Crafting: the recipes, the picked one, the craft under way and the
-- crafter turtle last heard on the bus.
-- recipes are the saved ones; book adds the built-in ones, and is what
-- the Craft tab lists and craft finds by name. selectedRecipe is one of
-- book's recipes.
local recipes = crafting.loadRecipes()
local book = recipebook.merge(recipes)
local selectedRecipe = nil
local recipeQuery = ""
local craftJob = nil
local crafterId, crafterLabel, crafterSeen, crafterBusy = nil, nil, 0, false
local craftCounter = 0
local startCraft -- defined with the panel's actions, used by remotes' requests too
-- The recipe being edited: its index (nil for a new one), grid, the
-- square picked and the items matching the last search.
local edit = { index = nil, grid = {}, cell = nil, matches = {} }
local problemShown = false
local autoStep = { 0, 10, 30, 60, 120, 300 }

local function status(text, role)
  if not ids then return end
  ids.status:setText(text)
end

local function queue(job)
  -- one refresh, deposit or sort waiting is enough
  for _, j in ipairs(jobs) do
    if (job[1] == "refresh" or job[1] == "deposit" or job[1] == "sort") and j[1] == job[1] then return end
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
    ids.picked:setText(item.displayName .. " x" .. item.count .. (#where > 0 and (" (" .. table.concat(where, ", ") .. ")") or ""))
  else
    ids.picked:setText(selectedKey and "None left." or "Touch an item to pick it.")
  end
end

local function updateSortButton()
  if ids and ids.sortChests then
    ids.sortChests:setText(sorting and "Stop sorting" or "Sort chests")
    ids.sortChests:repaint()
  end
end

-- An item's name for people, from the index or what is known of it.
local function itemName(key)
  if not key then return "?" end
  if crafting.isTag(key) then return recipebook.tagName(key) end
  local item = store:index()[key]
  if item then return item.displayName end
  local info = store.info[key]
  return info and info.displayName or storage.prettyName(key)
end

local function crafterText()
  if remote then return "Crafted at " .. (store.label or "the base storage") .. "." end
  if not config.craftChest or config.craftChest == "" then return "Pick the crafting chest in Settings." end
  if not crafterId then return "No crafter: run crafter on a crafty turtle by the crafting chest." end
  local who = (crafterLabel or "turtle") .. " " .. crafterId
  local age = os.clock() - crafterSeen
  if age > 90 then return "Crafter " .. who .. " not heard from for " .. math.floor(age) .. "s." end
  if craftJob then return "Crafter " .. who .. ": " .. craftJob.recipe.name .. " " .. craftJob.done .. "/" .. craftJob.crafts end
  return "Crafter " .. who .. " is ready."
end

-- What the items in storage are enough for: items when the recipe's
-- output is known, crafts (5x) when not.
local function canText(r, n)
  n = n or crafting.maxCrafts(r, store:index())
  if r.output then return tostring(n * r.output.count) end
  return n .. "x"
end

-- The saved recipe's index, or nil for a built-in one.
local function savedIndex(r)
  for i, other in ipairs(recipes) do
    if other == r then return i end
  end
  return nil
end

-- After the saved recipes change: list them with the built-in ones, and
-- keep the picked recipe (by name, so a saved copy replaces the
-- built-in one it was made from).
local function rebuildBook()
  book = recipebook.merge(recipes)
  if selectedRecipe then
    local name = selectedRecipe.name:lower()
    selectedRecipe = nil
    for _, r in ipairs(book) do
      if r.name:lower() == name then selectedRecipe = r; break end
    end
  end
end

-- The recipes the Craft tab lists, each with how many crafts storage
-- has the items for: those matching Find, and unless All is on only
-- the saved ones and the ones that can be made now.
local function shownRecipes()
  local q = recipeQuery:lower()
  local all = config.recipeFilter == "all"
  local items = store:index()
  local out = {}
  for _, r in ipairs(book) do
    if q == "" or r.name:lower():find(q, 1, true) then
      local n = crafting.maxCrafts(r, items)
      if all or not r.builtin or n > 0 or r == selectedRecipe then out[#out + 1] = { recipe = r, crafts = n } end
    end
  end
  return out
end

local function updateRecipes()
  if not ids then return end
  local rows, selectIndex = {}, nil
  for i, s in ipairs(shownRecipes()) do
    local r = s.recipe
    rows[i] = { r.name, r.output and tostring(r.output.count) or "?", canText(r, s.crafts), recipe = r }
    if r == selectedRecipe then selectIndex = i end
  end
  local all = config.recipeFilter == "all"
  ids.recipes:setEmptyText(recipeQuery ~= "" and ("No recipe matches " .. recipeQuery .. ".")
    or (all and "No recipes." or "Nothing to make yet: touch Can make for All."))
  ids.recipes:sortBy(nil)
  ids.recipes:setRows(rows)
  ids.recipes:select(selectIndex)
  ids.recipeFilter:setText(all and "All" or "Can make")
  local r = selectedRecipe
  if r then
    local parts = {}
    for key, per in pairs(crafting.needs(r)) do parts[#parts + 1] = per .. " " .. itemName(key) end
    table.sort(parts)
    ids.recipePicked:setText(r.name .. ": " .. table.concat(parts, ", "))
  else
    ids.recipePicked:setText("Touch a recipe to pick it.")
  end
  ids.crafter:setText(crafterText())
  ids.craftStop:setText(craftJob and "Stop" or "New")
end

-- The recipe editor: the nine squares and the matches list.
local function updateEditor()
  if not ids or not ids.cell1 then return end
  for cell = 1, 9 do
    local b = ids["cell" .. cell]
    local key = edit.grid[cell]
    b:setText(key and crafting.shortName(itemName(key), math.max(1, b.w - 1)) or "-")
    if cell == edit.cell then
      b:setBackgroundColor(guitheme.color("warn"))
      b:setTextColor(colors.black)
    elseif key then
      b:setBackgroundColor(guitheme.color("button"))
      b:setTextColor(guitheme.color("buttonText"))
    else
      b:setBackgroundColor(guitheme.color("surface"))
      b:setTextColor(guitheme.color("muted"))
    end
    b:repaint()
  end
  local rows = {}
  for i, item in ipairs(edit.matches) do rows[i] = { item.displayName, item.count, key = item.key } end
  ids.matches:setRows(rows)
  ids.editing:setText(edit.index and recipes[edit.index] and ("Editing " .. recipes[edit.index].name)
    or (edit.from and ("Copy of built-in " .. edit.from.name)) or "New recipe")
end

-- A remote's Settings: the storage computer and the chest picked.
local remoteChoices = nil
local function updateRemote()
  if not remote or not ids then return end
  local who = store.server and ((store.label or "Storage") .. " (computer " .. store.server .. ")") or "Not found yet."
  ids.serverText:setText(who)
  local opts = { "(none)" }
  for _, name in ipairs(store.choices or {}) do opts[#opts + 1] = name end
  local key = table.concat(opts, ",")
  if key ~= remoteChoices then
    remoteChoices = key
    ids.remoteChest:setOptions(opts)
  end
  ids.remoteChest:setValue(store.chest or "(none)")
end

local function updateView()
  if not ids then return end
  updateRemote()
  updateCapacity()
  updateList()
  updateSelected()
  updateRecipes()
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

-- Tell the player once when the input or output chest cannot work.
local function showProblem()
  local problem = store:problem()
  if not problem then return false end
  basepanel.log(problem)
  status("Check the input and output chests in Settings.")
  if not problemShown then
    problemShown = true
    ids.tabs:select(SettingsTab)
    guidialog.alert(root, "Chests", problem)
  end
  return true
end

local function sortStep(job)
  if not job.state then
    status("Sorting: indexing chests...")
    store:refresh()
    job.state = store:startSort()
    sorting = job
    updateSortButton()
  end
  local finished, why = false, nil
  if job.stop then
    finished, why = true, "stopped"
  else
    finished, why = store:sortStep(job.state, 16)
  end
  local done = job.state.done
  if finished then
    sorting = nil
    local msg
    if done == 0 and not why then msg = "Already sorted."
    elseif why then msg = "Sorting " .. why .. " after " .. done .. " moves."
    else msg = "Sorted: " .. done .. " moves." end
    basepanel.log(msg)
    status(msg)
    updateSortButton()
  else
    status("Sorting: " .. done .. " moves done, about " .. storage.sortLeft(job.state) .. " to go.")
    -- carry on after anything else waiting, such as a request
    table.insert(jobs, job)
  end
end

local function saveRecipes()
  crafting.saveRecipes(recipes)
  rebuildBook()
end

-- What a craft made so far, in words.
local function craftSummary(job)
  local r = job.recipe
  local what = r.output and (r.output.displayName or r.output.name) or r.name
  return "Crafted " .. crafting.itemsFrom(r, job.done) .. " " .. what
end

local function craftFinish(job, msg)
  if craftJob == job then craftJob = nil end
  basepanel.log(msg)
  status(msg)
  updateRecipes()
end

-- Move one batch of ingredients into the crafting chest and ask the
-- crafter, or finish when there is nothing more to make.
local function craftBatch(job)
  local left = job.crafts - job.done
  if job.stop then return craftFinish(job, craftSummary(job) .. "; stopped.") end
  if left <= 0 then return craftFinish(job, craftSummary(job) .. ".") end
  local chest = config.craftChest
  if not chest or chest == "" then return craftFinish(job, "Crafting: pick the crafting chest in Settings first.") end
  if not crafterId then return craftFinish(job, "Crafting: no crafter heard. Run crafter on the crafty turtle.") end
  if store:inputCount(chest) > 0 then store:deposit(chest) end
  if store:inputCount(chest) > 0 then
    return craftFinish(job, "Crafting stopped: the crafting chest is not empty and storage cannot take what is in it.")
  end
  -- this batch's items: the planks (and so on) storage has most of
  local r = crafting.resolve(job.recipe, store:index())
  local k = crafting.batchSize(r, left, function(key) return store:maxCount(key) end)
  local can, short = crafting.maxCrafts(r, store:index())
  k = math.min(k, can)
  -- a recipe never crafted makes one first, to learn what it makes
  if not r.output then k = math.min(k, 1) end
  if k < 1 then
    local _, anyShort = crafting.maxCrafts(job.recipe, store:index())
    local msg = "not enough " .. itemName(anyShort or short)
    return craftFinish(job, job.done > 0 and (craftSummary(job) .. "; then " .. msg .. ".") or ("Cannot craft " .. r.name .. ": " .. msg .. "."))
  end
  local grid = {}
  for _, cell in ipairs(crafting.cells(r)) do
    local key = r.grid[cell]
    local moved, why = store:withdraw(key, k, chest, cell)
    if moved < k then
      store:deposit(chest)
      return craftFinish(job, "Crafting stopped: could not move " .. itemName(key) .. " to the crafting chest (" .. tostring(why) .. ").")
    end
    grid[cell] = { name = (key:gsub("#.*$", "")), count = k }
  end
  craftCounter = craftCounter + 1
  job.batchId = os.getComputerID() .. ":" .. craftCounter
  job.waiting = true
  job.deadline = os.clock() + 30 + k
  basepanel.publish("base.craft.job", { jobId = job.batchId, to = crafterId, crafts = k, grid = grid, name = r.name })
  status("Crafting " .. k .. "x " .. r.name .. " (" .. job.done .. "/" .. job.crafts .. " done)...")
  updateRecipes()
end

-- The crafter finished a batch: put away what it made and go on.
local function craftDone(p)
  local job = craftJob
  if not job or not job.waiting or p.jobId ~= job.batchId then return end
  job.waiting = false
  store:deposit(config.craftChest)
  local crafted = tonumber(p.crafted) or 0
  job.done = job.done + crafted
  local r = job.recipe
  local out = p.output
  if type(out) == "table" and out.name and tonumber(out.count) then
    local learned = not r.output
    if learned or r.output.name ~= out.name or r.output.count ~= out.count then
      r.output = { name = out.name, count = out.count, displayName = out.displayName, maxCount = out.maxCount }
      if r.autoName and out.displayName then
        r.name = out.displayName
        r.autoName = nil
      end
      saveRecipes()
    end
    -- a number of items asked for before the recipe's output was known
    if learned and job.wantItems then job.crafts = math.min(job.crafts, crafting.craftsFor(r, job.wantItems)) end
  end
  if not p.ok then return craftFinish(job, craftSummary(job) .. "; the crafter stopped: " .. tostring(p.why)) end
  if crafted < 1 then return craftFinish(job, "Crafting stopped: the crafter made nothing.") end
  craftBatch(job)
end

--[[
Answers to remotes (storage remote on a pocket computer)
--]]

-- Is a remote's message for this storage computer?
local function forMe(p)
  return type(p) == "table" and (p.server == nil or p.server == os.getComputerID())
end

local function remoteChest(id)
  local r = config.remotes and config.remotes[id]
  return r and r.chest or nil
end

local function answer(topic, to, p, payload)
  payload.requestId = p.requestId
  payload.to = to
  basepanel.publish(topic, payload)
end

-- The item list, the remote's chest and what it may pick, the recipes.
local function answerList(sender, p)
  local items = {}
  for key, item in pairs(store:index()) do
    items[#items + 1] = { key = key, name = item.name, nbt = item.nbt, displayName = item.displayName,
                          count = item.count, maxCount = item.maxCount }
  end
  local used, total = store:capacity()
  answer("base.storage.items", sender, p, {
    label = os.getComputerLabel() or ("Storage " .. os.getComputerID()),
    items = items, used = used, total = total,
    chest = remoteChest(sender), choices = store:remoteChoices(sender), recipes = recipes,
  })
end

local function answerRegister(sender, p)
  local ok, why = store:setRemote(sender, p.chest, p.label)
  if ok then
    saveConfig(config)
    queue({ "refresh" })
    basepanel.log("Remote " .. tostring(p.label or sender) .. " uses " .. tostring(p.chest))
  end
  answer("base.storage.registered", sender, p, { ok = ok, chest = remoteChest(sender), why = why })
end

local function doJob(job)
  local kind = job[1]
  if kind == "refresh" and remote then
    status("Asking the storage...")
    local ok, why = store:refresh()
    if ok then
      recipes = store.recipes or {}
      rebuildBook()
      local used, total = store:capacity()
      status((store.label or "Storage") .. ": " .. used .. "/" .. total .. " slots used.")
    else
      status("No answer: " .. tostring(why))
    end
    showProblem()
  elseif kind == "refresh" then
    status("Indexing chests...")
    store:refresh()
    local used, total = store:capacity()
    status("Indexed " .. #store.names .. " chests, " .. used .. "/" .. total .. " slots used.")
    showProblem()
  elseif kind == "register" then
    local ok, why = store:register(job.chest)
    local msg = ok and ("Your chest is now " .. job.chest .. ".") or ("Could not use " .. tostring(job.chest) .. ": " .. tostring(why))
    basepanel.log(msg)
    status(msg)
    if ok then
      problemShown = false
      store:refresh()
    end
  elseif kind == "remoteCraft" then
    local msg = store:craft(job.recipe, job.count)
    basepanel.log(tostring(msg))
    status(tostring(msg))
    store:refresh()
  elseif kind == "remoteDeposit" then
    local chest = remoteChest(job.sender)
    local stored, left, why = 0, 0, "no chest picked for computer " .. tostring(job.sender)
    if chest then stored, left, why = store:deposit(chest) end
    local msg = "Remote " .. tostring(job.sender) .. " deposited " .. stored .. " items" .. (why and (" (" .. why .. ")") or "")
    basepanel.log(msg)
    status(msg)
    answer("base.storage.deposited", job.sender, job.payload, { stored = stored, left = left, why = why })
  elseif kind == "sort" then
    sortStep(job)
  elseif kind == "craft" then
    craftBatch(job.job)
  elseif kind == "craftDone" then
    craftDone(job.payload)
  elseif kind == "craftTimeout" then
    local cj = craftJob
    if cj and cj.waiting and os.clock() > cj.deadline then
      cj.waiting = false
      store:deposit(config.craftChest)
      craftFinish(cj, "Crafting stopped: the crafter did not answer. " .. crafterText())
    end
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
    if remote then target = "your chest" end
    local moved, why = store:withdraw(job.key, job.amount, target)
    local msg = describeGet(item, moved, why, target)
    basepanel.log(msg)
    status(msg)
  elseif kind == "request" then
    local p = job.payload
    local target = (type(p.target) ~= "string" or p.target == "") and remoteChest(job.sender)
      or storage.requestTarget(p, job.sender, peripheral.isPresent)
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
  -- a crafter that is already running says hello
  basepanel.publish("base.craft.ping", {})
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
    if craftJob and craftJob.waiting and now > craftJob.deadline then queue({ "craftTimeout" }) end
    if ids and math.floor(now) % 5 == 0 then ids.crafter:setText(crafterText()) end
  end
end

-- Requests from turtles over the bus.
local requests = basepanel.busLoop({ "base.storage.request", "base.craft.hello", "base.craft.done",
    "base.storage.list", "base.storage.register", "base.storage.deposit", "base.storage.craft" }, function(topic, payload, sender)
  if topic == "base.storage.request" and forMe(payload) and payload.item then
    queue({ "request", payload = payload, sender = sender })
  elseif topic == "base.storage.list" and forMe(payload) then
    answerList(sender, payload)
  elseif topic == "base.storage.register" and forMe(payload) then
    answerRegister(sender, payload)
  elseif topic == "base.storage.deposit" and forMe(payload) then
    queue({ "remoteDeposit", payload = payload, sender = sender })
  elseif topic == "base.storage.craft" and forMe(payload) then
    local r = crafting.findRecipe(book, payload.recipe)
    local msg = r and startCraft(r, payload.count or 1) or ("No recipe called " .. tostring(payload.recipe) .. " at the base.")
    answer("base.storage.crafting", sender, payload, { message = msg })
  elseif topic == "base.craft.hello" and type(payload) == "table" then
    if config.crafter == nil or config.crafter == sender then
      crafterId, crafterLabel, crafterSeen, crafterBusy = sender, payload.label, os.clock(), payload.busy
      if ids then ids.crafter:setText(crafterText()) end
    end
  elseif topic == "base.craft.done" and type(payload) == "table" then
    if payload.to == nil or payload.to == os.getComputerID() then
      crafterSeen = os.clock()
      queue({ "craftDone", payload = payload })
    end
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
  if remote then
    if not store.chest then return status("Pick your chest in Settings.") end
  elseif not config.output or config.output == "" then
    return status("Set the output chest in Settings.")
  end
  status("Sending " .. n .. "...")
  queue({ "get", key = selectedKey, amount = n })
end

local function setSearch(text)
  query = text or ""
  ids.search:setText(query)
  updateList()
end

local function searchHint(text)
  local n = #store:search(text)
  return n == 1 and "1 item matches" or (n .. " items match")
end

-- Start sorting, or stop the sort that is running.
local function toggleSort()
  if sorting then
    sorting.stop = true
    return "Stopping the sort"
  end
  queue({ "sort" })
  status("Sorting...")
  return "Sorting"
end

-- Craft count items of recipe r (or as many as storage allows with
-- "max"). Returns a message.
startCraft = function(r, count)
  if not r then return "Touch a recipe first." end
  if remote then
    queue({ "remoteCraft", recipe = r.name, count = count })
    return "Asking the base to craft " .. r.name .. "..."
  end
  if craftJob then return "Already crafting " .. craftJob.recipe.name .. "; stop it first." end
  local crafts, wantItems
  if count == "max" then
    crafts = crafting.maxCrafts(r, store:index())
  else
    count = tonumber(count)
    if not count or count < 1 then return "Bad amount." end
    wantItems = math.floor(count)
    crafts = crafting.craftsFor(r, wantItems)
  end
  local can, short = crafting.maxCrafts(r, store:index())
  if can < 1 then return "Cannot craft " .. r.name .. ": not enough " .. itemName(short) .. "." end
  if crafts < 1 then return "Nothing to craft." end
  craftJob = { recipe = r, crafts = crafts, done = 0, wantItems = wantItems }
  queue({ "craft", job = craftJob })
  updateRecipes()
  return "Crafting " .. (r.output and (crafting.itemsFrom(r, crafts) .. " ") or (crafts .. "x ")) .. r.name
end

local function stopCraft()
  if not craftJob then return "Not crafting." end
  craftJob.stop = true
  return "Stopping after this batch."
end

-- The editor: start a new recipe, or load a recipe. A built-in one is
-- loaded as a new recipe of the same name, which replaces it once saved.
local function editRecipe(r)
  local i = r and savedIndex(r)
  edit = { index = i, from = r and not i and r or nil, grid = {}, cell = nil, matches = {} }
  if r then for cell, key in pairs(r.grid) do edit.grid[cell] = key end end
  ids.recipeName:setText(r and r.name or "")
  ids.cellHint:setText("Touch a square.")
  updateEditor()
end

local function setCell(key)
  if not edit.cell then return end
  edit.grid[edit.cell] = key
  ids.cellHint:setText("Square " .. edit.cell .. ": " .. (key and itemName(key) or "empty"))
  edit.matches = {}
  updateEditor()
end

local function cellHint(text)
  if text == "" then return "Done with nothing empties the square" end
  local found = store:search(text, "name")
  if #found == 0 then return "Nothing in storage matches" end
  if #found == 1 then return found[1].displayName end
  return found[1].displayName .. " and " .. (#found - 1) .. " more"
end

-- Find the item for the picked square: one match (or an exact name)
-- fills it, several are listed to touch.
local function searchCell(text)
  if text == "" then return setCell(nil) end
  local found = store:search(text, "name")
  for _, item in ipairs(found) do
    if item.displayName:lower() == text:lower() or item.name == text then found = { item }; break end
  end
  if #found == 1 then return setCell(found[1].key) end
  edit.matches = found
  ids.cellHint:setText(#found == 0 and ("Nothing in storage matches " .. text .. ".")
    or ("Touch the item for square " .. edit.cell .. "."))
  updateEditor()
end

local function pickCell(cell)
  edit.cell = cell
  updateEditor()
  guikeyboard.open(root, "Square " .. cell .. ": find an item", "", searchCell, { hint = cellHint })
end

local function saveRecipe()
  if not next(edit.grid) then return status("Put at least one item in the grid first.") end
  local name = ids.recipeName:getText():gsub("^%s+", ""):gsub("%s+$", "")
  local r = edit.index and recipes[edit.index]
  if not r and edit.from then
    -- a copy of a built-in recipe keeps what it makes while its grid is the same
    r = { grid = {} }
    for cell, key in pairs(edit.from.grid) do r.grid[cell] = key end
    if edit.from.output then
      r.output = {}
      for k, v in pairs(edit.from.output) do r.output[k] = v end
    end
  end
  r = r or { grid = {} }
  local auto = nil
  if name == "" then
    name = r.name or ("Recipe " .. (#recipes + 1))
    auto = r.name == nil or r.autoName or nil
  elseif name == r.name then
    auto = r.autoName
  end
  for i, other in ipairs(recipes) do
    if i ~= edit.index and other.name:lower() == name:lower() then
      return status("There is a recipe called " .. name .. " already.")
    end
  end
  local same = true
  for cell = 1, 9 do if r.grid[cell] ~= edit.grid[cell] then same = false end end
  r.name, r.autoName = name, auto
  r.grid = {}
  for cell, key in pairs(edit.grid) do r.grid[cell] = key end
  if not same then r.output = nil end
  if not edit.index then
    recipes[#recipes + 1] = r
    edit.index = #recipes
  end
  edit.from = nil
  selectedRecipe = r
  saveRecipes()
  updateRecipes()
  updateEditor()
  status("Saved " .. name .. (r.output and "." or "; it learns what it makes the first time it is crafted."))
  ids.tabs:select(CraftTab)
end

local function deleteRecipe()
  local i = edit.index
  if not i or not recipes[i] then
    return status(edit.from and "Built-in recipes cannot be deleted." or "Nothing saved to delete.")
  end
  guidialog.confirm(root, "Delete", "Delete the recipe " .. recipes[i].name .. "?", function()
    local gone = table.remove(recipes, i)
    -- a built-in recipe of the same name comes back
    if selectedRecipe == gone then selectedRecipe = nil end
    saveRecipes()
    editRecipe(nil)
    updateRecipes()
    status("Deleted.")
  end, nil, { yes = "Delete", no = "Keep", danger = true })
end

local function autoText(short)
  local every = tonumber(config.autoDeposit) or 0
  if short then return every > 0 and ("A:" .. every .. "s") or "A:off" end
  return every > 0 and ("Auto " .. every .. "s") or "Auto off"
end

local function saveSettings()
  saveConfig(config)
  ids.auto:setText(autoText(disp.compact))
  if ids.autoSet then ids.autoSet:setText(autoText()) end
  if ids.alertAt then ids.alertAt:setText(math.floor((config.alertAt or 0.9) * 100 + 0.5) .. "%") end
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
  if remote then return opts end
  for _, name in ipairs(store:chestChoices()) do opts[#opts + 1] = name end
  return opts
end

local helpText = "commands: get <item> [n|stack|all], deposit, find <text>, refresh, sort [stop], craft <recipe> [n|max], craft stop, recipes [all] [text], auto <s>, input <chest>, output <chest>, craftchest <chest>, remotes, unremote <id>, list, quit"

local remoteHelp = "commands: get <item> [n|stack|all], deposit (from your chest), find <text>, refresh, craft <recipe> [n|max], recipes [all] [text], auto <s>, chest <name>, list, quit"

local function command(line)
  local w = basepanel.words(line)
  local cmd = (w[1] or ""):lower()
  if remote then
    if cmd == "help" or cmd == "?" then return remoteHelp end
    if cmd == "chest" then
      if not w[2] then return "your chest is " .. tostring(store.chest or "not picked yet") end
      queue({ "register", chest = w[2] })
      return "Asking for " .. w[2]
    end
    if cmd == "sort" or cmd == "input" or cmd == "output" or cmd == "craftchest" or cmd == "remotes" or cmd == "unremote" then
      return cmd .. " is done at the base storage"
    end
  elseif cmd == "remotes" then
    local out = {}
    for id, r in pairs(config.remotes or {}) do out[#out + 1] = tostring(r.label or ("computer " .. id)) .. " (" .. id .. "): " .. r.chest end
    table.sort(out)
    return #out > 0 and table.concat(out, ", ") or "no remotes"
  elseif cmd == "unremote" then
    local id = tonumber(w[2])
    if not id or not (config.remotes and config.remotes[id]) then return "unremote <computer id> (see remotes)" end
    store:setRemote(id, nil)
    saveSettings()
    queue({ "refresh" })
    return "Forgot computer " .. id .. "'s chest"
  end
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
  elseif cmd == "sort" then
    if (w[2] or ""):lower() == "stop" then
      if not sorting then return "Not sorting" end
      return toggleSort()
    end
    if sorting then return "Already sorting; sort stop stops it" end
    return toggleSort()
  elseif cmd == "craft" then
    if (w[2] or ""):lower() == "stop" and #w == 2 then return stopCraft() end
    if not w[2] then return "craft <recipe> [count|max]" end
    local count = 1
    local last = (w[#w] or ""):lower()
    local nameEnd = #w
    if #w > 2 and (last == "max" or tonumber(last)) then
      count = last == "max" and "max" or tonumber(last)
      nameEnd = #w - 1
    end
    local r, why = crafting.findRecipe(book, table.concat(w, " ", 2, nameEnd))
    if not r then return why end
    selectedRecipe = r
    return startCraft(r, count)
  elseif cmd == "recipes" then
    -- the saved ones and those storage has the items for, or with
    -- "all" every one; any other words narrow it by name
    local all = (w[2] or ""):lower() == "all"
    local q = table.concat(w, " ", all and 3 or 2):lower()
    local out = {}
    local items = store:index()
    for _, r in ipairs(book) do
      if q == "" or r.name:lower():find(q, 1, true) then
        local n = crafting.maxCrafts(r, items)
        if all or not r.builtin or n > 0 then out[#out + 1] = r.name .. " (can make " .. canText(r, n) .. ")" end
      end
    end
    if #out == 0 then return all and "no recipes match" or "nothing to make; recipes all lists every recipe" end
    return table.concat(out, ", ")
  elseif cmd == "auto" then
    local n = tonumber(w[2])
    if not n or n < 0 then return "auto <seconds> (0 turns it off)" end
    config.autoDeposit = math.floor(n)
    saveSettings()
    return autoText()
  elseif cmd == "input" or cmd == "output" or cmd == "craftchest" then
    local field = cmd == "craftchest" and "craftChest" or cmd
    local pick = cmd == "craftchest" and "craftPick" or (cmd .. "Pick")
    if not w[2] then return cmd .. " is " .. tostring(config[field]) end
    if not peripheral.hasType(w[2], "inventory") then return w[2] .. " is not an inventory" end
    if storage.isSide(w[2]) and store:networked() then
      return w[2] .. " is the side of the computer the chest touches; the chests on the cable cannot reach it there. Put a wired modem on it and use its network name."
    end
    config[field] = w[2]
    saveSettings()
    ids[pick]:setOptions(chestOptions())
    ids[pick]:setValue(w[2])
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

local function setRecipeSearch(text)
  recipeQuery = text or ""
  ids.recipeSearch:setText(recipeQuery)
  updateRecipes()
end

local function recipeHint(text)
  local q, n = (text or ""):lower(), 0
  for _, r in ipairs(book) do
    if r.name:lower():find(q, 1, true) then n = n + 1 end
  end
  return n == 1 and "1 recipe matches" or (n .. " recipes match")
end

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
        keyboardTitle = "Search items", keyboardHint = searchHint,
        onDone = function() query = ids.search:getText(); updateList() end },
      { type = "button", text = "x", w = 3, onPress = function() setSearch("") end },
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
      { type = "input", id = "amount", text = "", border = false, w = compact and 4 or 6, h = 1, bgRole = "surface",
        keyboardTitle = "How many?" },
      { type = "button", text = "Get", w = compact and 4 or 5, onPress = function() get(ids.amount:getText()) end },
      { type = "button", text = "Deposit", flex = 1, onPress = function() queue({ "deposit" }) end },
      { type = "button", id = "auto", text = autoText(compact), flex = 1, onPress = function() stepAuto(1, true) end },
    } },
  },
}

local craftTab = {
  type = "box", title = "Craft", dir = "vertical", gap = 0, children = {
    { type = "text", id = "crafter", text = "", h = 1, fgRole = "muted" },
    { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
      { type = "text", text = "Find:", w = 5, fgRole = "muted" },
      { type = "input", id = "recipeSearch", text = "", border = false, flex = 1, h = 1, bgRole = "surface",
        keyboardTitle = "Find a recipe", keyboardHint = recipeHint,
        onDone = function() recipeQuery = ids.recipeSearch:getText(); updateRecipes() end },
      { type = "button", text = "x", w = 3, onPress = function() setRecipeSearch("") end },
      { type = "button", id = "recipeFilter", text = "Can make", w = 10, onPress = function()
          config.recipeFilter = config.recipeFilter == "all" and "can" or "all"
          saveConfig(config)
          updateRecipes()
        end },
    } },
    { type = "table", id = "recipes", flex = 1, striped = true, emptyText = "",
      columns = { { title = "Recipe", flex = 1 }, { title = "Makes", width = 6, align = "right" },
                  { title = "Can", width = 6, align = "right" } },
      onSelect = function(e)
        selectedRecipe = e.row.recipe
        updateRecipes()
      end },
    { type = "text", id = "recipePicked", text = "", h = 1, fgRole = "muted" },
    { type = "grid", rows = 1, columns = 4, gap = 1, h = 1, children = {
      { type = "button", text = "1", onPress = function() status(startCraft(selectedRecipe, 1)) end },
      { type = "button", text = "16", onPress = function() status(startCraft(selectedRecipe, 16)) end },
      { type = "button", text = "64", onPress = function() status(startCraft(selectedRecipe, 64)) end },
      { type = "button", text = "Max", onPress = function() status(startCraft(selectedRecipe, "max")) end },
    } },
    { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
      { type = "input", id = "craftAmount", text = "", border = false, w = compact and 4 or 6, h = 1, bgRole = "surface",
        keyboardTitle = "How many to make?" },
      { type = "button", text = "Craft", w = 7, onPress = function()
          status(startCraft(selectedRecipe, ids.craftAmount:getText()))
        end },
      { type = "button", text = "Edit", flex = 1, onPress = function()
          if remote then return status("Recipes are made and edited at the base storage.") end
          if not selectedRecipe then return status("Touch a recipe first.") end
          editRecipe(selectedRecipe)
          ids.tabs:select(RecipeTab)
          if edit.from then status("Saving makes a copy that replaces the built-in " .. edit.from.name .. ".") end
        end },
      { type = "button", id = "craftStop", text = "New", flex = 1, onPress = function()
          if craftJob then return status(stopCraft()) end
          if remote then return status("Recipes are made and edited at the base storage.") end
          editRecipe(nil)
          ids.tabs:select(RecipeTab)
        end },
    } },
  },
}

local cellButtons = {}
for cell = 1, 9 do
  cellButtons[cell] = { type = "button", id = "cell" .. cell, text = "-", onPress = function() pickCell(cell) end }
end

local recipeTab = {
  type = "box", title = "Recipe", dir = "vertical", gap = 0, children = {
    { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
      { type = "text", text = "Name:", w = 5, fgRole = "muted" },
      { type = "input", id = "recipeName", text = "", border = false, flex = 1, h = 1, bgRole = "surface",
        keyboardTitle = "Recipe name" },
    } },
    { type = "text", id = "editing", text = "New recipe", h = 1, fgRole = "muted" },
    { type = "box", dir = "horizontal", gap = 1, flex = 1, children = {
      { type = "grid", rows = 3, columns = 3, gap = 1, w = compact and 23 or 32, children = cellButtons },
      { type = "box", dir = "vertical", gap = 0, flex = 1, children = {
        { type = "text", id = "cellHint", text = "Touch a square.", h = 1, fgRole = "muted" },
        { type = "table", id = "matches", flex = 1, striped = true, emptyText = "",
          columns = { { title = "Item", flex = 1 }, { title = "Have", width = 6, align = "right" } },
          onSelect = function(e) setCell(e.row.key) end },
      } },
    } },
    { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
      { type = "button", text = "Save", flex = 1, onPress = saveRecipe },
      { type = "button", text = "New", flex = 1, onPress = function() editRecipe(nil) end },
      { type = "button", text = compact and "Empty" or "Empty square", flex = 1, onPress = function()
          if not edit.cell then return status("Touch a square first.") end
          setCell(nil)
        end },
      { type = "button", text = "Delete", flex = 1, onPress = deleteRecipe },
    } },
  },
}

local settingsTab = {
  type = "box", title = "Settings", dir = "vertical", gap = (compact or disp.h < 24) and 0 or 1,
  padding = (compact or disp.h < 24) and 0 or 1, children = {
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
    { type = "text", text = "Crafting chest (beside the crafty turtle)", h = 1, fgRole = "muted" },
    { type = "dropdown", id = "craftPick", options = chestOptions(), h = 1, onSelect = function()
        local v = ids.craftPick:getValue()
        config.craftChest = v == "(none)" and "" or v
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
    { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
      { type = "button", text = "Re-index now", flex = 1, onPress = function() queue({ "refresh" }) end },
      { type = "button", id = "sortChests", text = "Sort chests", flex = 1, onPress = function() toggleSort() end },
    } },
  },
}

local remoteSettingsTab = {
  type = "box", title = "Settings", dir = "vertical", gap = (compact or disp.h < 20) and 0 or 1, padding = compact and 0 or 1, children = {
    { type = "text", text = "Storage computer", h = 1, fgRole = "muted" },
    { type = "text", id = "serverText", text = "Not found yet.", h = 1 },
    { type = "text", text = compact and "My chest (items come here)" or "My chest (items are delivered here)", h = 1, fgRole = "muted" },
    { type = "dropdown", id = "remoteChest", options = { "(none)" }, h = 1, onSelect = function()
        local v = ids.remoteChest:getValue()
        if v ~= "(none)" and v ~= store.chest then
          status("Asking for " .. v .. "...")
          queue({ "register", chest = v })
        end
      end },
    { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
      { type = "text", text = compact and "Auto dep." or "Auto deposit", w = compact and 9 or 13, fgRole = "muted" },
      { type = "button", text = "-", w = 3, onPress = function() stepAuto(-1) end },
      { type = "text", id = "autoSet", text = autoText(), w = 10, align = "center" },
      { type = "button", text = "+", w = 3, onPress = function() stepAuto(1) end },
    } },
    { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
      { type = "button", text = "Refresh", flex = 1, onPress = function() queue({ "refresh" }) end },
      { type = "button", text = "Find storage", flex = 1, onPress = function()
          store.server, config.server = nil, nil
          saveSettings()
          queue({ "refresh" })
        end },
    } },
  },
}

local tabList = remote and { itemsTab, craftTab, remoteSettingsTab } or { itemsTab, craftTab, recipeTab, settingsTab }

root, ids = guibuild.build({
  type = "root", title = remote and "Storage remote" or "Storage", term = disp.term, side = disp.side, dir = "vertical", gap = 0, children = {
    { type = "progress", id = "cap", value = 0, max = 1, h = 1 },
    { type = "tabs", id = "tabs", flex = 1, children = tabList,
      onChange = function(e)
        -- a tab's components are only sized once it is shown
        local index = e.index
        if index == RecipeTab then updateEditor() elseif index == CraftTab then updateRecipes() end
      end },
    { type = "text", id = "status", text = "Starting...", h = 1, fgRole = "muted" },
  },
})
app:setRootContainer(root)
app:setUPS(20)
if not remote then
  ids.inputPick:setValue(config.input ~= "" and config.input or "(none)")
  ids.outputPick:setValue(config.output ~= "" and config.output or "(none)")
  ids.craftPick:setValue(config.craftChest ~= "" and config.craftChest or "(none)")
end
saveSettings()
updateRecipes()
updateEditor()
if not remote and (config.input == "" or config.output == "") then
  ids.tabs:select(SettingsTab)
  status("Pick the input and output chests.")
end

basepanel.run({
  app = app, display = disp, name = "storage", commands = command,
  loops = remote and { worker, timers } or { worker, timers, requests },
  onStatus = function(msg) status(msg) end,
})
guitheme.setTheme(previousTheme)
