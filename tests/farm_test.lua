--[[
Tests for the farm API: which crops are ripe and what replants them,
where the chest may go, what is kept when emptying, and one pass over
a tiny field with the fake turtle.
--]]

before_each(function()
  testing.stub(_G, "print", function() end)
end)

local function opts(over)
  local o = { width = 3, length = 3, crop = "wheat", sleep = 0, passes = 1, chest = "behind" }
  for k, v in pairs(over or {}) do o[k] = v end
  return o
end

describe("farm crops", function()
  it("knows what plants each crop choice", function()
    expect.equal(farm.seedFor("wheat"), "minecraft:wheat_seeds")
    expect.equal(farm.seedFor("carrots"), "minecraft:carrot")
    expect.equal(farm.seedFor("potatoes"), "minecraft:potato")
    expect.equal(farm.seedFor("beetroots"), "minecraft:beetroot_seeds")
    expect.equal(farm.seedFor("none"), nil)
  end)
  it("calls wheat ripe at age 7 and beetroot at 3", function()
    expect.truthy(farm.isRipe({ name = "minecraft:wheat", state = { age = 7 } }))
    expect.falsy(farm.isRipe({ name = "minecraft:wheat", state = { age = 6 } }))
    expect.truthy(farm.isRipe({ name = "minecraft:beetroots", state = { age = 3 } }))
    expect.falsy(farm.isRipe({ name = "minecraft:melon_stem", state = { age = 7 } }))
    expect.falsy(farm.isRipe(nil))
  end)
  it("knows the seeds", function()
    expect.truthy(farm.isSeed("minecraft:wheat_seeds"))
    expect.truthy(farm.isSeed("minecraft:carrot"))
    expect.falsy(farm.isSeed("minecraft:wheat"))
  end)
end)

describe("farm chest sides", function()
  it("keeps the chest out of the field", function()
    expect.same(farm.chestSides(3), { "left", "behind", "above" })
    expect.same(farm.chestSides(1), { "left", "right", "behind", "above" })
  end)
  it("refuses bad options", function()
    expect.equal(farm.validate(opts()), nil)
    expect.match(farm.validate(opts({ chest = "below" })), "below would be in the field")
    expect.match(farm.validate(opts({ crop = "melons" })), "crop must be one of")
    expect.match(farm.validate(opts({ width = 0 })), "width")
    expect.match(farm.validate(opts({ passes = -1 })), "passes")
  end)
end)

describe("farm.keepSlots", function()
  it("keeps the biggest stack of each seed and of coal", function()
    testing.useTurtle(testing.fakeTurtle({ slots = {
      { name = "minecraft:wheat_seeds", count = 10 },
      { name = "minecraft:wheat_seeds", count = 30 },
      { name = "minecraft:wheat", count = 5 },
      { name = "minecraft:coal", count = 3 },
      { name = "minecraft:carrot", count = 2 },
    } }))
    expect.same(farm.keepSlots(), { 2, 4, 5 })
  end)
end)

describe("farm.run", function()
  it("harvests and replants a ripe crop and sows bare farmland", function()
    local f = testing.useTurtle(testing.fakeTurtle({
      slots = { { name = "minecraft:wheat_seeds", count = 10 } },
      detect = true, -- the chest behind
      inspectDown = {
        testing.returns(true, { name = "minecraft:wheat", state = { age = 7 } }),
        testing.returns(false, "No block to inspect"),
      },
      digDown = true,
    }))
    local ok, err = farm.run(opts({ width = 1, length = 2 }))
    expect.truthy(ok, err)
    expect.equal(f.called("digDown"), 1)
    expect.equal(f.called("placeDown"), 2)
    expect.equal(f.getItemCount(1), 8)
    expect.same({ f.x, f.y, f.z, f.heading }, { 0, 0, 0, 0 })
  end)
end)
