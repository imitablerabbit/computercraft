--[[
Tests for the lavafuel API: the argument checks, what counts as a lava
source, and scooping and burning with the fake turtle.
--]]

before_each(function()
  testing.stub(_G, "print", function() end)
end)

local function opts(over)
  local o = { target = 5000, range = 8, width = 1, mode = "refuel", chest = "behind" }
  for k, v in pairs(over or {}) do o[k] = v end
  return o
end

describe("lavafuel.validate", function()
  it("accepts the defaults", function()
    expect.equal(lavafuel.validate(opts(), 20000), nil)
  end)
  it("refuses a target over the fuel limit, or any for a turtle without fuel", function()
    expect.match(lavafuel.validate(opts({ target = 30000 }), 20000), "over the turtle's fuel limit of 20000")
    expect.match(lavafuel.validate(opts(), "unlimited"), "needs no fuel")
  end)
  it("refuses unknown modes and empty areas", function()
    expect.match(lavafuel.validate(opts({ mode = "drink" }), 20000), "mode must be refuel or depot")
    expect.match(lavafuel.validate(opts({ range = 0 }), 20000), "range")
    expect.match(lavafuel.validate(opts({ width = 0 }), 20000), "width")
  end)
end)

describe("lavafuel.isLavaSource", function()
  it("takes still lava only", function()
    expect.truthy(lavafuel.isLavaSource({ name = "minecraft:lava", state = { level = 0 } }))
    expect.falsy(lavafuel.isLavaSource({ name = "minecraft:lava", state = { level = 4 } }))
    expect.falsy(lavafuel.isLavaSource({ name = "minecraft:water", state = { level = 0 } }))
    expect.falsy(lavafuel.isLavaSource(nil))
  end)
end)

describe("lavafuel.columns", function()
  it("centres the area on the turtle", function()
    expect.same({ lavafuel.columns(1) }, { 0, 0 })
    expect.same({ lavafuel.columns(3) }, { -1, 1 })
    expect.same({ lavafuel.columns(4) }, { -1, 2 })
  end)
end)

describe("lavafuel.run", function()
  -- A bucket placed down fills with lava; there is lava under every block.
  local function lakeTurtle(fuel)
    return testing.fakeTurtle({
      fuel = fuel,
      slots = { { name = "minecraft:bucket", count = 2 } },
      inspectDown = function() return true, { name = "minecraft:lava", state = { level = 0 } } end,
      placeDown = function(f)
        local s = f.slots[f.selected]
        if not s or s.name ~= "minecraft:bucket" then return false end
        s.count = s.count - 1
        if s.count == 0 then f.slots[f.selected] = nil end
        for slot = 1, 16 do
          if not f.slots[slot] then f.slots[slot] = { name = "minecraft:lava_bucket", count = 1 } break end
        end
        return true
      end,
    })
  end

  it("burns lava until the target and comes home", function()
    local f = testing.useTurtle(lakeTurtle(10))
    local ok, err = lavafuel.run(opts({ target = 1500, range = 4 }))
    expect.truthy(ok, err)
    expect.truthy(f.fuel >= 1500)
    expect.equal(f.called("placeDown"), 2)
    expect.same({ f.x, f.y, f.z, f.heading }, { 0, 0, 0, 0 })
  end)

  it("does nothing but say so when the fuel is already there", function()
    local f = testing.useTurtle(lakeTurtle(6000))
    expect.truthy(lavafuel.run(opts({ target = 5000 })))
    expect.equal(f.called("forward"), 0)
  end)

  it("will not go further than it can get back from", function()
    local f = testing.useTurtle(testing.fakeTurtle({ fuel = 6, slots = { { name = "minecraft:bucket", count = 1 } } }))
    local ok, err = lavafuel.run(opts({ target = 1000, range = 10 }))
    expect.falsy(ok)
    expect.match(err, "no lava")
    expect.equal(f.called("forward"), 4, "two out and back, keeping a margin of 2")
    expect.same({ f.x, f.y }, { 0, 0 })
  end)
end)
