--[[
Tests for the nav API's pure parts: the A* search (nav.findPath) over
made-up worlds, and the heading and coordinate helpers. Nothing here
moves a turtle or touches nav's saved state.
--]]

-- A world for findPath: blocks listed as "x,y,z" = kind (or { kind,
-- name }), everything else `rest` (nil for unknown).
local function world(blocks, rest)
  return function(x, y, z)
    local b = blocks[x .. "," .. y .. "," .. z]
    if type(b) == "table" then return b[1], b[2] end
    if b ~= nil then return b end
    return rest
  end
end

-- Every block a path moves into.
local function visited(steps)
  local list = {}
  for _, s in ipairs(steps) do
    if s.action ~= "turnLeft" and s.action ~= "turnRight" then
      list[#list + 1] = s.x .. "," .. s.y .. "," .. s.z
    end
  end
  return list
end

local function actions(steps)
  local list = {}
  for _, s in ipairs(steps) do list[#list + 1] = s.action end
  return list
end

local origin = { x = 0, y = 0, z = 0, h = 0 }

describe("nav.findPath in open space", function()
  it("goes straight ahead without turning", function()
    local steps, cost = nav.findPath(origin, { x = 0, y = 0, z = -3 }, world({}, "a"))
    expect.same(actions(steps), { "forward", "forward", "forward" })
    expect.equal(cost, 3)
  end)
  it("returns no steps when already there", function()
    local steps, cost = nav.findPath(origin, { x = 0, y = 0, z = 0 }, world({}, "a"))
    expect.same(steps, {})
    expect.equal(cost, 0)
  end)
  it("counts a turn like a move", function()
    local steps, cost = nav.findPath(origin, { x = 2, y = 0, z = 0 }, world({}, "a"))
    expect.same(actions(steps), { "turnRight", "forward", "forward" })
    expect.equal(cost, 3)
  end)
  it("turns round for a goal behind", function()
    local steps, cost = nav.findPath(origin, { x = 0, y = 0, z = 2 }, world({}, "a"))
    expect.equal(cost, 4)
    expect.same(visited(steps), { "0,0,1", "0,0,2" })
  end)
  it("goes up and down without turning", function()
    local steps, cost = nav.findPath(origin, { x = 0, y = 3, z = 0 }, world({}, "a"))
    expect.same(actions(steps), { "up", "up", "up" })
    expect.equal(cost, 3)
  end)
  it("makes one turn rather than zig-zagging", function()
    local steps, cost = nav.findPath(origin, { x = 3, y = 0, z = -3 }, world({}, "a"))
    expect.equal(cost, 7)
    local turns = 0
    for _, a in ipairs(actions(steps)) do
      if a == "turnLeft" or a == "turnRight" then turns = turns + 1 end
    end
    expect.equal(turns, 1)
  end)
  it("costs a turn more when turns are dearer", function()
    local _, cost = nav.findPath(origin, { x = 2, y = 0, z = 0 }, world({}, "a"), { turnCost = 5 })
    expect.equal(cost, 7)
  end)
  it("gives where the turtle is after every step", function()
    local steps = nav.findPath(origin, { x = 1, y = 1, z = 0 }, world({}, "a"))
    local last = steps[#steps]
    expect.same({ last.x, last.y, last.z }, { 1, 1, 0 })
    expect.equal(steps[1].h ~= nil, true)
  end)
end)

describe("nav.findPath around obstacles", function()
  -- A wall across the way north at z, 3 wide and 2 high, centred on x 0.
  local function wallAt(z)
    local b = {}
    for x = -1, 1 do
      for y = 0, 1 do b[x .. "," .. y .. "," .. z] = "s" end
    end
    return b
  end

  it("goes round a wall it may not dig", function()
    local blocks = wallAt(-2)
    local steps, cost = nav.findPath(origin, { x = 0, y = 0, z = -4 }, world(blocks, "a"))
    expect.truthy(steps)
    for _, k in ipairs(visited(steps)) do
      expect.falsy(blocks[k], "walked into the wall at " .. k)
    end
    expect.truthy(cost > 4)
  end)
  it("digs straight through when allowed and cheaper", function()
    local blocks = wallAt(-2)
    local steps, cost = nav.findPath(origin, { x = 0, y = 0, z = -4 }, world(blocks, "a"), { dig = true, digCost = 1 })
    expect.same(visited(steps), { "0,0,-1", "0,0,-2", "0,0,-3", "0,0,-4" })
    expect.equal(cost, 5)
  end)
  it("still goes round when digging costs more than the detour", function()
    local blocks = { ["0,0,-2"] = "s" }
    local steps = nav.findPath(origin, { x = 0, y = 0, z = -4 }, world(blocks, "a"), { dig = true, digCost = 10 })
    for _, k in ipairs(visited(steps)) do expect.falsy(k == "0,0,-2") end
  end)
  it("never digs protected blocks", function()
    local blocks = { ["0,0,-1"] = { "s", "minecraft:chest" } }
    local steps = nav.findPath(origin, { x = 0, y = 0, z = -2 }, world(blocks, "a"), { dig = true, digCost = 0 })
    for _, k in ipairs(visited(steps)) do expect.falsy(k == "0,0,-1", "dug the chest") end
  end)
  it("never digs blocks protected by the caller", function()
    local blocks = { ["0,0,-1"] = { "s", "minecraft:glass" } }
    local steps = nav.findPath(origin, { x = 0, y = 0, z = -2 }, world(blocks, "a"), { dig = true, digCost = 0, protect = { "minecraft:glass" } })
    for _, k in ipairs(visited(steps)) do expect.falsy(k == "0,0,-1", "dug the glass") end
  end)
  it("never enters unbreakable blocks or turtles", function()
    for _, kind in ipairs({ "u", "t" }) do
      local blocks = { ["0,0,-1"] = kind }
      local steps = nav.findPath(origin, { x = 0, y = 0, z = -2 }, world(blocks, "a"), { dig = true })
      for _, k in ipairs(visited(steps)) do expect.falsy(k == "0,0,-1", kind) end
    end
  end)
  it("walks through liquids", function()
    local blocks = { ["0,0,-1"] = { "l", "minecraft:water" } }
    local steps, cost = nav.findPath(origin, { x = 0, y = 0, z = -2 }, world(blocks, "a"))
    expect.equal(cost, 2)
  end)
  it("keeps out of blocks the caller rules out", function()
    local steps = nav.findPath(origin, { x = 0, y = 0, z = -2 }, world({}, "a"), {
      blocked = function(x, y, z) return x == 0 and y == 0 and z == -1 end,
    })
    for _, k in ipairs(visited(steps)) do expect.falsy(k == "0,0,-1") end
  end)
  it("stays within minY and maxY", function()
    -- the way north is walled at y 0 and 1; under it is ruled out by minY
    local blocks = wallAt(-1)
    local steps = nav.findPath(origin, { x = 0, y = 0, z = -2 }, world(blocks, "a"), { minY = 0 })
    for _, s in ipairs(steps) do expect.truthy(s.y >= 0) end
  end)
end)

describe("nav.findPath with unknown space", function()
  it("crosses unknown space when there is nothing better", function()
    local steps, cost = nav.findPath(origin, { x = 0, y = 0, z = -3 }, world({}, nil))
    expect.equal(#visited(steps), 3)
    expect.equal(cost, 6, "each unknown block costs one more")
  end)
  it("prefers a known corridor over a slightly shorter unknown way", function()
    -- straight north is unknown; a known air corridor goes up, north and down
    local blocks = {}
    for z = 0, -4, -1 do blocks["0,1," .. z] = "a" end
    blocks["0,0,-4"] = "a"
    local steps = nav.findPath(origin, { x = 0, y = 0, z = -4 }, world(blocks, nil), { unknownCost = 2 })
    expect.same(actions(steps), { "up", "forward", "forward", "forward", "forward", "down" })
  end)
  it("takes the unknown way when the known one is much longer", function()
    local blocks = {}
    for z = 0, -4, -1 do blocks["0,5," .. z] = "a" end
    local steps = nav.findPath(origin, { x = 0, y = 0, z = -4 }, world(blocks, nil), { unknownCost = 1 })
    expect.same(actions(steps), { "forward", "forward", "forward", "forward" })
  end)
end)

describe("nav.findPath when there is no way", function()
  -- A closed box of solid around the goal in a known world.
  local function boxed(kind, name)
    local blocks = {}
    for x = -1, 1 do
      for y = -1, 1 do
        for z = -6, -4 do
          if not (x == 0 and y == 0 and z == -5) then blocks[x .. "," .. y .. "," .. z] = { kind, name } end
        end
      end
    end
    return blocks
  end
  local goal = { x = 0, y = 0, z = -5 }

  it("fails when the goal is shut in and digging is not allowed", function()
    local steps, reason = nav.findPath(origin, goal, world(boxed("s"), "a"), { maxNodes = 3000 })
    expect.falsy(steps)
    expect.match(reason, "no route")
  end)
  it("digs in when allowed", function()
    local steps, cost = nav.findPath(origin, goal, world(boxed("s"), "a"), { dig = true, digCost = 3 })
    expect.truthy(steps)
    expect.equal(#visited(steps), 5)
    expect.equal(cost, 5 + 3)
  end)
  it("fails when the box is chests even with digging", function()
    local steps, reason = nav.findPath(origin, goal, world(boxed("s", "minecraft:chest"), "a"), { dig = true, maxNodes = 3000 })
    expect.falsy(steps)
    expect.match(reason, "no route")
  end)
  it("fails at once when the goal itself is blocked", function()
    local steps, reason = nav.findPath(origin, goal, world({ ["0,0,-5"] = "s" }, "a"))
    expect.falsy(steps)
    expect.match(reason, "is blocked")
  end)
  it("stops at the node limit in a world that never ends", function()
    -- Known solid everywhere except an endless corridor going nowhere.
    local cellAt = function(x, y, z)
      if y == 0 and z == 0 then return "a" end
      if x == 0 and y == 0 and z == -5 then return "a" end
      return "s"
    end
    local steps, reason, expanded = nav.findPath(origin, goal, cellAt, { maxNodes = 200 })
    expect.falsy(steps)
    expect.match(reason, "within 200")
  end)
  it("calls yield during a long search", function()
    local calls = 0
    nav.findPath(origin, goal, world(boxed("s"), "a"), { maxNodes = 1200, yield = function() calls = calls + 1 end })
    expect.truthy(calls >= 2)
  end)
end)

describe("nav helpers", function()
  it("parses headings by name, letter and number", function()
    expect.equal(nav.parseHeading("north"), 0)
    expect.equal(nav.parseHeading("E"), 1)
    expect.equal(nav.parseHeading("south"), 2)
    expect.equal(nav.parseHeading("3"), 3)
    expect.equal(nav.parseHeading(5), 1)
    expect.equal(nav.parseHeading("up"), nil)
  end)
  it("names headings", function()
    expect.equal(nav.headingName(0), "north")
    expect.equal(nav.headingName(3), "west")
  end)
  it("finds blocks relative to a turtle facing each way", function()
    -- one forward, two right, one up
    expect.same({ nav.relative({ x = 0, y = 0, z = 0, h = 0 }, 2, 1, 1) }, { 2, 1, -1 })
    expect.same({ nav.relative({ x = 0, y = 0, z = 0, h = 1 }, 2, 1, 1) }, { 1, 1, 2 })
    expect.same({ nav.relative({ x = 0, y = 0, z = 0, h = 2 }, 2, 1, 1) }, { -2, 1, 1 })
    expect.same({ nav.relative({ x = 10, y = 64, z = 10, h = 3 }, 2, 0, 1) }, { 9, 64, 8 })
  end)
  it("classifies what inspect says", function()
    expect.same({ nav.classify(false, "No block to inspect") }, { "a" })
    expect.same({ nav.classify(true, { name = "minecraft:stone" }) }, { "s", "minecraft:stone" })
    expect.same({ nav.classify(true, { name = "minecraft:water" }) }, { "l", "minecraft:water" })
    expect.same({ nav.classify(true, { name = "minecraft:bedrock" }) }, { "u", "minecraft:bedrock" })
    expect.same({ nav.classify(true, { name = "computercraft:turtle_advanced" }) }, { "t", "computercraft:turtle_advanced" })
  end)
  it("protects containers and computers", function()
    expect.truthy(nav.isProtected("minecraft:chest"))
    expect.truthy(nav.isProtected("minecraft:trapped_chest"))
    expect.truthy(nav.isProtected("computercraft:computer_advanced"))
    expect.truthy(nav.isProtected("minecraft:red_bed"))
    expect.falsy(nav.isProtected("minecraft:stone"))
    expect.falsy(nav.isProtected(nil))
    expect.truthy(nav.isProtected("minecraft:glass", { "minecraft:glass" }))
    expect.truthy(nav.isProtected("minecraft:oak_log", { "_log$" }))
  end)
end)
