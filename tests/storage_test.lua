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
      if not to then error("Target '" .. args[1] .. "' does not exist") end
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
