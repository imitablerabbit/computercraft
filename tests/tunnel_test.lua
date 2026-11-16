--[[
Tests for the tunnel API's layout rules and argument checks: which
columns a width covers, where torches go and what is refused.
--]]

local function opts(over)
  local o = { length = 10, width = 3, height = 3, torchGap = 8, chest = "behind", returnHome = true, plug = true }
  for k, v in pairs(over or {}) do o[k] = v end
  return o
end

describe("tunnel.columns", function()
  it("centres odd widths on the turtle", function()
    expect.same({ tunnel.columns(1) }, { 0, 0 })
    expect.same({ tunnel.columns(3) }, { -1, 1 })
    expect.same({ tunnel.columns(5) }, { -2, 2 })
  end)
  it("puts the extra column of an even width on the right", function()
    expect.same({ tunnel.columns(2) }, { 0, 1 })
    expect.same({ tunnel.columns(4) }, { -1, 2 })
  end)
end)

describe("tunnel.torchColumn", function()
  it("is never the middle column the turtle walks", function()
    for w = 2, 5 do
      local col = tunnel.torchColumn(w)
      expect.truthy(col ~= 0, "width " .. w)
      local x0, x1 = tunnel.columns(w)
      expect.truthy(col == x0 or col == x1, "an outer column")
    end
  end)
  it("is nil for a one wide tunnel, whose torches go up top", function()
    expect.equal(tunnel.torchColumn(1), nil)
  end)
end)

describe("tunnel.isTorchSlice", function()
  it("lights every gap-th slice", function()
    expect.falsy(tunnel.isTorchSlice(1, 4))
    expect.truthy(tunnel.isTorchSlice(4, 4))
    expect.truthy(tunnel.isTorchSlice(8, 4))
  end)
  it("never lights with a gap of 0", function()
    expect.falsy(tunnel.isTorchSlice(4, 0))
  end)
end)

describe("tunnel.validate", function()
  it("accepts the defaults", function()
    expect.equal(tunnel.validate(opts()), nil)
  end)
  it("refuses widths outside 1 to 5", function()
    expect.match(tunnel.validate(opts({ width = 0 })), "width must be 1 to 5")
    expect.match(tunnel.validate(opts({ width = 6 })), "width must be 1 to 5")
  end)
  it("refuses heights outside 2 to 5", function()
    expect.match(tunnel.validate(opts({ height = 1 })), "height must be 2 to 5")
    expect.match(tunnel.validate(opts({ height = 6 })), "height must be 2 to 5")
  end)
  it("refuses a zero length, a negative torch gap and an unknown chest side", function()
    expect.match(tunnel.validate(opts({ length = 0 })), "length")
    expect.match(tunnel.validate(opts({ torchGap = -1 })), "torch gap")
    expect.match(tunnel.validate(opts({ chest = "front" })), "unknown chest side")
  end)
end)

describe("tunnel.run", function()
  it("refuses bad options without moving", function()
    local f = testing.useTurtle(testing.fakeTurtle())
    local ok, err = tunnel.run(opts({ width = 9 }))
    expect.falsy(ok)
    expect.match(err, "width")
    expect.equal(#f.names(testing.actionsOnly), 0)
  end)

  it("bores a short tunnel through an empty world and comes back", function()
    testing.stub(_G, "print", function() end)
    local f = testing.useTurtle(testing.fakeTurtle({
      detect = true, -- a chest behind the start; the world is otherwise empty
      slots = { { name = "minecraft:cobblestone", count = 10 }, { name = "minecraft:coal", count = 4 } },
    }))
    local ok, err = tunnel.run(opts({ length = 2, width = 1, height = 2, torchGap = 0, plug = false }))
    expect.truthy(ok, err)
    expect.same({ f.x, f.y, f.z, f.heading }, { 0, 0, 0, 0 })
    expect.same(f.dropped, {}, "cobblestone and coal are kept")
  end)
end)
