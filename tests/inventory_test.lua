--[[
Tests for the inventory API against the fake turtle: chest sides,
emptying into a chest on any side, refuelling and slot searches.
--]]

local coal = { name = "minecraft:coal", count = 5 }
local dirt = { name = "minecraft:dirt", count = 10 }

describe("inventory.isChestSide", function()
  it("accepts the five chest sides", function()
    for _, side in ipairs({ "left", "right", "behind", "below", "above" }) do
      expect.truthy(inventory.isChestSide(side), side)
    end
  end)
  it("rejects anything else", function()
    expect.falsy(inventory.isChestSide("front"))
    expect.falsy(inventory.isChestSide(nil))
    expect.falsy(inventory.isChestSide("Left"))
  end)
end)

describe("inventory.dumpTo", function()
  it("turns to a chest on the left, empties everything and turns back", function()
    local t = testing.useTurtle(testing.fakeTurtle({ slots = { coal, [4] = dirt }, detect = true }))
    local ok, reason = inventory.dumpTo("left")
    expect.truthy(ok, reason)
    expect.same(t.dropped, { { name = "minecraft:coal", count = 5, dir = "" }, { name = "minecraft:dirt", count = 10, dir = "" } })
    expect.equal(t.heading, 0, "facing the way it started")
    expect.same(t.names(function(n) return n:find("^turn") end), { "turnLeft", "turnRight" })
  end)

  it("defaults to the left", function()
    local t = testing.useTurtle(testing.fakeTurtle({ slots = { coal }, detect = true }))
    expect.truthy(inventory.dumpTo())
    expect.equal(t.called("turnLeft"), 1)
  end)

  it("turns round for a chest behind", function()
    local t = testing.useTurtle(testing.fakeTurtle({ slots = { coal }, detect = true }))
    expect.truthy(inventory.dumpTo("behind"))
    expect.equal(t.called("turnLeft"), 2)
    expect.equal(t.called("turnRight"), 2)
    expect.equal(t.heading, 0)
  end)

  it("drops down into a chest below without turning", function()
    local t = testing.useTurtle(testing.fakeTurtle({ slots = { coal }, detectDown = true }))
    expect.truthy(inventory.dumpTo("below"))
    expect.same(t.dropped, { { name = "minecraft:coal", count = 5, dir = "Down" } })
    expect.equal(t.called("turnLeft") + t.called("turnRight"), 0)
  end)

  it("keeps the items when there is no chest", function()
    local t = testing.useTurtle(testing.fakeTurtle({ slots = { coal }, detectUp = false }))
    local ok, reason = inventory.dumpTo("above")
    expect.falsy(ok)
    expect.equal(reason, "no chest above")
    expect.equal(#t.dropped, 0)
    expect.equal(t.getItemCount(1), 5)
  end)

  it("says when the chest is full", function()
    local t = testing.useTurtle(testing.fakeTurtle({ slots = { coal, dirt }, detect = true, drop = { true, false } }))
    local ok, reason = inventory.dumpTo("right")
    expect.falsy(ok)
    expect.equal(reason, "the chest right is full")
    expect.equal(t.heading, 0, "turned back even so")
  end)

  it("leaves ignored slots alone and restores the selected slot", function()
    local t = testing.useTurtle(testing.fakeTurtle({ slots = { coal, dirt }, detect = true, selected = 2 }))
    expect.truthy(inventory.dumpTo("left", { 1 }))
    expect.same(t.dropped, { { name = "minecraft:dirt", count = 10, dir = "" } })
    expect.equal(t.getItemCount(1), 5)
    expect.equal(t.getSelectedSlot(), 2)
  end)

  it("refuses an unknown side without moving", function()
    local t = testing.useTurtle(testing.fakeTurtle())
    local ok, reason = inventory.dumpTo("sideways")
    expect.falsy(ok)
    expect.equal(reason, "unknown chest side sideways")
    expect.equal(#t.calls, 0)
  end)
end)

describe("inventory slots", function()
  it("finds every slot holding an item", function()
    testing.useTurtle(testing.fakeTurtle({ slots = { coal, dirt, coal } }))
    expect.same(inventory.find("minecraft:coal"), { 1, 3 })
    expect.same(inventory.find("minecraft:torch"), {})
    expect.error(function() inventory.find() end, "item name expected")
  end)

  it("selects the first slot with an item", function()
    local t = testing.useTurtle(testing.fakeTurtle({ slots = { dirt, coal } }))
    expect.truthy(inventory.select("minecraft:coal"))
    expect.equal(t.selected, 2)
    expect.falsy(inventory.select("minecraft:torch"))
  end)

  it("knows when there is no free slot", function()
    local full = {}
    for i = 1, 16 do full[i] = dirt end
    testing.useTurtle(testing.fakeTurtle({ slots = full }))
    expect.falsy(inventory.anyFreeSpace())
    full[16] = nil
    testing.useTurtle(testing.fakeTurtle({ slots = full }))
    expect.truthy(inventory.anyFreeSpace())
  end)

  it("burns fuel except blacklisted items and slots", function()
    local t = testing.useTurtle(testing.fakeTurtle({
      fuel = 0, selected = 5,
      slots = { coal, { name = "minecraft:oak_log", count = 4 }, [3] = { name = "minecraft:coal", count = 1 } },
    }))
    inventory.refuelAll({ "minecraft:oak_log", 3 })
    expect.equal(t.fuel, 5 * 80)
    expect.equal(t.getItemCount(2), 4)
    expect.equal(t.getItemCount(3), 1)
    expect.equal(t.getSelectedSlot(), 5)
  end)
end)
