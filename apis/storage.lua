--[[
Storage keeps an index of a network of chests and moves items in and
out of it. A computer with a wired modem sees every chest on the cable
as a generic inventory peripheral (minecraft:chest_0, ...). One of them
is the input chest, where items are put to be stored, one is the output
chest, where requested items are delivered, and every other inventory
on the network is storage.

  local s = storage.new({ input = "minecraft:chest_6", output = "minecraft:chest_7" })
  s:refresh()                          -- list every chest (in parallel)
  for _, item in ipairs(s:search("coal", "count")) do print(item.count, item.displayName) end
  local moved, why = s:withdraw("minecraft:coal", 16)
  local stored, left, why = s:deposit()

Peripheral calls are slow in game (about a tick each), so listing is
done many chests at a time with parallel.waitForAll, and the index is
kept up to date from what this program moves instead of listing again.
refresh(names) lists only the chests given; a full refresh now and then
catches changes made by hand.

A chest touching the computer is seen under the name of that side
(left, top ...), not its name on the network, and the chests on the
cable cannot push items to or from it. So the storage chests are the
network's inventories, and side ones only when the input or output
chest is itself on a side (a small setup with no cable at all).
problem() says when the input or output is a side that the network
cannot reach.

sort() condenses partial stacks and lays every kind of item out one
after another, chest by chest; see "Sorting" below.

Items are keyed by name, plus the NBT hash for items that carry data
(an enchanted book and a plain one do not stack). The display name and
stack size come from getItemDetail, asked once per kind of item.

new(config, opts): opts.peripheral replaces the peripheral API, which is
how the tests run it against fake chests.
--]]

-- Defaults for the config file storage.loadConfig creates.
DefaultConfig = {
  input = "",           -- peripheral name of the input chest
  output = "",          -- peripheral name of the output chest
  craftChest = "",      -- chest beside the crafty turtle (see apis/crafting.lua)
  remotes = {},         -- computer id -> { chest, label }: each remote's own chest
  exclude = {},         -- other inventories that are not storage
  autoDeposit = 0,      -- seconds between automatic deposits, 0 for off
  refresh = 60,         -- seconds between full re-indexes
  alertAt = 0.9,        -- fraction of slots used that raises the alert
}

ConfigFile = "/storage.cfg"

-- How many peripheral calls run at once.
Batch = 32

--[[
Config files
--]]

local function copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end

-- Read a config file, filling in defaults for anything missing. When
-- the file does not exist it is written with the defaults, so there is
-- something to edit. Returns the config and whether it was created.
function loadConfig(path, defaults)
  path = path or ConfigFile
  defaults = defaults or DefaultConfig
  local config = copy(defaults)
  local created = false
  if fs.exists(path) then
    local h = fs.open(path, "r")
    local data = h and textutils.unserialize(h.readAll() or "")
    if h then h.close() end
    if type(data) == "table" then
      for k, v in pairs(data) do config[k] = v end
    end
  else
    saveConfig(config, path)
    created = true
  end
  return config, created
end

function saveConfig(config, path)
  local h = fs.open(path or ConfigFile, "w")
  if not h then return false end
  h.write(textutils.serialize(config))
  h.close()
  return true
end

--[[
Helpers
--]]

-- The sides of a computer. A chest there is reached by the side's
-- name, not over the wired network.
Sides = { top = true, bottom = true, left = true, right = true, front = true, back = true }

function isSide(name)
  return Sides[name] == true
end

-- A peripheral error in words a player can act on.
function explain(err)
  err = tostring(err)
  local target = err:match("Target '(.-)' does not exist")
  if target then
    return target .. " cannot be reached: all the chests must be on the same wired network"
  end
  return err
end

-- The key items are indexed by.
function keyOf(stack)
  if stack.nbt then return stack.name .. "#" .. stack.nbt end
  return stack.name
end

-- A readable name when getItemDetail has not been asked yet:
-- minecraft:oak_log -> Oak Log.
function prettyName(name)
  local short = tostring(name):gsub("^[^:]*:", ""):gsub("#.*$", "")
  return (short:gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

-- Run functions many at a time and wait for them all.
function runBatched(fns, size)
  size = size or Batch
  for i = 1, #fns, size do
    local group = {}
    for j = i, math.min(#fns, i + size - 1) do group[#group + 1] = fns[j] end
    if #group == 1 then group[1]() else parallel.waitForAll(table.unpack(group)) end
  end
end

-- Turn an amount word into a number of items: a number, "stack" (one
-- stack of this item), "all", or nil for bad input.
function parseAmount(word, item)
  if type(word) == "number" then return word > 0 and math.floor(word) or nil end
  word = tostring(word or ""):lower()
  if word == "all" then return item and item.count or math.huge end
  if word == "stack" then return item and item.maxCount or 64 end
  local n = tonumber(word)
  if n and n >= 1 then return math.floor(n) end
  return nil
end

--[[
The storage object
--]]

local Storage = {}
Storage.__index = Storage
-- The class, for apis/remotestorage.lua, which shares its searching.
Class = Storage

function new(config, opts)
  opts = opts or {}
  local s = setmetatable({
    config = config or copy(DefaultConfig),
    p = opts.peripheral or peripheral,
    chests = {},       -- name -> { size, slots = { [slot] = { name, count, nbt } } }
    names = {},        -- storage chest names, in the order deposits try them
    info = {},         -- key -> { displayName, maxCount }
    dirty = true,      -- the item index needs rebuilding
    items = nil,
  }, Storage)
  return s
end

function Storage:call(name, method, ...)
  return self.p.call(name, method, ...)
end

-- Is name a storage chest (an inventory that is not the input, the
-- output or excluded)?
function Storage:isStorage(name)
  local c = self.config
  if name == c.input or name == c.output or name == c.craftChest then return false end
  for _, r in pairs(c.remotes or {}) do
    if r.chest == name then return false end
  end
  -- an ender chest is someone's, picked or not yet
  if name:find("ender_chest", 1, true) then return false end
  if isSide(name) ~= self:onSides() then return false end
  for _, x in ipairs(c.exclude or {}) do if x == name then return false end end
  if name:match("^turtle_") or name:match("^computer_") then return false end
  return self.p.hasType(name, "inventory") == true
end

-- Whether the chests in use are the ones on the computer's sides,
-- because the input (or else the output) chest is on one.
function Storage:onSides()
  local c = self.config
  local io = c.input
  if not io or io == "" then io = c.output end
  return io ~= nil and io ~= "" and isSide(io)
end

-- Is there any inventory on a wired network (not on a side)?
function Storage:networked()
  for _, name in ipairs(self.p.getNames()) do
    if not isSide(name) and self.p.hasType(name, "inventory") then return true end
  end
  return false
end

-- Why the input and output chests cannot work together with the
-- storage chests, or nil when they can: a chest given by the side of
-- the computer it touches while the other chests are on the cable.
function Storage:problem()
  local c = self.config
  if not self:networked() then return nil end
  for _, which in ipairs({ "input", "output" }) do
    local name = c[which]
    if name and isSide(name) then
      return "The " .. which .. " chest is set to " .. name .. ", the side of the computer it touches, "
        .. "and chests on the cable cannot reach it there. Put a wired modem on it, connect it to "
        .. "the cable and pick its network name (minecraft:chest_N) instead."
    end
  end
  return nil
end

-- The inventories that can be the input or output chest: those on the
-- network, or the side ones when there is no network.
function Storage:chestChoices()
  local out, sides = {}, {}
  for _, name in ipairs(self:inventories()) do
    if isSide(name) then sides[#sides + 1] = name else out[#out + 1] = name end
  end
  if #out == 0 then return sides end
  return out
end

--[[
Remote chests. A remote (storage remote on a pocket computer, see
apis/remotestorage.lua) has its own chest on the network, such as an
ender chest, that its items are delivered to and deposited from. The
chests are kept in config.remotes by computer id and are not storage,
and nor is any ender chest (a name with ender_chest in it), so the
storage never fills one before its owner has picked it.
--]]

-- The remote that has chest, as its id and record, or nil.
function Storage:remoteOf(chest)
  for id, r in pairs(self.config.remotes or {}) do
    if r.chest == chest then return id, r end
  end
  return nil
end

-- The chests remote id may pick: those on the network other than the
-- input, output and crafting chests and the chests of other remotes.
function Storage:remoteChoices(id)
  local c = self.config
  local out = {}
  for _, name in ipairs(self:chestChoices()) do
    local owner = self:remoteOf(name)
    if name ~= c.input and name ~= c.output and name ~= c.craftChest and (owner == nil or owner == id)
        and not name:match("^turtle_") and not name:match("^computer_") then
      out[#out + 1] = name
    end
  end
  return out
end

-- Give remote id the chest (nil to forget it). Returns true, or false
-- and why.
function Storage:setRemote(id, chest, label)
  local c = self.config
  c.remotes = c.remotes or {}
  if chest == nil or chest == "" then
    c.remotes[id] = nil
    return true
  end
  local owner, r = self:remoteOf(chest)
  if owner and owner ~= id then
    return false, chest .. " is already the chest of " .. tostring(r.label or ("computer " .. owner))
  end
  local ok = false
  for _, name in ipairs(self:remoteChoices(id)) do
    if name == chest then ok = true end
  end
  if not ok then return false, chest .. " is not a chest on the storage network that can be used" end
  c.remotes[id] = { chest = chest, label = label }
  return true
end

-- Every inventory peripheral this computer can see, storage or not.
function Storage:inventories()
  local out = {}
  for _, name in ipairs(self.p.getNames()) do
    if self.p.hasType(name, "inventory") then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

-- Find the storage chests. Returns their names.
function Storage:discover()
  local names = {}
  for _, name in ipairs(self.p.getNames()) do
    if self:isStorage(name) then names[#names + 1] = name end
  end
  -- chest_2 before chest_10
  table.sort(names, function(a, b)
    local pa, na = a:match("^(.-)(%d+)$")
    local pb, nb = b:match("^(.-)(%d+)$")
    if pa and pb and pa == pb then return tonumber(na) < tonumber(nb) end
    return a < b
  end)
  self.names = names
  for name in pairs(self.chests) do
    local keep = false
    for _, n in ipairs(names) do if n == name then keep = true end end
    if not keep then self.chests[name] = nil end
  end
  self.dirty = true
  return names
end

-- List chests again: the names given, or every storage chest after
-- discovering them anew. Chests that fail to answer (taken away) are
-- dropped from the index. Item details for new kinds of items are
-- fetched afterwards.
function Storage:refresh(names)
  if not names then names = self:discover() end
  local fns = {}
  for _, name in ipairs(names) do
    fns[#fns + 1] = function()
      local ok, size = pcall(self.call, self, name, "size")
      local ok2, list = pcall(self.call, self, name, "list")
      if ok and ok2 and type(list) == "table" then
        local slots = {}
        for slot, st in pairs(list) do
          slots[slot] = { name = st.name, count = st.count, nbt = st.nbt }
        end
        self.chests[name] = { size = size or 27, slots = slots }
      else
        self.chests[name] = nil
      end
    end
  end
  runBatched(fns)
  self.dirty = true
  self:fetchDetails()
end

-- Ask getItemDetail once for every kind of item without details yet.
function Storage:fetchDetails()
  local wanted = {}
  for _, name in ipairs(self.names) do
    local chest = self.chests[name]
    if chest then
      for slot, st in pairs(chest.slots) do
        local key = keyOf(st)
        if not self.info[key] and not wanted[key] then wanted[key] = { name, slot } end
      end
    end
  end
  local fns = {}
  for key, where in pairs(wanted) do
    fns[#fns + 1] = function() self:detailFrom(key, where[1], where[2]) end
  end
  runBatched(fns)
  if #fns > 0 then self.dirty = true end
end

-- Learn an item's display name and stack size from a slot holding it.
function Storage:detailFrom(key, chest, slot)
  local ok, d = pcall(self.call, self, chest, "getItemDetail", slot)
  if ok and type(d) == "table" then
    self.info[key] = { displayName = d.displayName or prettyName(key), maxCount = d.maxCount or 64 }
  else
    self.info[key] = self.info[key] or { displayName = prettyName(key), maxCount = 64 }
  end
  return self.info[key]
end

function Storage:maxCount(key)
  local i = self.info[key]
  return i and i.maxCount or 64
end

-- The item index: key -> { key, name, nbt, displayName, count,
-- maxCount, chests = { [chest] = count }, stacks }.
function Storage:index()
  if not self.dirty and self.items then return self.items end
  local items = {}
  for _, cname in ipairs(self.names) do
    local chest = self.chests[cname]
    if chest then
      for slot, st in pairs(chest.slots) do
        local key = keyOf(st)
        local item = items[key]
        if not item then
          local info = self.info[key] or {}
          item = { key = key, name = st.name, nbt = st.nbt, count = 0, stacks = 0, chests = {},
                   displayName = info.displayName or prettyName(st.name), maxCount = info.maxCount or 64 }
          items[key] = item
        end
        item.count = item.count + st.count
        item.stacks = item.stacks + 1
        item.chests[cname] = (item.chests[cname] or 0) + st.count
      end
    end
  end
  self.items = items
  self.dirty = false
  return items
end

-- One indexed item by key, by exact name, or by a unique part of its
-- name or display name. Returns the item, or nil and why.
function Storage:find(text)
  local items = self:index()
  if items[text] then return items[text] end
  for key, item in pairs(items) do
    if item.name == text or item.name == "minecraft:" .. text then return item end
  end
  local found = self:search(text)
  if #found == 1 then return found[1] end
  for _, item in ipairs(found) do
    if item.displayName:lower() == tostring(text):lower() then return item end
  end
  if #found == 0 then return nil, "no " .. tostring(text) .. " in storage" end
  return nil, #found .. " items match " .. tostring(text)
end

-- Items whose name or display name contains query (no case), sorted
-- by "count" (most first) or "name".
function Storage:search(query, sortBy)
  query = tostring(query or ""):lower()
  local out = {}
  for _, item in pairs(self:index()) do
    if query == "" or item.name:lower():find(query, 1, true) or item.displayName:lower():find(query, 1, true) then
      out[#out + 1] = item
    end
  end
  table.sort(out, function(a, b)
    if sortBy == "count" and a.count ~= b.count then return a.count > b.count end
    if a.displayName ~= b.displayName then return a.displayName < b.displayName end
    return a.key < b.key
  end)
  return out
end

-- Slots used and slots in all, over the storage chests.
function Storage:capacity()
  local used, total = 0, 0
  for _, name in ipairs(self.names) do
    local chest = self.chests[name]
    if chest then
      total = total + chest.size
      for _ in pairs(chest.slots) do used = used + 1 end
    end
  end
  return used, total
end

-- Change the cached count of a slot by delta (a new stack when the slot
-- was empty).
function Storage:adjust(chest, slot, key, delta, stack)
  local c = self.chests[chest]
  if not c then return end
  local st = c.slots[slot]
  if st then
    st.count = st.count + delta
    if st.count <= 0 then c.slots[slot] = nil end
  elseif delta > 0 then
    c.slots[slot] = { name = stack.name, count = delta, nbt = stack.nbt }
  end
  self.dirty = true
end

-- Send count of an item (a key, name or search text) to target (the
-- output chest by default, or any inventory on the network such as
-- turtle_5), into slot toSlot of it when given. Takes from the smallest stacks first, so partial stacks
-- are used up and free their slots. Returns the number moved and, when
-- that is less than asked, why.
function Storage:withdraw(text, count, target, toSlot)
  target = target or self.config.output
  if not target or target == "" then return 0, "no output chest set" end
  if target == self.config.output then
    local problem = self:problem()
    if problem then return 0, problem end
  end
  local item, why = self:find(text)
  if not item then return 0, why end
  count = parseAmount(count or 1, item)
  if not count then return 0, "bad amount" end
  local want = math.min(count, item.count)
  local sources = {}
  for _, cname in ipairs(self.names) do
    local chest = self.chests[cname]
    if chest then
      for slot, st in pairs(chest.slots) do
        if keyOf(st) == item.key then sources[#sources + 1] = { chest = cname, slot = slot, count = st.count } end
      end
    end
  end
  table.sort(sources, function(a, b)
    if a.count ~= b.count then return a.count < b.count end
    if a.chest ~= b.chest then return a.chest < b.chest end
    return a.slot < b.slot
  end)
  local moved = 0
  local reason
  for _, src in ipairs(sources) do
    if moved >= want then break end
    local n = math.min(src.count, want - moved)
    local ok, got = pcall(self.call, self, src.chest, "pushItems", target, src.slot, n, toSlot)
    if not ok then reason = explain(got); break end
    got = got or 0
    self:adjust(src.chest, src.slot, item.key, -got)
    moved = moved + got
    if got < n then
      -- either the slot held less than the index thought (changed by
      -- hand) or the target is full: look at the slot again to tell
      self:refresh({ src.chest })
      local st = self.chests[src.chest] and self.chests[src.chest].slots[src.slot]
      if st and keyOf(st) == item.key then reason = target == self.config.output and "the output chest is full" or (target .. " is full"); break end
    end
  end
  if not reason and moved < count then
    reason = moved < want and "some items were missing" or ("only " .. item.count .. " in storage")
  end
  return moved, reason
end

-- A slot to put up to space items of key into: a partial stack of the
-- same item first, then an empty slot in a chest that already holds
-- the item, then any empty slot. skip lists "chest/slot" to avoid.
function Storage:findSlot(key, stack, skip)
  local maxCount = self:maxCount(key)
  for _, cname in ipairs(self.names) do
    local chest = self.chests[cname]
    if chest then
      for slot, st in pairs(chest.slots) do
        if keyOf(st) == key and st.count < maxCount and not skip[cname .. "/" .. slot] then
          return cname, slot, maxCount - st.count
        end
      end
    end
  end
  local function empty(cname)
    local chest = self.chests[cname]
    if not chest then return nil end
    for slot = 1, chest.size do
      if not chest.slots[slot] and not skip[cname .. "/" .. slot] then return slot end
    end
  end
  local item = self:index()[key]
  for pass = 1, 2 do
    for _, cname in ipairs(self.names) do
      local holds = item and item.chests[cname]
      if (pass == 1 and holds) or (pass == 2 and not holds) then
        local slot = empty(cname)
        if slot then return cname, slot, maxCount end
      end
    end
  end
  return nil
end

-- Move everything from the input chest (or from) into storage. Returns
-- the number of items stored, the number left behind and why any
-- were left.
function Storage:deposit(from)
  from = from or self.config.input
  if not from or from == "" then return 0, 0, "no input chest set" end
  if from == self.config.input then
    local problem = self:problem()
    if problem then return 0, 0, problem end
  end
  if #self.names == 0 then return 0, 0, "no storage chests found" end
  local ok, list = pcall(self.call, self, from, "list")
  if not ok or type(list) ~= "table" then return 0, 0, "cannot read " .. from end
  local slots = {}
  for slot in pairs(list) do slots[#slots + 1] = slot end
  table.sort(slots)
  local stored, left, reason = 0, 0, nil
  for _, slot in ipairs(slots) do
    local stack = list[slot]
    local key = keyOf(stack)
    if not self.info[key] then self:detailFrom(key, from, slot) end
    local remaining = stack.count
    local skip = {}
    for tries = 1, 200 do
      if remaining <= 0 then break end
      local chest, toSlot, space = self:findSlot(key, stack, skip)
      if not chest then reason = "storage is full"; break end
      local n = math.min(remaining, space)
      local ok2, got = pcall(self.call, self, from, "pushItems", chest, slot, n, toSlot)
      if not ok2 then reason = explain(got); break end
      got = got or 0
      self:adjust(chest, toSlot, key, got, stack)
      remaining = remaining - got
      stored = stored + got
      if got < n then
        -- the index was out of date for that slot: skip it and look at
        -- the chest again
        skip[chest .. "/" .. toSlot] = true
        self:refresh({ chest })
      end
    end
    left = left + math.max(0, remaining)
  end
  return stored, left, reason
end

-- How many items are waiting in the input chest (or chest).
function Storage:inputCount(chest)
  local input = chest or self.config.input
  if not input or input == "" then return 0 end
  local ok, list = pcall(self.call, self, input, "list")
  if not ok or type(list) ~= "table" then return 0 end
  local n = 0
  for _, st in pairs(list) do n = n + st.count end
  return n
end

--[[
Sorting

planSort works out, on a copy of the index, the moves that

1. condense: for each kind of item, the last stacks are poured into the
   first partial ones, so it ends up in as few stacks as it fits;
2. lay out: the kinds of item, sorted by name, take the storage slots
   one after another in storage order (chest by chest as discover
   sorts them, slot by slot), so each kind sits together and all the
   free slots end up at the end.

A stack in the way is moved to a free slot first: one in its own
kind's place when there is one, else one past the end of the items.
That needs at least one free slot, without which the lay out stops
early. Each slot takes at most two moves. A move is { from, fromSlot,
to, toSlot, count, key }.

A sort is done a few moves at a time, so the program can deliver
items in between:

  local job = s:startSort()
  repeat local finished, why = s:sortStep(job, 16) until finished

Every move is checked against the index before it is made. When items
were taken out or put in since the plan (by this program, which keeps
the index up to date, or by hand, which the move then finds out), the
rest of the sort is planned again from the index.
--]]

-- Every storage slot in storage order: { chest, slot }.
function Storage:slotList()
  local out = {}
  for _, cname in ipairs(self.names) do
    local chest = self.chests[cname]
    if chest then
      for slot = 1, chest.size do out[#out + 1] = { chest = cname, slot = slot } end
    end
  end
  return out
end

-- The moves that sort storage, and why it stops early (or nil).
function Storage:planSort()
  local positions = self:slotList()
  local total = #positions
  local state = {}
  for i, pos in ipairs(positions) do
    local st = self.chests[pos.chest].slots[pos.slot]
    if st then state[i] = { key = keyOf(st), count = st.count } end
  end
  local moves = {}
  local function move(from, to, n)
    local a, b = state[from], state[to]
    moves[#moves + 1] = { from = positions[from].chest, fromSlot = positions[from].slot,
                          to = positions[to].chest, toSlot = positions[to].slot, count = n, key = a.key }
    if b then b.count = b.count + n else state[to] = { key = a.key, count = n } end
    a.count = a.count - n
    if a.count <= 0 then state[from] = nil end
  end

  -- 1. condense
  local posOf = {}
  for i = 1, total do
    local st = state[i]
    if st then
      posOf[st.key] = posOf[st.key] or {}
      table.insert(posOf[st.key], i)
    end
  end
  local keys = {}
  for key in pairs(posOf) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local list = posOf[key]
    local max = self:maxCount(key)
    local i, j = 1, #list
    while i < j do
      local into = state[list[i]]
      if into.count >= max then
        i = i + 1
      else
        move(list[j], list[i], math.min(state[list[j]].count, max - into.count))
        if not state[list[j]] then
          table.remove(list, j)
          j = j - 1
        end
      end
    end
  end

  -- 2. lay out: the place of each kind of item
  local target, first, last = {}, {}, {}
  local n = 0
  for _, key in ipairs(keys) do
    first[key] = n + 1
    for _ = 1, #posOf[key] do
      n = n + 1
      target[n] = key
    end
    last[key] = n
  end

  local function freeIn(a, b)
    for i = math.max(1, a), math.min(total, b) do
      if not state[i] then return i end
    end
    return nil
  end
  local function relocate(from, to)
    local key = state[from].key
    move(from, to, state[from].count)
    local list = posOf[key]
    for k = #list, 1, -1 do
      if list[k] == from then table.remove(list, k); break end
    end
    local k = #list
    while k > 0 and list[k] > to do k = k - 1 end
    table.insert(list, k + 1, to)
  end

  for p = 1, n do
    local want = target[p]
    local here = state[p]
    if not (here and here.key == want) then
      if here then
        local k = here.key
        local r = freeIn(math.max(p + 1, first[k]), last[k]) or freeIn(n + 1, total) or freeIn(p + 1, n)
        if not r then return moves, "sorting needs at least one free slot" end
        relocate(p, r)
      end
      local list = posOf[want]
      local q = list[#list]
      if not q or q <= p then return moves, "lost track of " .. want end
      relocate(q, p)
    end
  end
  return moves, nil
end

-- Start a sort: plan it. The job counts moves done in done.
function Storage:startSort()
  local moves, why = self:planSort()
  return { moves = moves, at = 1, done = 0, replans = 0, stopWhy = why }
end

-- Moves left in a sort job (an estimate, as plans can change).
function sortLeft(job)
  return #job.moves - job.at + 1
end

-- Is move m still right for what the index says is in the chests?
function Storage:moveFits(m)
  local from = self.chests[m.from]
  local to = self.chests[m.to]
  local src = from and from.slots[m.fromSlot]
  if not src or keyOf(src) ~= m.key or src.count < m.count then return false end
  local dst = to and to.slots[m.toSlot]
  if dst and (keyOf(dst) ~= m.key or dst.count + m.count > self:maxCount(m.key)) then return false end
  return to ~= nil
end

-- Make up to budget moves of a sort job. Returns true and a message
-- (nil when all went well) once it has finished, false while there
-- are moves left.
function Storage:sortStep(job, budget)
  budget = budget or math.huge
  local made = 0
  while made < budget do
    local m = job.moves[job.at]
    if not m then return true, job.stopWhy end
    local fits = self:moveFits(m)
    local got = 0
    if fits then
      local src = self.chests[m.from].slots[m.fromSlot]
      local stack = { name = src.name, nbt = src.nbt }
      local ok, res = pcall(self.call, self, m.from, "pushItems", m.to, m.fromSlot, m.count, m.toSlot)
      if not ok then return true, explain(res) end
      got = res or 0
      if got > 0 then
        self:adjust(m.from, m.fromSlot, m.key, -got)
        self:adjust(m.to, m.toSlot, m.key, got, stack)
        job.done = job.done + 1
      end
    end
    made = made + 1
    if fits and got == m.count then
      job.at = job.at + 1
    else
      -- the chests are not what the plan thought: look again and plan
      -- the rest from there
      job.replans = job.replans + 1
      if job.replans > 5 then return true, "the chests kept changing while sorting" end
      if fits then self:refresh({ m.from, m.to }) end
      job.moves, job.stopWhy = self:planSort()
      job.at = 1
    end
  end
  return false
end

-- Sort storage in one go. Returns the number of moves made and why it
-- stopped early (or nil).
function Storage:sort()
  local job = self:startSort()
  local finished, why
  repeat finished, why = self:sortStep(job, 64) until finished
  return job.done, why
end

--[[
Low space alert, with hysteresis: raised at alertAt of the slots used,
cleared again below alertAt - 0.05. Returns "raise", "clear" or nil
when nothing changed.
--]]
function Storage:checkSpace()
  local used, total = self:capacity()
  local at = self.config.alertAt or 0.9
  local frac = total > 0 and used / total or 1
  if not self.lowSpace and frac >= at then
    self.lowSpace = true
    return "raise", used, total
  elseif self.lowSpace and frac < at - 0.05 then
    self.lowSpace = false
    return "clear", used, total
  end
  return nil, used, total
end

--[[
Requests from other computers. A turtle (or anything else) on the same
wired network asks for items over the bus:

  storage.request("minecraft:coal", 16)    -- on the turtle

publishes "base.storage.request" { item, count, target, requestId } and
waits for the "base.storage.result" with the same requestId, which says
how many were pushed into target (the turtle's own name on the network,
turtle_<id>, by default). Returns the number moved and a message.
--]]
function request(item, count, timeout, target)
  if not bus or not bus.publish then return 0, "no bus API" end
  bus.open()
  bus.subscribe("base.storage.result")
  local id = os.getComputerID()
  local requestId = id .. ":" .. math.floor(os.clock() * 1000) .. ":" .. math.random(1000)
  bus.publish("base.storage.request", { item = item, count = count, target = target, requestId = requestId })
  local deadline = os.clock() + (timeout or 10)
  while os.clock() < deadline do
    local topic, payload = bus.receive(deadline - os.clock())
    if topic == "base.storage.result" and type(payload) == "table" and payload.requestId == requestId then
      return payload.moved or 0, payload.message
    end
  end
  return 0, "no answer from storage"
end

-- The target a request should go to: its own target, or the name the
-- asking computer has on the wired network.
function requestTarget(payload, senderId, isPresent)
  if type(payload) ~= "table" then return nil end
  if type(payload.target) == "string" and payload.target ~= "" then return payload.target end
  for _, name in ipairs({ "turtle_" .. tostring(senderId), "computer_" .. tostring(senderId) }) do
    if not isPresent or isPresent(name) then return name end
  end
  return nil
end
