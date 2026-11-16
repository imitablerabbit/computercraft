--[[
Tests for the storage index and transfers, against a fake network of
chests that stands in for the peripheral API.
--]]

local maxCounts = { ["minecraft:ender_pearl"] = 16, ["minecraft:diamond_pickaxe"] = 1 }

-- A fake peripheral API over chests = { name = { size, slots } }.
-- Turtles named turtle_N are inventories of 16 slots too.
local function network(chests)
  local net = { chests = chests, calls = {} }
  local function stackMax(st) return maxCounts[st.name] or 64 end
  local function insert(to, stack, n, toSlot)
    local moved = 0
    local order = {}
    if toSlot then order = { toSlot } else for i = 1, to.size do order[#order + 1] = i end end
    -- like the game: fill matching stacks first, then empty slots
    for pass = 1, 2 do
      for _, i in ipairs(order) do
        if moved >= n then break end
        local t = to.slots[i]
        if pass == 1 and t and t.name == stack.name and t.nbt == stack.nbt then
          local k = math.min(n - moved, stackMax(t) - t.count)
          if k > 0 then t.count = t.count + k; moved = moved + k end
        elseif pass == 2 and not t then
          local k = math.min(n - moved, stackMax(stack))
          to.slots[i] = { name = stack.name, count = k, nbt = stack.nbt }
          moved = moved + k
        end
      end
    end
    return moved
  end
  net.getNames = function()
    local names = {}
    for name in pairs(chests) do names[#names + 1] = name end
    table.sort(names)
    return names
  end
  net.hasType = function(name, ty)
    if not chests[name] then return nil end
    return ty == "inventory"
  end
  net.isPresent = function(name) return chests[name] ~= nil end
  net.call = function(name, method, ...)
    local args = { ... }
    net.calls[#net.calls + 1] = method
    local c = chests[name]
    if not c then error("No peripheral " .. name) end
    if method == "size" then return c.size
    elseif method == "list" then
      local out = {}
      for i, st in pairs(c.slots) do out[i] = { name = st.name, count = st.count, nbt = st.nbt } end
      return out
    elseif method == "getItemDetail" then
      local st = c.slots[args[1]]
      if not st then return nil end
      return { name = st.name, count = st.count, maxCount = stackMax(st), displayName = storage.prettyName(st.name) }
    elseif method == "pushItems" then
      local to = chests[args[1]]
      -- like the game, a chest on a side and one on the network cannot
      -- reach each other
      if not to or storage.isSide(name) ~= storage.isSide(args[1]) then
        error("Target '" .. args[1] .. "' does not exist")
      end
      local st = c.slots[args[2]]
      if not st then return 0 end
      local n = math.min(st.count, args[3] or 64)
      local moved = insert(to, st, n, args[4])
      st.count = st.count - moved
      if st.count == 0 then c.slots[args[2]] = nil end
      return moved
    end
    error("No such method " .. method)
  end
  net.count = function(chest, item)
    local n = 0
    for _, st in pairs(chests[chest].slots) do if not item or st.name == item then n = n + st.count end end
    return n
  end
  net.used = function(chest)
    local n = 0
    for _ in pairs(chests[chest].slots) do n = n + 1 end
    return n
  end
  return net
end

local function chest(size, slots) return { size = size or 27, slots = slots or {} } end
local function st(name, count, nbt) return { name = "minecraft:" .. name, count = count, nbt = nbt } end

local config = { input = "in", output = "out", exclude = { "trash" } }

local function make(chests)
  local net = network(chests)
  local s = storage.new(config, { peripheral = net })
  s:refresh()
  return s, net
end

describe("storage index", function()
  it("finds the storage chests, leaving out input, output and excluded ones", function()
    local s = make({ ["minecraft:chest_10"] = chest(), ["minecraft:chest_2"] = chest(), ["in"] = chest(), ["out"] = chest(), trash = chest() })
    expect.same(s.names, { "minecraft:chest_2", "minecraft:chest_10" })
  end)

  it("adds up items over chests and slots", function()
    local s = make({
      a = chest(27, { st("coal", 64), st("coal", 10), st("dirt", 5) }),
      b = chest(27, { [4] = st("coal", 6) }),
    })
    local coal = s:index()["minecraft:coal"]
    expect.equal(coal.count, 80)
    expect.equal(coal.stacks, 3)
    expect.same(coal.chests, { a = 74, b = 6 })
    expect.equal(coal.displayName, "Coal")
  end)

  it("keeps items with different NBT apart", function()
    local s = make({ a = chest(27, { st("enchanted_book", 1, "abc"), st("enchanted_book", 1, "def") }) })
    local items = s:search("book")
    expect.equal(#items, 2)
  end)

  it("searches by name or display name and sorts by count or name", function()
    local s = make({ a = chest(27, { st("oak_log", 5), st("oak_planks", 40), st("coal", 12) }) })
    local byCount = s:search("oak", "count")
    expect.equal(byCount[1].name, "minecraft:oak_planks")
    local byName = s:search("", "name")
    expect.same({ byName[1].displayName, byName[2].displayName, byName[3].displayName }, { "Coal", "Oak Log", "Oak Planks" })
    expect.equal(#s:search("PLANK"), 1)
  end)

  it("counts used and total slots", function()
    local s = make({ a = chest(27, { st("coal", 1), st("dirt", 1) }), b = chest(54, {}) })
    expect.same({ s:capacity() }, { 2, 81 })
  end)

  it("lists chests a batch at a time", function()
    local batches = 0
    testing.stub(parallel, "waitForAll", function(...)
      batches = batches + 1
      for _, f in ipairs({ ... }) do f() end
    end)
    local chests = {}
    for i = 1, 40 do chests["minecraft:chest_" .. i] = chest() end
    make(chests)
    expect.equal(batches, 2) -- 40 chests in groups of 32
  end)

  it("refreshes only the chests asked for", function()
    local s, net = make({ a = chest(27, { st("coal", 1) }), b = chest(27, { st("dirt", 1) }) })
    net.chests.a.slots[1].count = 9
    net.chests.b.slots[1].count = 9
    s:refresh({ "a" })
    expect.equal(s:index()["minecraft:coal"].count, 9)
    expect.equal(s:index()["minecraft:dirt"].count, 1)
  end)
end)

describe("storage.withdraw", function()
  it("splits a request over several slots, smallest stacks first", function()
    local s, net = make({ a = chest(27, { st("coal", 64), st("coal", 10) }), b = chest(27, { st("coal", 5) }), out = chest() })
    local moved, why = s:withdraw("minecraft:coal", 20)
    expect.equal(moved, 20)
    expect.falsy(why)
    expect.equal(net.count("out", "minecraft:coal"), 20)
    expect.equal(net.count("b"), 0) -- the 5 went first
    expect.equal(net.chests.a.slots[2], nil) -- then the 10
    expect.equal(net.chests.a.slots[1].count, 59)
    expect.equal(s:index()["minecraft:coal"].count, 59) -- the index follows without listing again
  end)

  it("honours stack sizes when sending a stack", function()
    local s, net = make({ a = chest(27, { st("ender_pearl", 16), st("ender_pearl", 16) }), out = chest() })
    expect.equal(s:withdraw("ender_pearl", "stack"), 16)
    expect.equal(net.count("out"), 16)
  end)

  it("sends all of an item", function()
    local s, net = make({ a = chest(27, { st("dirt", 64), st("dirt", 64), st("dirt", 3) }), out = chest() })
    expect.equal(s:withdraw("dirt", "all"), 131)
    expect.equal(s:index()["minecraft:dirt"], nil)
  end)

  it("reports a partial transfer when the output fills up", function()
    local s, net = make({ a = chest(27, { st("dirt", 64), st("dirt", 64) }), out = chest(1, {}) })
    local moved, why = s:withdraw("dirt", 128)
    expect.equal(moved, 64)
    expect.match(why, "full")
    expect.equal(s:index()["minecraft:dirt"].count, 64)
  end)

  it("says when there is less than asked", function()
    local s = make({ a = chest(27, { st("coal", 3) }), out = chest() })
    local moved, why = s:withdraw("coal", 10)
    expect.equal(moved, 3)
    expect.match(why, "only 3")
  end)

  it("refuses unknown items and bad amounts", function()
    local s = make({ a = chest(27, { st("coal", 3) }), out = chest() })
    expect.equal(s:withdraw("diamond", 1), 0)
    local moved, why = s:withdraw("coal", "lots")
    expect.equal(moved, 0)
    expect.match(why, "bad amount")
  end)

  it("can send to a turtle on the network", function()
    local s, net = make({ a = chest(27, { st("coal", 30) }), turtle_5 = chest(16, {}) })
    expect.equal(s:withdraw("coal", 8, "turtle_5"), 8)
    expect.equal(net.count("turtle_5"), 8)
  end)

  it("copes with a slot emptied by hand", function()
    local s, net = make({ a = chest(27, { st("coal", 10), st("coal", 20) }), out = chest() })
    net.chests.a.slots[1] = nil -- someone took the 10
    local moved = s:withdraw("coal", 15)
    expect.equal(moved, 15)
    expect.equal(net.count("out"), 15)
  end)
end)

describe("storage.deposit", function()
  it("tops up partial stacks of the same item first", function()
    local s, net = make({
      a = chest(27, { st("dirt", 5) }),
      b = chest(27, { st("coal", 60) }),
      ["in"] = chest(27, { st("coal", 10) }),
    })
    local stored, left = s:deposit()
    expect.equal(stored, 10)
    expect.equal(left, 0)
    expect.equal(net.chests.b.slots[1].count, 64)
    expect.equal(net.chests.b.slots[2].count, 6)
    expect.equal(net.count("a"), 5) -- nothing went to the chest without coal
    expect.equal(net.count("in"), 0)
  end)

  it("puts new items into empty slots", function()
    local s, net = make({ a = chest(27, {}), ["in"] = chest(27, { st("torch", 64), st("sand", 40) }) })
    expect.same({ s:deposit() }, { 104, 0, nil })
    expect.equal(s:index()["minecraft:sand"].count, 40)
    expect.equal(net.used("a"), 2)
  end)

  it("keeps stack sizes in storage", function()
    local s, net = make({ a = chest(27, { st("ender_pearl", 10) }), ["in"] = chest(27, { st("ender_pearl", 16) }) })
    s:deposit()
    expect.equal(net.chests.a.slots[1].count, 16)
    expect.equal(net.chests.a.slots[2].count, 10)
  end)

  it("leaves what does not fit and says storage is full", function()
    local s, net = make({ a = chest(1, { st("dirt", 60) }), ["in"] = chest(27, { st("dirt", 10), st("coal", 5) }) })
    local stored, left, why = s:deposit()
    expect.equal(stored, 4)
    expect.equal(left, 11)
    expect.match(why, "full")
  end)

  it("says when there is no input chest", function()
    local s = storage.new({ input = "" }, { peripheral = network({}) })
    local stored, left, why = s:deposit()
    expect.equal(stored, 0)
    expect.match(why, "no input")
  end)
end)

describe("storage space alert", function()
  it("raises at the threshold and clears below it with a margin", function()
    local slots = {}
    for i = 1, 18 do slots[i] = st("dirt", 1) end
    local s, net = make({ a = chest(20, slots), ["in"] = chest(27, { st("coal", 1) }) })
    s.config = { input = "in", output = "out", alertAt = 0.9 }
    expect.equal(s:checkSpace(), "raise")
    expect.equal(s:checkSpace(), nil)
    net.chests.a.slots[18] = nil
    s:refresh()
    expect.equal(s:checkSpace(), nil) -- 85% is inside the margin
    net.chests.a.slots[17] = nil
    s:refresh()
    expect.equal(s:checkSpace(), "clear")
  end)
end)

describe("storage helpers", function()
  it("parses amounts", function()
    local item = { count = 100, maxCount = 16 }
    expect.equal(storage.parseAmount("12", item), 12)
    expect.equal(storage.parseAmount("stack", item), 16)
    expect.equal(storage.parseAmount("all", item), 100)
    expect.equal(storage.parseAmount("0", item), nil)
    expect.equal(storage.parseAmount("x", item), nil)
  end)

  it("makes readable names", function()
    expect.equal(storage.prettyName("minecraft:oak_log"), "Oak Log")
  end)

  it("sends requests to the asking turtle by default", function()
    expect.equal(storage.requestTarget({ item = "coal" }, 5, function(n) return n == "turtle_5" end), "turtle_5")
    expect.equal(storage.requestTarget({ item = "coal", target = "minecraft:chest_3" }, 5), "minecraft:chest_3")
    expect.equal(storage.requestTarget({ item = "coal" }, 5, function() return false end), nil)
  end)

  it("writes a config with defaults when there is none", function()
    local path = "/.storage_test.cfg"
    if fs.exists(path) then fs.delete(path) end
    local c, created = storage.loadConfig(path)
    expect.truthy(created)
    expect.equal(c.alertAt, 0.9)
    c.input = "minecraft:chest_9"
    storage.saveConfig(c, path)
    local c2, created2 = storage.loadConfig(path)
    expect.falsy(created2)
    expect.equal(c2.input, "minecraft:chest_9")
    fs.delete(path)
  end)
end)

describe("storage chests on the computer's sides", function()
  it("leaves side chests out of storage when the chests are on a network", function()
    -- the input chest touches the computer and is on the cable too, so
    -- it is seen twice: as left and as minecraft:chest_0
    local s = storage.new({ input = "minecraft:chest_0", output = "out" }, { peripheral = network({
      left = chest(27, { st("coal", 5) }),
      ["minecraft:chest_0"] = chest(27, { st("coal", 5) }),
      ["minecraft:chest_1"] = chest(),
      out = chest(),
    }) })
    s:refresh()
    expect.same(s.names, { "minecraft:chest_1" })
    local stored, left, why = s:deposit()
    expect.equal(stored, 5)
    expect.equal(left, 0)
    expect.equal(why, nil)
    expect.same(s:chestChoices(), { "minecraft:chest_0", "minecraft:chest_1", "out" })
  end)

  it("says what to do when the input is a side and the rest are on the network", function()
    local s = storage.new({ input = "left", output = "out" }, { peripheral = network({
      left = chest(27, { st("coal", 5) }),
      ["minecraft:chest_1"] = chest(),
      out = chest(),
    }) })
    s:refresh()
    expect.match(s:problem(), "wired modem")
    local stored, left, why = s:deposit()
    expect.equal(stored, 0)
    expect.match(why, "input chest is set to left")
  end)

  it("works with only side chests when there is no network", function()
    local net = network({ left = chest(27, { st("coal", 5) }), right = chest(), top = chest() })
    local s = storage.new({ input = "left", output = "right" }, { peripheral = net })
    s:refresh()
    expect.same(s.names, { "top" })
    expect.equal(s:problem(), nil)
    expect.equal((s:deposit()), 5)
    expect.equal(net.count("top", "minecraft:coal"), 5)
  end)

  it("explains a target the network cannot reach", function()
    expect.match(storage.explain("Target 'left' does not exist"), "left cannot be reached")
    expect.equal(storage.explain("boom"), "boom")
  end)
end)

-- The keys of every slot in storage order ("" for empty), after
-- listing the chests again.
local function layout(s)
  s:refresh(s.names)
  local out = {}
  for _, pos in ipairs(s:slotList()) do
    local st = s.chests[pos.chest].slots[pos.slot]
    out[#out + 1] = st and storage.keyOf(st) or ""
  end
  return out
end

-- Check storage is sorted: items first, by key, each kind in as few
-- stacks as it fits, and the totals unchanged.
local function expectSorted(s, before)
  local keys = layout(s)
  local seenEmpty = false
  for i, k in ipairs(keys) do
    if k == "" then seenEmpty = true
    else
      expect.falsy(seenEmpty, "an item after a free slot at " .. i)
      if i > 1 and keys[i - 1] ~= "" then expect.truthy(keys[i - 1] <= k, "out of order at " .. i) end
    end
  end
  local after = s:index()
  for key, count in pairs(before) do
    local item = after[key]
    expect.equal(item and item.count, count, "count of " .. key)
    local max = s:maxCount(key)
    expect.equal(item.stacks, math.ceil(count / max), "stacks of " .. key)
  end
  for key in pairs(after) do expect.truthy(before[key], "new item " .. key) end
end

local function totals(s)
  local out = {}
  for key, item in pairs(s:index()) do out[key] = item.count end
  return out
end

describe("storage.sort", function()
  it("condenses partial stacks and puts each kind of item together", function()
    local s = make({
      a = chest(6, { st("dirt", 5), st("coal", 10), [5] = st("dirt", 30) }),
      b = chest(6, { st("coal", 60), [3] = st("cobblestone", 64), [4] = st("coal", 20) }),
    })
    local before = totals(s)
    local moved, why = s:sort()
    expect.equal(why, nil)
    expect.truthy(moved > 0)
    expectSorted(s, before)
    expect.same(layout(s), { "minecraft:coal", "minecraft:coal", "minecraft:cobblestone", "minecraft:dirt", "", "",
                             "", "", "", "", "", "" })
  end)

  it("keeps to smaller stack sizes and NBT", function()
    local s = make({
      a = chest(9, { st("ender_pearl", 10), st("enchanted_book", 1, "x"), st("ender_pearl", 9), [7] = st("enchanted_book", 1, "y") }),
    })
    local before = totals(s)
    s:sort()
    expectSorted(s, before)
    expect.equal(s:index()["minecraft:ender_pearl"].stacks, 2)
  end)

  it("does nothing when storage is already sorted", function()
    local s = make({ a = chest(4, { st("coal", 64), st("dirt", 3) }) })
    local job = s:startSort()
    expect.equal(#job.moves, 0)
    expect.equal((s:sort()), 0)
  end)

  it("needs a free slot to swap stacks, but still condenses", function()
    local s = make({ a = chest(3, { st("dirt", 64), st("coal", 64), st("bone", 64) }) })
    local moved, why = s:sort()
    expect.match(why, "free slot")
    expect.equal(moved, 0)
  end)

  it("plans again when the chests change in the middle", function()
    local s, net = make({
      a = chest(9, { st("dirt", 5), st("coal", 10), st("dirt", 7), st("coal", 3), st("sand", 4), st("dirt", 2) }),
    })
    local job = s:startSort()
    local finished = s:sortStep(job, 1)
    expect.falsy(finished)
    -- someone takes every stack of dirt out by hand
    for i, stack in pairs(net.chests.a.slots) do
      if stack.name == "minecraft:dirt" then net.chests.a.slots[i] = nil end
    end
    local why
    for _ = 1, 50 do
      finished, why = s:sortStep(job, 4)
      if finished then break end
    end
    expect.truthy(finished)
    expect.equal(why, nil)
    expect.truthy(job.replans >= 1)
    local keys = layout(s)
    expect.same({ keys[1], keys[2], keys[3] }, { "minecraft:coal", "minecraft:sand", "" })
  end)

  it("sorts random storage without losing anything", function()
    math.randomseed(42)
    local names = { "coal", "dirt", "sand", "ender_pearl", "torch", "gravel", "oak_log" }
    for round = 1, 20 do
      local chests = {}
      for c = 1, math.random(1, 4) do
        local size = ({ 5, 9, 27 })[math.random(1, 3)]
        local slots = {}
        for slot = 1, size do
          if math.random() < 0.6 then
            local name = names[math.random(1, #names)]
            local max = maxCounts["minecraft:" .. name] or 64
            slots[slot] = st(name, math.random(1, max))
          end
        end
        chests["minecraft:chest_" .. c] = chest(size, slots)
      end
      local s = make(chests)
      local before = totals(s)
      local used, total = s:capacity()
      local moved, why = s:sort()
      if used < total then
        expect.equal(why, nil, "round " .. round)
        expectSorted(s, before)
      else
        expect.equal(totals(s)["minecraft:coal"], before["minecraft:coal"])
      end
    end
  end)
end)

describe("remote chests", function()
  local function remoteStore()
    local net = network({
      ["minecraft:chest_0"] = chest(27, { st("coal", 20) }),
      ["minecraft:chest_1"] = chest(),
      ["minecraft:chest_5"] = chest(),
      ["minecraft:chest_6"] = chest(),
      ["enderstorage:ender_chest_0"] = chest(),
      ["in"] = chest(), ["out"] = chest(),
    })
    local s = storage.new({ input = "in", output = "out", craftChest = "minecraft:chest_6", remotes = {} }, { peripheral = net })
    s:refresh()
    return s, net
  end

  it("never uses an ender chest as storage", function()
    local s = remoteStore()
    expect.same(s.names, { "minecraft:chest_0", "minecraft:chest_1", "minecraft:chest_5" })
  end)

  it("gives each remote its own chest, taken out of storage", function()
    local s = remoteStore()
    expect.truthy(s:setRemote(10, "minecraft:chest_5", "Alice"))
    s:refresh()
    expect.same(s.names, { "minecraft:chest_0", "minecraft:chest_1" })
    local ok, why = s:setRemote(11, "minecraft:chest_5", "Bob")
    expect.falsy(ok)
    expect.match(why, "Alice")
    expect.truthy(s:setRemote(11, "enderstorage:ender_chest_0", "Bob"))
    expect.equal(s:remoteOf("enderstorage:ender_chest_0"), 11)
  end)

  it("offers chests that are not the input, output, crafting or someone else's", function()
    local s = remoteStore()
    s:setRemote(10, "minecraft:chest_5", "Alice")
    local choices = s:remoteChoices(11)
    expect.same(choices, { "enderstorage:ender_chest_0", "minecraft:chest_0", "minecraft:chest_1" })
    expect.contains(s:remoteChoices(10), "minecraft:chest_5")
    local ok = s:setRemote(11, "out")
    expect.falsy(ok)
  end)

  it("delivers to a remote's chest and deposits from it", function()
    local s, net = remoteStore()
    s:setRemote(10, "minecraft:chest_5", "Alice")
    s:refresh()
    expect.equal((s:withdraw("coal", 5, "minecraft:chest_5")), 5)
    expect.equal(net.count("minecraft:chest_5", "minecraft:coal"), 5)
    expect.equal((s:deposit("minecraft:chest_5")), 5)
    expect.equal(net.count("minecraft:chest_5"), 0)
  end)

  it("forgets a remote", function()
    local s = remoteStore()
    s:setRemote(10, "minecraft:chest_5", "Alice")
    s:setRemote(10, nil)
    expect.equal(s:remoteOf("minecraft:chest_5"), nil)
  end)
end)
