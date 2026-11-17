--[[
Tests for the rail API against the fake turtle: powered rails with
their redstone torches, plain rail when those are missing, rails
already in place and the argument checks.
--]]

local function slots(list)
  local s = {}
  for i, v in ipairs(list) do s[i] = { name = "minecraft:" .. v[1], count = v[2] } end
  return s
end

before_each(function()
  testing.stub(_G, "print", function() end)
end)

describe("rail.validate", function()
  it("accepts a plain line and refuses bad numbers", function()
    expect.equal(rail.validate({ length = 10, poweredGap = 0, torchGap = 0 }), nil)
    expect.match(rail.validate({ length = 0, poweredGap = 0, torchGap = 0 }), "length")
    expect.match(rail.validate({ length = 5, poweredGap = -1, torchGap = 0 }), "powered gap")
    expect.match(rail.validate({ length = 5, poweredGap = 0, torchGap = -2 }), "torch gap")
  end)
end)

describe("rail.isRail", function()
  it("knows every kind of rail", function()
    expect.truthy(rail.isRail("minecraft:rail"))
    expect.truthy(rail.isRail("minecraft:powered_rail"))
    expect.truthy(rail.isRail("minecraft:detector_rail"))
    expect.falsy(rail.isRail("minecraft:stone"))
  end)
end)

describe("rail.run", function()
  it("lays a powered rail with a redstone torch beside it every gap", function()
    local f = testing.useTurtle(testing.fakeTurtle({ slots = slots({
      { "rail", 4 }, { "powered_rail", 2 }, { "redstone_torch", 2 }, { "cobblestone", 5 },
    }) }))
    local ok, err = rail.run({ length = 4, poweredGap = 2, torchGap = 0 })
    expect.truthy(ok, err)
    expect.same({ f.x, f.y, f.z, f.heading }, { 0, 3, 1, 0 })
    expect.equal(f.getItemCount(1), 2, "two plain rails")
    expect.equal(f.getItemCount(2), 0, "both powered rails")
    expect.equal(f.getItemCount(3), 0, "both redstone torches")
    expect.equal(f.getItemCount(4), 3, "a support under each powered rail's drop")
  end)

  it("lays plain rail where a powered one is due but there are no redstone torches", function()
    local f = testing.useTurtle(testing.fakeTurtle({ slots = slots({ { "rail", 4 }, { "powered_rail", 2 } }) }))
    expect.truthy(rail.run({ length = 4, poweredGap = 2, torchGap = 0 }))
    expect.equal(f.getItemCount(1), 0)
    expect.equal(f.getItemCount(2), 2)
    expect.equal(f.called("down"), 0, "it never dropped to rail level")
  end)

  it("leaves a rail that is already there", function()
    local f = testing.useTurtle(testing.fakeTurtle({
      slots = slots({ { "rail", 4 } }),
      inspectDown = function() return true, { name = "minecraft:rail", state = {} } end,
    }))
    expect.truthy(rail.run({ length = 3, poweredGap = 0, torchGap = 0 }))
    expect.equal(f.called("placeDown"), 0)
    expect.equal(f.called("digDown"), 0)
  end)

  it("stops with the reason at bedrock", function()
    testing.useTurtle(testing.fakeTurtle({
      slots = slots({ { "rail", 4 } }),
      forward = false, detect = true, dig = testing.returns(false, "Unbreakable block detected"),
    }))
    local ok, err = rail.run({ length = 3, poweredGap = 0, torchGap = 0 })
    expect.falsy(ok)
    expect.match(err, "blocked after 1 blocks: Unbreakable")
  end)
end)
