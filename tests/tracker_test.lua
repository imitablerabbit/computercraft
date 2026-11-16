--[[
Tests for the tracker API against the fake turtle: position and
heading tracking, digging through blocks and falling gravel, attacking
what stands in the way, giving up on bedrock and the fuel checks.
--]]

local gravel = { name = "minecraft:gravel" }
local stone = { name = "minecraft:stone" }

-- A world column in front of the turtle: a list of blocks that come one
-- after the other as each is dug (gravel falling into the space).
local function column(blocks)
  local i = 1
  return {
    inspect = function() if blocks[i] then return true, blocks[i] end return false, "No block to inspect" end,
    detect = function() return blocks[i] ~= nil end,
    dig = function()
      if not blocks[i] then return false, "Nothing to dig here" end
      if blocks[i].name == "minecraft:bedrock" then return false, "Unbreakable block detected" end
      i = i + 1
      return true
    end,
    forward = function(f) if blocks[i] then return false, "Movement obstructed" end return f.defaults.forward() end,
  }
end

before_each(function()
  testing.stub(_G, "sleep", function() end)
end)

describe("tracker.isFalling and isLiquid", function()
  it("knows sand and gravel fall but soul sand does not", function()
    expect.truthy(tracker.isFalling("minecraft:gravel"))
    expect.truthy(tracker.isFalling("minecraft:sand"))
    expect.truthy(tracker.isFalling("minecraft:red_sand"))
    expect.truthy(tracker.isFalling("minecraft:white_concrete_powder"))
    expect.falsy(tracker.isFalling("minecraft:soul_sand"))
    expect.falsy(tracker.isFalling("minecraft:sandstone"))
    expect.falsy(tracker.isFalling(nil))
  end)
  it("knows water and lava, and a source by its level", function()
    expect.truthy(tracker.isLiquid("minecraft:lava"))
    expect.truthy(tracker.isLiquid("minecraft:water"))
    expect.falsy(tracker.isLiquid("minecraft:water_bucket"))
    expect.truthy(tracker.isSource({ name = "minecraft:lava", state = { level = 0 } }))
    expect.falsy(tracker.isSource({ name = "minecraft:lava", state = { level = 3 } }))
    expect.falsy(tracker.isSource({ name = "minecraft:stone", state = {} }))
  end)
end)

describe("tracker moves", function()
  it("tracks position and heading relative to the start", function()
    local f = testing.useTurtle(testing.fakeTurtle())
    local t = tracker.new()
    expect.truthy(t:forward())
    t:turnRight()
    expect.truthy(t:forward())
    expect.truthy(t:up())
    expect.same({ t.x, t.y, t.z, t.heading }, { 1, 1, 1, 1 })
    t:face(3)
    expect.equal(t.heading, 3)
    expect.equal(f.heading, 3, "the turtle turned too")
    expect.equal(t:distanceHome(), 3)
  end)

  it("goes to a cell one axis at a time and comes back", function()
    local f = testing.useTurtle(testing.fakeTurtle())
    local t = tracker.new()
    expect.truthy(t:goTo(-2, 3, 1, "zxy"))
    expect.same({ t.x, t.y, t.z }, { -2, 3, 1 })
    expect.same({ f.x, f.y, f.z }, { -2, 3, 1 })
    expect.truthy(t:goTo(0, 0, 0, "yxz"))
    expect.same({ f.x, f.y, f.z }, { 0, 0, 0 })
  end)

  it("digs through stone and gravel that keeps falling in", function()
    testing.useTurtle(testing.fakeTurtle(column({ stone, gravel, gravel })))
    local t = tracker.new()
    expect.truthy(t:forward())
    expect.equal(t.dug, 3)
    expect.equal(t.y, 1)
  end)

  it("gives up on bedrock with the reason", function()
    testing.useTurtle(testing.fakeTurtle(column({ { name = "minecraft:bedrock" } })))
    local t = tracker.new()
    local ok, reason = t:forward()
    expect.falsy(ok)
    expect.equal(reason, "Unbreakable block detected")
    expect.equal(t.y, 0, "it did not move")
  end)

  it("attacks a mob in the way until it moves", function()
    local f = testing.useTurtle(testing.fakeTurtle({ forward = { false, false, true }, attack = true }))
    local t = tracker.new()
    expect.truthy(t:forward())
    expect.equal(f.called("attack"), 2)
    expect.equal(f.called("dig"), 0)
    expect.equal(t.y, 1)
  end)

  it("does not dig when told not to", function()
    local f = testing.useTurtle(testing.fakeTurtle({ forward = { false, true }, detect = true }))
    local t = tracker.new({ dig = false })
    expect.truthy(t:forward())
    expect.equal(f.called("dig"), 0)
  end)
end)

describe("tracker.digFalling", function()
  it("digs gravel over a ceiling and stops at stone", function()
    local blocks = { gravel, gravel, stone }
    local i = 1
    local f = testing.useTurtle(testing.fakeTurtle({
      inspectUp = function() return true, blocks[i] end,
      digUp = function() i = i + 1 return true end,
    }))
    local t = tracker.new()
    expect.truthy(t:digFalling("Up"))
    expect.equal(f.called("digUp"), 2, "the stone stays")
  end)
end)

describe("tracker fuel", function()
  it("has fuel for the way home plus the margin", function()
    testing.useTurtle(testing.fakeTurtle({ fuel = 25 }))
    local t = tracker.new({ margin = 10 })
    t.y = 10
    expect.truthy(t:hasFuelFor(5))
    expect.falsy(t:hasFuelFor(6))
  end)

  it("burns coal to have enough but keeps what it is told to", function()
    local f = testing.useTurtle(testing.fakeTurtle({ fuel = 5, slots = {
      { name = "minecraft:oak_planks", count = 10 }, { name = "minecraft:coal", count = 1 },
    } }))
    local t = tracker.new({ keep = function(d) return d.name == "minecraft:oak_planks" end })
    expect.truthy(t:hasFuelFor(50))
    expect.equal(f.fuel, 85)
    expect.equal(f.getItemCount(1), 10, "the planks were kept")
  end)

  it("burns fuel before a move when the tank is empty", function()
    local f = testing.useTurtle(testing.fakeTurtle({ fuel = 0, slots = { { name = "minecraft:coal", count = 1 } } }))
    local t = tracker.new()
    expect.truthy(t:forward())
    expect.equal(f.fuel, 79)
  end)
end)
