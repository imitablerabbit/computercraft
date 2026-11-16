--[[
Depot is a set of service chests at known places in the world (fuel to
take, a dump for what turtles dig, materials) and the way turtles find
and use them. A depot computer (programs/depot.lua) keeps the list,
reads how full each chest is through inventory peripherals on its wired
network when it can, and answers "the nearest <role> chest from x, y, z"
over rednet. Turtles then walk there with nav and back.

A chest is { name, role, x, y, z, access, peripheral }: role is one of
Roles, x, y, z its block in Minecraft coordinates (F3), access the side
of the chest the turtle stands on (north, east, south, west, above or
below; above means on top of it, dropping down), and peripheral its
name on the depot's wired network (minecraft:chest_0, ...) or nil when
the depot cannot see it. Full dump chests and empty fuel chests are
skipped. Fullness counts slots: a chest whose every slot holds
something is full, which is a little early for part-filled stacks.

Protocol (rednet, PROTOCOL "depot"):
  turtle -> broadcast  { type = "find", role, x, y, z, exclude = { names } }
  depot  -> turtle     { type = "chest", ok = true, role, name, x, y, z,
                         stand = { x, y, z }, face, used, size, items,
                         distance, depot } or { type = "chest", ok = false,
                         role, message }
  face is the heading (0 north .. 3 west) to face the chest from the
  stand block, or "down" / "up" when it is below or above.
The depot also publishes its chests on the bus as "depot.chests" ({
chests = { ... } }, every 30 seconds and when asked with "depot.list"),
which turtle control's map shows.

Turtle side (needs a wireless modem, and nav calibrated with gps, which
these do by themselves when gps answers):
  depot.find(role [, opts]) -> chest reply or nil, reason
  depot.unload([opts]) -> true or false, reason: goes to the nearest
      dump chest, drops everything except opts.keep (item names or Lua
      patterns) and opts.keepSlots, tries the next chest when one fills
      up, and comes back to the same block and heading
  depot.refuel([target, opts]) -> true or false, reason: goes to the
      nearest fuel chest, takes fuel items and burns them up to target
      fuel (default DefaultRefuel), puts back what is left, comes back
  opts.dig lets nav dig its way (never through chests or computers).
--]]

PROTOCOL = "depot"
ConfigFile = "depot.cfg"
Roles = { "fuel", "dump", "materials" }
Access = { "north", "east", "south", "west", "above", "below" }
FindTimeout = 2       -- seconds to wait for a depot to answer
DefaultRefuel = 2000  -- fuel refuel aims for without a target

-- Where the turtle stands for each access side, and which way it faces.
local Offsets = {
  north = { 0, 0, -1, 2 }, east = { 1, 0, 0, 3 }, south = { 0, 0, 1, 0 }, west = { -1, 0, 0, 1 },
  above = { 0, 1, 0, "down" }, below = { 0, -1, 0, "up" },
}

local function contains(list, v)
  for _, x in ipairs(list) do
    if x == v then return true end
  end
  return false
end

--[[
The depot's side
--]]

-- The block a turtle stands on to reach the chest, and which way it
-- faces from there (a heading, or "down" / "up").
function standFor(chest)
  local o = Offsets[chest.access or "north"]
  if not o then return nil end
  return { x = chest.x + o[1], y = chest.y + o[2], z = chest.z + o[3] }, o[4]
end

-- Is this a usable chest record? Returns true or false, why.
function checkChest(c)
  if type(c) ~= "table" then return false, "not a chest" end
  if type(c.name) ~= "string" or c.name == "" then return false, "a chest needs a name" end
  if not contains(Roles, c.role) then return false, "role must be one of " .. table.concat(Roles, ", ") end
  if not (tonumber(c.x) and tonumber(c.y) and tonumber(c.z)) then return false, "x, y and z must be numbers" end
  if not Offsets[c.access] then return false, "access must be one of " .. table.concat(Access, ", ") end
  return true
end

-- A chest record from loose values (text from a command line or form).
function newChest(name, role, x, y, z, access, peripheralName)
  local c = {
    name = name, role = role, x = tonumber(x), y = tonumber(y), z = tonumber(z),
    access = access or "north",
  }
  if peripheralName and peripheralName ~= "" and peripheralName ~= "none" then c.peripheral = peripheralName end
  local ok, err = checkChest(c)
  if not ok then return nil, err end
  c.x, c.y, c.z = math.floor(c.x), math.floor(c.y), math.floor(c.z)
  return c
end

function loadConfig(path)
  path = path or ConfigFile
  local cfg = { chests = {} }
  if not fs.exists(path) then return cfg end
  local f = fs.open(path, "r")
  if not f then return cfg end
  local data = textutils.unserialize(f.readAll() or "")
  f.close()
  if type(data) == "table" and type(data.chests) == "table" then
    for _, c in ipairs(data.chests) do
      if checkChest(c) then table.insert(cfg.chests, c) end
    end
  end
  return cfg
end

function saveConfig(cfg, path)
  local f = fs.open(path or ConfigFile, "w")
  if not f then return false end
  f.write(textutils.serialize({ chests = cfg.chests }))
  f.close()
  return true
end

-- How full an inventory peripheral is: { used, size, items } (slots
-- holding something, slots, items in all), or nil when it cannot be read.
function level(peripheralName)
  if not peripheralName then return nil end
  local ok, size = pcall(peripheral.call, peripheralName, "size")
  if not ok or not tonumber(size) then return nil end
  local ok2, list = pcall(peripheral.call, peripheralName, "list")
  if not ok2 or type(list) ~= "table" then return nil end
  local used, items = 0, 0
  for _, item in pairs(list) do
    used = used + 1
    items = items + (item.count or 0)
  end
  return { used = used, size = size, items = items }
end

-- The levels of every chest that has a peripheral, by chest name.
function levels(chests)
  local out = {}
  for _, c in ipairs(chests) do
    if c.peripheral then out[c.name] = level(c.peripheral) end
  end
  return out
end

-- Can a turtle use this chest now? A dump needs a free slot, a fuel or
-- materials chest something in it. Unknown levels count as fine.
function usable(chest, lv)
  if not lv then return true end
  if chest.role == "dump" and lv.used >= lv.size then return false, "full" end
  if chest.role ~= "dump" and lv.items == 0 then return false, "empty" end
  return true
end

-- The nearest usable chest with the role from x, y, z (measured from
-- its stand block), skipping the names in exclude. Returns the chest
-- and its distance, or nil and why.
function nearest(chests, role, x, y, z, lvls, exclude)
  local best, bestD, why = nil, nil, nil
  for _, c in ipairs(chests) do
    if c.role == role and not contains(exclude or {}, c.name) then
      local ok, reason = usable(c, lvls and lvls[c.name])
      if ok then
        local s = standFor(c)
        local d = math.abs(s.x - x) + math.abs(s.y - y) + math.abs(s.z - z)
        if not best or d < bestD then best, bestD = c, d end
      else
        why = why or (c.name .. " is " .. reason)
      end
    end
  end
  if not best then return nil, why and ("no " .. role .. " chest to use: " .. why) or ("no " .. role .. " chest") end
  return best, bestD
end

-- The answer to a find request.
function answer(chests, req, lvls, depotName)
  local role = req and req.role
  if not contains(Roles, role) then
    return { type = "chest", ok = false, role = role, message = "unknown role " .. tostring(role) }
  end
  local x, y, z = tonumber(req.x), tonumber(req.y), tonumber(req.z)
  if not (x and y and z) then
    return { type = "chest", ok = false, role = role, message = "where are you? (x, y, z missing)" }
  end
  local c, d = nearest(chests, role, x, y, z, lvls, type(req.exclude) == "table" and req.exclude or nil)
  if not c then return { type = "chest", ok = false, role = role, message = d } end
  local stand, face = standFor(c)
  local lv = lvls and lvls[c.name]
  return {
    type = "chest", ok = true, role = role, name = c.name, x = c.x, y = c.y, z = c.z,
    stand = stand, face = face, distance = d, depot = depotName,
    used = lv and lv.used, size = lv and lv.size, items = lv and lv.items,
  }
end

-- The chests as published on the bus, with their levels.
function describe(chests, lvls)
  local out = {}
  for i, c in ipairs(chests) do
    local lv = lvls and lvls[c.name]
    out[i] = { name = c.name, role = c.role, x = c.x, y = c.y, z = c.z, access = c.access,
      used = lv and lv.used, size = lv and lv.size, items = lv and lv.items }
  end
  return out
end

--[[
The turtle's side
--]]

local function openRednet()
  if rednet.isOpen() then return true end
  if bus and bus.open and bus.open() then return true end
  local modem = peripheral.find("modem")
  if not modem then return false end
  rednet.open(peripheral.getName(modem))
  return rednet.isOpen()
end

-- Make sure nav knows the turtle's Minecraft position, calibrating
-- with gps when it does not yet. Returns true or false, why.
function ensurePosition(opts)
  local s = nav.status()
  if s.calibrated and s.sure and s.headingSure then return true end
  if s.calibrated and not s.sure and nav.locate() then
    s = nav.status()
    if s.headingSure then return true end
  end
  local ok, err = nav.calibrate({ dig = opts and opts.dig })
  if not ok then return false, "nav needs Minecraft coordinates for the depot: " .. tostring(err) end
  return true
end

-- Ask the depots for the nearest chest with a role. opts.exclude lists
-- chest names to skip, opts.timeout the seconds to wait.
function find(role, opts)
  opts = opts or {}
  if not openRednet() then return nil, "no modem to ask the depot" end
  local ok, err = ensurePosition(opts)
  if not ok then return nil, err end
  local x, y, z = nav.position()
  rednet.broadcast({ type = "find", role = role, x = x, y = y, z = z, exclude = opts.exclude }, PROTOCOL)
  local timeout = opts.timeout or FindTimeout
  local deadline = os.clock() + timeout
  local best, why = nil, nil
  while true do
    local left = deadline - os.clock()
    if left <= 0 then break end
    local sender, msg = rednet.receive(PROTOCOL, left)
    if not sender then break end
    if type(msg) == "table" and msg.type == "chest" and msg.role == role then
      if msg.ok and type(msg.stand) == "table" then
        if not best or (msg.distance or 0) < (best.distance or 0) then best = msg end
        -- other depots get a moment to answer too
        deadline = math.min(deadline, os.clock() + 0.5)
      elseif not msg.ok then
        why = why or msg.message
      end
    end
  end
  if not best then return nil, why or "no depot answered" end
  return best
end

-- The drop and suck functions for a face.
local function sides(face)
  if face == "down" then return turtle.dropDown, turtle.suckDown end
  if face == "up" then return turtle.dropUp, turtle.suckUp end
  return turtle.drop, turtle.suck
end

-- Walk to a chest's stand block and face it.
local function visit(chest, opts)
  local s = chest.stand
  local heading = type(chest.face) == "number" and chest.face or nil
  local ok, err = nav.goTo(s.x, s.y, s.z, { dig = opts.dig, heading = heading })
  if not ok then return false, "could not reach " .. tostring(chest.name) .. ": " .. tostring(err) end
  return true
end

local function goBack(start, opts)
  local ok, err = nav.goTo(start.x, start.y, start.z, { dig = opts.dig, heading = start.h })
  if not ok then return false, "could not get back: " .. tostring(err) end
  return true
end

-- Should this item stay in the turtle?
local function kept(slot, detail, opts)
  if contains(opts.keepSlots or {}, slot) then return true end
  for _, k in ipairs(opts.keep or {}) do
    if detail.name == k then return true end
    local ok, found = pcall(string.find, detail.name, k)
    if ok and found then return true end
  end
  return false
end

-- Drop everything not kept. Returns true when it all went.
local function dropAll(drop, opts)
  local selected = turtle.getSelectedSlot()
  local all = true
  for slot = 1, 16 do
    local detail = turtle.getItemDetail(slot)
    if detail and not kept(slot, detail, opts) then
      turtle.select(slot)
      drop()
      if turtle.getItemCount(slot) > 0 then all = false end
    end
  end
  turtle.select(selected)
  return all
end

-- Has the turtle anything to unload?
local function hasLoad(opts)
  for slot = 1, 16 do
    local detail = turtle.getItemDetail(slot)
    if detail and not kept(slot, detail, opts) then return true end
  end
  return false
end

function unload(opts)
  opts = opts or {}
  if not hasLoad(opts) then return true end
  local ok, err = ensurePosition(opts)
  if not ok then return false, err end
  local x, y, z, h = nav.position()
  local start = { x = x, y = y, z = z, h = h }
  local tried, emptied, why = {}, false, nil
  for attempt = 1, 4 do
    local chest, ferr = find("dump", { exclude = tried, dig = opts.dig })
    if not chest then why = ferr break end
    local vok, verr = visit(chest, opts)
    if not vok then why = verr break end
    local drop = sides(chest.face)
    if dropAll(drop, opts) then
      emptied = true
      break
    end
    why = chest.name .. " is full"
    table.insert(tried, chest.name)
  end
  local bok, berr = goBack(start, opts)
  if not emptied then return false, why or "could not unload" end
  if not bok then return false, berr end
  return true
end

local function emptySlot()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then return slot end
  end
  return nil
end

-- Take fuel from the chest in front (or below / above) and burn it up
-- to target. Leftover fuel goes back; anything else taken (an empty
-- bucket, a stray item) stays in the turtle. Returns why it stopped
-- short, or nil when it reached the target.
local function takeFuel(face, target)
  local drop, suck = sides(face)
  local selected = turtle.getSelectedSlot()
  local strays, why = 0, nil
  while turtle.getFuelLevel() < target do
    local slot = emptySlot()
    if not slot then why = "no free slot" break end
    turtle.select(slot)
    if not suck() then why = "empty" break end
    if turtle.refuel(0) then
      local before = turtle.getFuelLevel()
      turtle.refuel(1)
      local each = turtle.getFuelLevel() - before
      local count = turtle.getItemCount(slot)
      if each > 0 and count > 0 and turtle.getFuelLevel() < target then
        turtle.refuel(math.min(count, math.ceil((target - turtle.getFuelLevel()) / each)))
      end
      if turtle.getItemCount(slot) > 0 and turtle.refuel(0) then drop() end
    else
      strays = strays + 1
      if strays >= 4 then why = "no fuel in it" break end
    end
  end
  turtle.select(selected)
  return why
end

function refuel(target, opts)
  opts = opts or {}
  target = tonumber(target) or DefaultRefuel
  local limit = turtle.getFuelLimit()
  if limit ~= "unlimited" then target = math.min(target, limit) end
  local fuel = turtle.getFuelLevel()
  if fuel == "unlimited" or fuel >= target then return true end
  local ok, err = ensurePosition(opts)
  if not ok then return false, err end
  local x, y, z, h = nav.position()
  local start = { x = x, y = y, z = z, h = h }
  local tried, why = {}, nil
  while turtle.getFuelLevel() < target do
    local chest, ferr = find("fuel", { exclude = tried, dig = opts.dig })
    if not chest then why = ferr break end
    local vok, verr = visit(chest, opts)
    if not vok then why = verr break end
    local short = takeFuel(chest.face, target)
    if not short then break end
    why = chest.name .. ": " .. short
    if short == "no free slot" then break end
    table.insert(tried, chest.name)
  end
  local bok, berr = goBack(start, opts)
  if turtle.getFuelLevel() < target then
    return false, "fuel " .. turtle.getFuelLevel() .. " of " .. target .. ": " .. tostring(why)
  end
  if not bok then return false, berr end
  return true
end
