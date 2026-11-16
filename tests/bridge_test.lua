--[[
Tests for the bridge API against the fake turtle: what counts as a
floor or railing item, the argument checks, and stopping on the far
side of a gap.
--]]

before_each(function()
  testing.stub(_G, "print", function() end)
end)

describe("bridge item rules", function()
  it("takes any building block for the floor, but not sand or torches", function()
    expect.truthy(bridge.isFloor("minecraft:cobblestone", "any"))
    expect.truthy(bridge.isFloor("minecraft:oak_planks", "any"))
    expect.falsy(bridge.isFloor("minecraft:sand", "any"))
    expect.falsy(bridge.isFloor("minecraft:gravel", "any"))
    expect.falsy(bridge.isFloor("minecraft:torch", "any"))
    expect.falsy(bridge.isFloor("minecraft:coal", "any"))
  end)
  it("takes only the named item when one is given", function()
    expect.truthy(bridge.isFloor("minecraft:stone_bricks", "minecraft:stone_bricks"))
    expect.falsy(bridge.isFloor("minecraft:cobblestone", "minecraft:stone_bricks"))
  end)
  it("uses fences and walls for railings", function()
    expect.truthy(bridge.isRailing("minecraft:oak_fence"))
    expect.truthy(bridge.isRailing("minecraft:cobblestone_wall"))
    expect.falsy(bridge.isRailing("minecraft:oak_fence_gate"))
    expect.falsy(bridge.isRailing("minecraft:cobblestone"))
  end)
end)

describe("bridge.validate", function()
  it("refuses unknown walls and bad numbers", function()
    local o = { length = 10, walls = "none", untilGround = 0, block = "any" }
    expect.equal(bridge.validate(o), nil)
    o.walls = "fence"
    expect.match(bridge.validate(o), "walls must be none, rails or walls")
    o.walls, o.length = "none", 0
    expect.match(bridge.validate(o), "length")
    o.length, o.untilGround = 5, -1
    expect.match(bridge.validate(o), "untilGround")
  end)
end)

describe("bridge.run", function()
  it("fills the gap and stops after enough ground on the far side", function()
    local f = testing.useTurtle(testing.fakeTurtle({
      slots = { { name = "minecraft:cobblestone", count = 10 } },
      -- ground, gap, gap, ground, ground, ...
      detectDown = { true, false, false, true, true, true },
    }))
    local ok, err = bridge.run({ length = 10, walls = "none", untilGround = 2, block = "any" })
    expect.truthy(ok, err)
    expect.equal(f.y, 5)
    expect.equal(f.getItemCount(1), 8)
  end)

  it("walls both sides of each gap block", function()
    local f = testing.useTurtle(testing.fakeTurtle({
      slots = { { name = "minecraft:cobblestone", count = 10 } },
      detectDown = false,
    }))
    expect.truthy(bridge.run({ length = 2, walls = "walls", untilGround = 0, block = "any" }))
    expect.equal(f.getItemCount(1), 4, "a floor and two sides for each block")
    expect.equal(f.heading, 0)
  end)
end)
