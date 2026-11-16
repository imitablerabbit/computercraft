--[[
Tests for how turtleinv classifies items (fuel, placeable blocks) and
the text helpers the inventory screens use.
--]]

describe("turtleinv.guessBlock by name", function()
  it("knows common blocks", function()
    for _, name in ipairs({ "minecraft:cobblestone", "minecraft:oak_log", "minecraft:coal_ore", "minecraft:torch",
        "minecraft:chest", "minecraft:bricks", "minecraft:quartz_block", "minecraft:bookshelf", "minecraft:sugar_cane" }) do
      expect.truthy(turtleinv.guessBlock(name), name)
    end
  end)
  it("knows common items, even when the name looks like a block", function()
    for _, name in ipairs({ "minecraft:stone_pickaxe", "minecraft:coal", "minecraft:charcoal", "minecraft:iron_ingot",
        "minecraft:stick", "minecraft:brick", "minecraft:quartz", "minecraft:book", "minecraft:water_bucket",
        "minecraft:snowball", "minecraft:wooden_axe", "minecraft:diamond" }) do
      expect.falsy(turtleinv.guessBlock(name), name)
    end
  end)
end)

describe("turtleinv.guessBlock with game data", function()
  it("trusts the creative tab over the name", function()
    expect.truthy(turtleinv.guessBlock("mod:thing", { { id = "building_blocks", displayName = "Building Blocks" } }))
    expect.falsy(turtleinv.guessBlock("minecraft:stone", { { id = "ingredients", displayName = "Ingredients" } }))
  end)
  it("uses block tags when there is no tab", function()
    expect.truthy(turtleinv.guessBlock("mod:odd_item", nil, { "minecraft:logs" }))
    expect.truthy(turtleinv.guessBlock("mod:odd_item", {}, { "c:storage_blocks" }))
  end)
  it("falls back to the name when the tags say nothing", function()
    expect.falsy(turtleinv.guessBlock("mod:gizmo", nil, { "c:tools" }))
    expect.truthy(turtleinv.guessBlock("mod:gizmo_block", nil, { "c:tools" }))
  end)
end)

describe("turtleinv.readSlot", function()
  it("reads a slot with the detailed information", function()
    testing.useTurtle(testing.fakeTurtle({
      slots = { [3] = { name = "minecraft:coal", count = 7 } },
      getItemDetail = function(fake, slot, detailed)
        local s = fake.slots[slot or fake.selected]
        if not s then return nil end
        if not detailed then return { name = s.name, count = s.count } end
        return { name = s.name, count = s.count, displayName = "Coal", maxCount = 64,
          tags = { ["minecraft:coals"] = true }, itemGroups = { { id = "ingredients", displayName = "Ingredients" } } }
      end,
    }))
    local item = turtleinv.readSlot(3)
    expect.same(item, { slot = 3, name = "minecraft:coal", count = 7, displayName = "Coal", maxCount = 64,
      tags = { "minecraft:coals" }, fuel = true, block = false })
  end)
  it("returns nil for an empty slot", function()
    testing.useTurtle(testing.fakeTurtle())
    expect.falsy(turtleinv.readSlot(1))
  end)
  it("does not select a slot to test fuel while a job runs", function()
    local t = testing.useTurtle(testing.fakeTurtle({ slots = { [2] = { name = "test:never_seen_fuel", count = 1 } } }))
    local item = turtleinv.readSlot(2, false)
    expect.equal(item.fuel, nil)
    expect.equal(t.called("select"), 0)
  end)
  it("checks fuel with refuel(0) and puts the selected slot back", function()
    local t = testing.useTurtle(testing.fakeTurtle({ selected = 9,
      slots = { [2] = { name = "test:burns_once", count = 3 } }, fuelValues = { ["test:burns_once"] = 10 } }))
    expect.truthy(turtleinv.isFuel(2, "test:burns_once"))
    expect.equal(t.getItemCount(2), 3, "nothing burnt")
    expect.equal(t.selected, 9)
    -- cached from now on, even without selecting
    expect.truthy(turtleinv.isFuel(2, "test:burns_once", false))
  end)
end)

describe("turtleinv text helpers", function()
  it("shortName prefers the display name", function()
    expect.equal(turtleinv.shortName({ name = "minecraft:coal", displayName = "Coal" }), "Coal")
    expect.equal(turtleinv.shortName({ name = "minecraft:oak_log" }), "oak log")
  end)

  it("changed spots any difference in a slot", function()
    local a = { name = "minecraft:coal", count = 2 }
    expect.falsy(turtleinv.changed(nil, nil))
    expect.truthy(turtleinv.changed(nil, a))
    expect.truthy(turtleinv.changed(a, nil))
    expect.falsy(turtleinv.changed(a, { name = "minecraft:coal", count = 2 }))
    expect.truthy(turtleinv.changed(a, { name = "minecraft:coal", count = 3 }))
    expect.truthy(turtleinv.changed(a, { name = "minecraft:coal", count = 2, fuel = true }))
  end)

  it("wraps at spaces and splits long words", function()
    expect.same(turtleinv.wrap("hello world foo", 5), { "hello", "world", "foo" })
    expect.same(turtleinv.wrap("a b c", 3), { "a", "b c" })
    expect.same(turtleinv.wrap("abcdefgh", 3), { "abc", "def", "gh" })
    expect.same(turtleinv.wrap("", 5), {})
  end)

  it("tagText drops the minecraft prefix", function()
    expect.equal(turtleinv.tagText({ tags = { "minecraft:logs", "c:wood" } }), "logs c:wood")
    expect.equal(turtleinv.tagText({ tags = {} }), nil)
    expect.equal(turtleinv.tagText({}), nil)
  end)

  it("detailRows describes an item", function()
    local rows = turtleinv.detailRows({ name = "minecraft:stone_pickaxe", displayName = "Stone Pickaxe", count = 1,
      maxCount = 1, damage = 3, maxDamage = 131, fuel = false, block = false })
    local byLabel = {}
    for _, r in ipairs(rows) do byLabel[r.label] = r.value end
    expect.equal(byLabel.Count, "1 / 1")
    expect.equal(byLabel.Damage, "3 / 131")
    expect.equal(byLabel.Fuel, "no")
    expect.match(byLabel.Block, "^no")
    local unknown = turtleinv.detailRows({ name = "x:y", count = 2 })
    expect.equal(unknown[#unknown - 1].value, "unknown while a job runs")
  end)
end)
