--[[
Depot runs the depot computer: it keeps the list of service chests
(fuel, dump, materials) with their world positions, answers turtles
asking for the nearest one over rednet (see apis/depot.lua), and
publishes the list on the bus for turtle control's map. The computer
needs a wireless modem; a wired modem with the chests on its network
lets it read how full they are, so full dump chests and empty fuel
chests are skipped.

The screen lists the chests with their role, position, the side the
turtle stands on and how full they are, with Add, Edit and Remove. The
list is kept in depot.cfg. The same can be done from the shell before
starting it, which is handy in a startup file:

  depot add <name> <fuel|dump|materials> <x> <y> <z> <side> [peripheral]
  depot remove <name>
  depot list

side is where the turtle stands next to the chest: north, east, south,
west, above (on top, dropping down) or below. peripheral is the chest's
name on the wired network, such as minecraft:chest_0.

On a turtle the same program uses a depot:

  depot unload           empty everything at the nearest dump chest
  depot refuel [target]  take fuel at the nearest fuel chest (default 2000)
  depot find <role>      say which chest the depot would send it to

Usage: depot [add|remove|list ...]
       depot unload|refuel [target]|find <role>     (on a turtle)
--]]

local args = { ... }

--[[
On a turtle: use the depot.
--]]

if turtle then
  local cmd = args[1]
  local ok, err
  if cmd == "unload" then
    print("unloading at the depot...")
    ok, err = depot.unload()
    if ok then print("unloaded, back where it started") end
  elseif cmd == "refuel" then
    local target = tonumber(args[2]) or depot.DefaultRefuel
    print("refuelling at the depot to " .. target .. "...")
    ok, err = depot.refuel(target)
    if ok then print("fuel is now " .. tostring(turtle.getFuelLevel())) end
  elseif cmd == "find" and args[2] then
    local found, why = depot.find(args[2])
    if found then
      print(found.name .. " at " .. found.x .. " " .. found.y .. " " .. found.z .. ", stand at "
        .. found.stand.x .. " " .. found.stand.y .. " " .. found.stand.z .. ", " .. found.distance .. " blocks")
    end
    ok, err = found ~= nil, why
  else
    print("Usage: depot unload")
    print("       depot refuel [target]")
    print("       depot find <fuel|dump|materials>")
    return
  end
  if not ok then error(tostring(err), 0) end
  return
end

--[[
On the depot computer: the chest list from the shell.
--]]

local cfg = depot.loadConfig()

if args[1] == "add" then
  local c, err = depot.newChest(args[2], args[3], args[4], args[5], args[6], args[7], args[8])
  if not c then error(err, 0) end
  for i, old in ipairs(cfg.chests) do
    if old.name == c.name then table.remove(cfg.chests, i) break end
  end
  table.insert(cfg.chests, c)
  depot.saveConfig(cfg)
  print("added " .. c.name .. " (" .. c.role .. ") at " .. c.x .. " " .. c.y .. " " .. c.z)
  return
elseif args[1] == "remove" and args[2] then
  for i, old in ipairs(cfg.chests) do
    if old.name == args[2] then
      table.remove(cfg.chests, i)
      depot.saveConfig(cfg)
      print("removed " .. args[2])
      return
    end
  end
  error("no chest called " .. args[2], 0)
elseif args[1] == "list" then
  if #cfg.chests == 0 then print("no chests yet: depot add ...") end
  for _, c in ipairs(cfg.chests) do
    print(c.name .. " " .. c.role .. " " .. c.x .. " " .. c.y .. " " .. c.z .. " " .. c.access .. (c.peripheral and (" " .. c.peripheral) or ""))
  end
  return
elseif args[1] then
  print("Usage: depot [add|remove|list ...]")
  print("  depot add <name> <fuel|dump|materials> <x> <y> <z> <side> [peripheral]")
  return
end

--[[
The server with its screen.
--]]

local publishEvery = 30 -- seconds between depot.chests messages
local levelEvery = 5    -- seconds between reading the chests

local opened = (bus and bus.open and bus.open()) or turtlectl.openModem()
if not opened then
  print("Error: no modem attached")
  return
end
if bus and bus.subscribe then bus.subscribe("depot.list") end

local display = term.current()
local lvls = depot.levels(cfg.chests)
local lastRequest = "waiting for turtles"
local app = guiapplication.GUIApplication.new()
local refreshList -- set while the list screen shows

local function publish()
  if bus and bus.publish then pcall(bus.publish, "depot.chests", { chests = depot.describe(cfg.chests, lvls) }) end
end

local function newRoot(title)
  local root = guirootcontainer.GUIRootContainer.new(display)
  root:setTitle(title)
  root:setBackgroundColor(colors.black)
  root:setBorderColor(colors.gray)
  root:setTextColor(colors.white)
  return root
end

local function newLabel(text, x, y, w, color)
  local label = guitext.GUIText.new(text)
  label:setPreferredBounds(x, y, math.max(1, w), 1)
  label:setBorder(false)
  label:setBackgroundColor(colors.black)
  label:setTextColor(color or colors.white)
  return label
end

local function newButton(text, x, y, w, color, onClick)
  local button = guibutton.GUIButton.new(text)
  button:setPreferredBounds(x, y, w, 1)
  button:setBackgroundColor(color or colors.blue)
  button.pressColor = colors.lightGray
  button:setTextColor(colors.white)
  button:setBorder(false)
  button:addButtonListener(onClick)
  return button
end

local function newInput(text, x, y, w)
  local input = guiinput.GUIInput.new(text or "")
  input:setPreferredBounds(x, y, w, 1)
  input:setBorder(false)
  input:setBackgroundColor(colors.gray)
  input:setTextColor(colors.white)
  return input
end

local function setRoot(root)
  app:setRootContainer(root)
  root:setStarted(true)
  root:repaint()
end

local function fillText(c)
  local lv = lvls[c.name]
  if not lv then return c.peripheral and "?" or "-" end
  if c.role == "dump" then return lv.used .. "/" .. lv.size end
  return tostring(lv.items)
end

local showList, showEdit

showList = function(message)
  local w, h = display.getSize()
  local root = newRoot("Depot " .. (os.getComputerLabel() or os.getComputerID()))
  local tbl = guitable.GUITable.new({
    { title = "Chest", flex = 1 },
    { title = "Role", width = 5 },
    { title = "Position", width = 15 },
    { title = "Side", width = 6 },
    { title = "Fill", width = 6, align = "right" },
  })
  tbl:setPreferredBounds(1, 2, w, h - 3)
  tbl:setEmptyText("No chests: Add one")
  root:add(tbl)
  local status = newLabel(message or lastRequest, 1, h - 1, w, colors.lightGray)
  root:add(status)
  local function rows()
    local list = {}
    for i, c in ipairs(cfg.chests) do
      local color = ({ fuel = colors.orange, dump = colors.brown, materials = colors.cyan })[c.role]
      local lv = lvls[c.name]
      if lv and not depot.usable(c, lv) then color = colors.red end
      list[i] = { c.name, c.role, c.x .. " " .. c.y .. " " .. c.z, c.access, fillText(c), color = color, chest = c }
    end
    tbl:setRows(list)
  end
  rows()
  local function selected()
    local _, row = tbl:getSelected()
    return row and row.chest
  end
  local bw = math.floor((w - 3) / 4)
  root:add(newButton("Add", 1, h, bw, colors.green, function() showEdit(nil) end))
  root:add(newButton("Edit", 2 + bw, h, bw, colors.blue, function()
    local c = selected()
    if c then showEdit(c) else status:setText("Touch a chest first") end
  end))
  root:add(newButton("Remove", 3 + 2 * bw, h, bw, colors.red, function()
    local c = selected()
    if not c then return status:setText("Touch a chest first") end
    guidialog.confirm(root, "Remove", "Remove " .. c.name .. " from the depot?", function()
      for i, x in ipairs(cfg.chests) do
        if x == c then table.remove(cfg.chests, i) break end
      end
      depot.saveConfig(cfg)
      publish()
      showList("Removed " .. c.name)
    end, nil, { yes = "Remove", no = "Cancel", danger = true })
  end))
  root:add(newButton("Read", 4 + 3 * bw, h, w - 3 - 3 * bw, colors.gray, function()
    lvls = depot.levels(cfg.chests)
    rows()
    status:setText("Read the chests")
  end))
  refreshList = function(text)
    rows()
    if text then status:setText(text) end
  end
  setRoot(root)
end

-- Add (chest nil) or edit a chest.
showEdit = function(chest)
  refreshList = nil
  local w, h = display.getSize()
  local root = newRoot(chest and ("Edit " .. chest.name) or "Add a chest")
  local labelW = 11
  local fieldW = math.max(8, w - labelW - 1)
  local row = 3
  local function label(text) root:add(newLabel(text, 1, row, labelW, colors.lightGray)) end

  label("Name")
  local name = newInput(chest and chest.name or "", labelW + 1, row, fieldW)
  root:add(name)
  row = row + 2
  label("Role")
  local role = jobform.newDropdown(depot.Roles, chest and chest.role or "dump", labelW + 1, row, 12)
  root:add(role)
  row = row + 2
  label("X Y Z")
  local third = math.floor((fieldW - 2) / 3)
  local xs = newInput(chest and tostring(chest.x) or "", labelW + 1, row, third)
  local ys = newInput(chest and tostring(chest.y) or "", labelW + 2 + third, row, third)
  local zs = newInput(chest and tostring(chest.z) or "", labelW + 3 + 2 * third, row, third)
  root:add(xs) root:add(ys) root:add(zs)
  row = row + 2
  label("Turtle at")
  local access = jobform.newDropdown(depot.Access, chest and chest.access or "north", labelW + 1, row, 10)
  root:add(access)
  row = row + 2
  label("Peripheral")
  local names = { "none" }
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.hasType and peripheral.hasType(n, "inventory") then table.insert(names, n) end
  end
  if chest and chest.peripheral then
    local known = false
    for _, n in ipairs(names) do known = known or n == chest.peripheral end
    if not known then table.insert(names, chest.peripheral) end
  end
  local per = jobform.newDropdown(names, chest and chest.peripheral or "none", labelW + 1, row, math.min(fieldW, 24))
  root:add(per)
  local status = newLabel("Click a field and type", 1, h - 1, w, colors.lightGray)
  root:add(status)

  root:add(newButton("Save", 1, h, 10, colors.green, function()
    local c, err = depot.newChest(name.text, role:getValue(), xs.text, ys.text, zs.text, access:getValue(), per:getValue())
    if not c then return status:setText(err) end
    for i, x in ipairs(cfg.chests) do
      if x == chest or x.name == c.name then table.remove(cfg.chests, i) break end
    end
    table.insert(cfg.chests, c)
    depot.saveConfig(cfg)
    lvls = depot.levels(cfg.chests)
    publish()
    showList("Saved " .. c.name)
  end))
  root:add(newButton("Cancel", 12, h, 10, colors.gray, function() showList() end))
  setRoot(root)
end

--[[
Network
--]]

local function answer(sender, msg)
  -- Fresh levels for the answer, so a chest emptied a moment ago counts.
  lvls = depot.levels(cfg.chests)
  local reply = depot.answer(cfg.chests, msg, lvls, os.getComputerLabel() or ("Depot " .. os.getComputerID()))
  rednet.send(sender, reply, depot.PROTOCOL)
  if reply.ok then
    lastRequest = "#" .. sender .. " " .. tostring(msg.role) .. " -> " .. reply.name .. " (" .. reply.distance .. " blocks)"
  else
    lastRequest = "#" .. sender .. " " .. tostring(msg.role) .. ": " .. tostring(reply.message)
  end
  if refreshList then refreshList(lastRequest) end
end

local publishTimer = os.startTimer(1)
local levelTimer = os.startTimer(levelEvery)

app:addEventListener(function(event)
  if event[1] == "rednet_message" and event[4] == depot.PROTOCOL then
    local msg = event[3]
    if type(msg) == "table" and msg.type == "find" then answer(event[2], msg) end
  elseif event[1] == "timer" and event[2] == publishTimer then
    publish()
    publishTimer = os.startTimer(publishEvery)
  elseif event[1] == "timer" and event[2] == levelTimer then
    lvls = depot.levels(cfg.chests)
    if refreshList then refreshList() end
    levelTimer = os.startTimer(levelEvery)
  elseif bus and bus.handle then
    local topic = bus.handle(table.unpack(event, 1, event.n))
    if topic == "depot.list" then publish() end
  end
end)

app:setUPS(20)
showList()
app:start()
