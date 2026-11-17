--[[
Tests for the footprint and chest side rules in the excavate API,
which quarry and flatten use before they dig anything.
--]]

describe("excavate.columns", function()
  it("puts a left start on the leftmost column", function()
    expect.same({ excavate.columns(3, "left") }, { 0, 2 })
  end)
  it("defaults to a left start", function()
    expect.same({ excavate.columns(4) }, { 0, 3 })
  end)
  it("puts a right start on the rightmost column", function()
    expect.same({ excavate.columns(3, "right") }, { -2, 0 })
  end)
  it("centres a middle start on an odd width", function()
    expect.same({ excavate.columns(5, "middle") }, { -2, 2 })
  end)
  it("puts the extra column of an even width on the right", function()
    expect.same({ excavate.columns(4, "middle") }, { -1, 2 })
  end)
  it("gives a single column for width 1 from anywhere", function()
    for _, start in ipairs(excavate.Starts) do
      expect.same({ excavate.columns(1, start) }, { 0, 0 }, start)
    end
  end)
  it("always spans width columns", function()
    for width = 1, 9 do
      for _, start in ipairs(excavate.Starts) do
        local x0, x1 = excavate.columns(width, start)
        expect.equal(x1 - x0 + 1, width, width .. " " .. start)
        expect.truthy(x0 <= 0 and x1 >= 0, "the turtle is inside the footprint")
      end
    end
  end)
end)

describe("excavate.chestConflict", function()
  it("refuses a chest below a quarry", function()
    expect.match(excavate.chestConflict(3, 3, 2, "down", "below"), "below is inside")
  end)
  it("allows the sides and above for a quarry", function()
    for _, side in ipairs({ "left", "right", "behind", "above" }) do
      expect.falsy(excavate.chestConflict(3, 3, 2, "down", side), side)
    end
  end)
  it("refuses a chest beside the turtle inside a flatten", function()
    expect.truthy(excavate.chestConflict(3, 3, 2, "up", "right", "left"))
    expect.falsy(excavate.chestConflict(3, 3, 2, "up", "left", "left"))
    expect.truthy(excavate.chestConflict(3, 3, 2, "up", "left", "right"))
    expect.falsy(excavate.chestConflict(3, 3, 2, "up", "right", "right"))
    expect.truthy(excavate.chestConflict(3, 3, 2, "up", "left", "middle"))
    expect.truthy(excavate.chestConflict(3, 3, 2, "up", "right", "middle"))
  end)
  it("allows beside a one wide flatten", function()
    expect.falsy(excavate.chestConflict(1, 3, 2, "up", "left", "middle"))
    expect.falsy(excavate.chestConflict(1, 3, 2, "up", "right", "middle"))
  end)
  it("allows above a one high flatten but not a taller one", function()
    expect.falsy(excavate.chestConflict(3, 3, 1, "up", "above"))
    expect.truthy(excavate.chestConflict(3, 3, 2, "up", "above"))
  end)
  it("never minds a chest behind", function()
    expect.falsy(excavate.chestConflict(5, 5, 5, "down", "behind", "middle"))
    expect.falsy(excavate.chestConflict(5, 5, 5, "up", "behind", "middle"))
  end)
  it("says nothing about unknown sides", function()
    expect.falsy(excavate.chestConflict(3, 3, 3, "down", "sideways"))
  end)
end)

describe("excavate.chestSides", function()
  it("lists every side but below for a quarry", function()
    expect.same(excavate.chestSides(3, 3, 2, "down"), { "left", "right", "behind", "above" })
  end)
  it("lists the sides outside a flatten", function()
    expect.same(excavate.chestSides(3, 3, 3, "up", "left"), { "left", "behind", "below" })
    expect.same(excavate.chestSides(3, 3, 3, "up", "right"), { "right", "behind", "below" })
    expect.same(excavate.chestSides(3, 3, 3, "up", "middle"), { "behind", "below" })
  end)
end)

describe("excavate helpers", function()
  it("knows the start positions", function()
    expect.truthy(excavate.isStart("middle"))
    expect.falsy(excavate.isStart("centre"))
  end)
  it("estimates fuel for every cell plus the trips", function()
    expect.equal(excavate.estimateFuel(3, 3, 2), 18 + 2 * (3 + 3 + 4))
  end)
  it("rejects bad sizes before moving", function()
    local t = testing.useTurtle(testing.fakeTurtle())
    local ok, err = excavate.run(0, 3, 3, "down")
    expect.falsy(ok)
    expect.match(err, "at least 1")
    ok, err = excavate.run(3, 3, 3, "down", "below")
    expect.falsy(ok)
    expect.match(err, "inside the area")
    expect.equal(#t.calls, 0, "no turtle calls")
  end)
end)

describe("excavate.run with a fake turtle", function()
  before_each(function()
    testing.stub(_G, "print", function() end)
  end)

  it("clears a small quarry, comes home and empties into the chest", function()
    local t = testing.useTurtle(testing.fakeTurtle({
      slots = { { name = "minecraft:coal", count = 3 } },
      detect = true, -- the chest on the left is there
    }))
    local ok, err = excavate.run(2, 3, 2, "down", "left")
    expect.truthy(ok, err)
    expect.same({ t.x, t.y, t.z, t.heading }, { 0, 0, 0, 0 }, "back at the start facing forward")
    expect.equal(t.called("down"), 2)
    expect.equal(t.called("up"), 2)
    -- 2x3 cells per layer is 5 steps, twice, plus the way home
    expect.truthy(t.called("forward") >= 10)
    expect.same(t.dropped, { { name = "minecraft:coal", count = 3, dir = "" } })
  end)

  it("digs through blocks in the way", function()
    local t = testing.useTurtle(testing.fakeTurtle({
      forward = { false, true },
      detect = true,
      dig = true,
    }))
    local ok = excavate.run(1, 2, 1, "down", "left")
    expect.truthy(ok)
    expect.truthy(t.called("dig") >= 1)
  end)

  it("reports a quarry blocked by bedrock and still goes home", function()
    local t = testing.useTurtle(testing.fakeTurtle({
      down = { true, false },
      detectDown = true,
      digDown = testing.returns(false, "Unbreakable block detected"),
      detect = true,
    }))
    local ok, err = excavate.run(1, 1, 3, "down", "left")
    expect.falsy(ok)
    expect.match(err, "blocked going down after 1 layers")
    expect.equal(t.z, 0, "back up at the start")
  end)
end)
