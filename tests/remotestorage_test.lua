--[[
Tests for the storage remote's client, against a fake bus that answers
like the storage computer at the base.
--]]

-- A fake bus: publish hands the message to server(topic, payload),
-- whose answer (topic, payload) receive then returns from computer 1.
local function fakeBus(server)
  local queue = {}
  local fake = { published = {} }
  testing.stub(_G, "bus", {
    open = function() return true end,
    subscribe = function() end,
    publish = function(topic, payload)
      fake.published[#fake.published + 1] = { topic = topic, payload = payload }
      local t, p = server(topic, payload)
      if t then
        p.requestId = payload.requestId
        queue[#queue + 1] = { t, p }
      end
    end,
    receive = function()
      local m = table.remove(queue, 1)
      if not m then return nil end
      return m[1], m[2], 1
    end,
  })
  return fake
end

local items = {
  { key = "minecraft:coal", name = "minecraft:coal", displayName = "Coal", count = 40, maxCount = 64 },
  { key = "minecraft:ender_pearl", name = "minecraft:ender_pearl", displayName = "Ender Pearl", count = 3, maxCount = 16 },
}

local function base(state)
  state = state or {}
  return function(topic, p)
    if topic == "base.storage.list" then
      return "base.storage.items", { label = "Base", items = items, used = 2, total = 27, chest = state.chest,
                                     choices = { "minecraft:chest_5" }, recipes = {} }
    elseif topic == "base.storage.register" then
      state.chest = p.chest
      return "base.storage.registered", { ok = true, chest = p.chest }
    elseif topic == "base.storage.request" then
      state.asked = p
      return "base.storage.result", { moved = math.min(p.count, 40) }
    elseif topic == "base.storage.deposit" then
      return "base.storage.deposited", { stored = 7, left = 0 }
    elseif topic == "base.storage.craft" then
      return "base.storage.crafting", { message = "Crafting " .. p.count .. " " .. p.recipe }
    end
  end
end

describe("storage remote", function()
  it("fetches the item list and searches it like storage", function()
    fakeBus(base())
    local r = remotestorage.new({})
    expect.truthy(r:refresh())
    expect.equal(r.server, 1)
    expect.equal(r.label, "Base")
    expect.equal(#r:search("ender"), 1)
    expect.equal(r:find("coal").count, 40)
    expect.equal(r:maxCount("minecraft:ender_pearl"), 16)
    expect.same({ r:capacity() }, { 2, 27 })
  end)

  it("asks for a chest first, then gets items into it", function()
    local state = {}
    local bus = fakeBus(base(state))
    local r = remotestorage.new({})
    r:refresh()
    expect.match(r:problem(), "Pick your chest")
    expect.truthy(r:register("minecraft:chest_5"))
    expect.equal(r.chest, "minecraft:chest_5")
    expect.equal(r:problem(), nil)
    local moved = r:withdraw("coal", 16)
    expect.equal(moved, 16)
    expect.same({ state.asked.item, state.asked.count, state.asked.server }, { "minecraft:coal", 16, 1 })
    expect.equal(r:find("coal").count, 24)
    expect.equal(bus.published[#bus.published].topic, "base.storage.request")
  end)

  it("deposits from its chest and asks the base to craft", function()
    fakeBus(base({ chest = "minecraft:chest_5" }))
    local r = remotestorage.new({})
    r:refresh()
    expect.same({ r:deposit() }, { 7, 0 })
    expect.equal(r:craft("Stick", 16), "Crafting 16 Stick")
  end)

  it("says when no storage computer answers", function()
    fakeBus(function() end)
    local r = remotestorage.new({}, { timeout = 0.1 })
    local ok, why = r:refresh()
    expect.falsy(ok)
    expect.match(why, "no storage computer")
    expect.match(r:problem(), "wireless or ender modem")
  end)
end)
