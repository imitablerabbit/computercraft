--[[
Tests for the depot's side of apis/depot.lua: where a turtle stands
for a chest, checking chest records, and picking the nearest chest
that can be used. The turtle's trips are covered by the fleet
scenario's checks.
--]]

local function chest(name, role, x, y, z, access)
  return depot.newChest(name, role, x, y, z, access)
end

describe("depot.standFor", function()
  it("stands beside the chest facing it", function()
    local c = chest("F", "fuel", 10, 64, 5, "north")
    local s, face = depot.standFor(c)
    expect.same(s, { x = 10, y = 64, z = 4 })
    expect.equal(face, 2) -- south, towards the chest
    s, face = depot.standFor(chest("F", "fuel", 10, 64, 5, "west"))
    expect.same(s, { x = 9, y = 64, z = 5 })
    expect.equal(face, 1)
  end)
  it("stands on top of the chest and drops down", function()
    local s, face = depot.standFor(chest("D", "dump", 0, 63, 0, "above"))
    expect.same(s, { x = 0, y = 64, z = 0 })
    expect.equal(face, "down")
  end)
end)

describe("depot.newChest", function()
  it("checks the role, coordinates and access side", function()
    expect.truthy(chest("A", "dump", "1", "2", "3", "east"))
    expect.match(select(2, depot.newChest("A", "trash", 1, 2, 3, "east")), "role")
    expect.match(select(2, depot.newChest("A", "dump", 1, "two", 3, "east")), "numbers")
    expect.match(select(2, depot.newChest("A", "dump", 1, 2, 3, "inside")), "access")
    expect.match(select(2, depot.newChest("", "dump", 1, 2, 3, "east")), "name")
  end)
  it("keeps the peripheral name unless it is none", function()
    expect.equal(depot.newChest("A", "dump", 1, 2, 3, "east", "minecraft:chest_0").peripheral, "minecraft:chest_0")
    expect.equal(depot.newChest("A", "dump", 1, 2, 3, "east", "none").peripheral, nil)
  end)
end)

describe("depot.nearest and depot.answer", function()
  local chests = {
    chest("Near dump", "dump", 2, 64, 0, "north"),
    chest("Far dump", "dump", 50, 64, 0, "north"),
    chest("Fuel", "fuel", 0, 64, 10, "south"),
  }

  it("finds the nearest chest with the role", function()
    local c, d = depot.nearest(chests, "dump", 0, 64, 0)
    expect.equal(c.name, "Near dump")
    expect.equal(d, 3)
  end)
  it("skips full dumps, empty fuel chests and excluded names", function()
    local lv = { ["Near dump"] = { used = 27, size = 27, items = 1000 }, Fuel = { used = 0, size = 27, items = 0 } }
    expect.equal(depot.nearest(chests, "dump", 0, 64, 0, lv).name, "Far dump")
    expect.equal(depot.nearest(chests, "dump", 0, 64, 0, nil, { "Near dump" }).name, "Far dump")
    local c, why = depot.nearest(chests, "fuel", 0, 64, 0, lv)
    expect.falsy(c)
    expect.match(why, "Fuel is empty")
  end)
  it("answers with the stand block, the face and the level", function()
    local lv = { Fuel = { used = 2, size = 27, items = 80 } }
    local a = depot.answer(chests, { role = "fuel", x = 0, y = 64, z = 0 }, lv, "Depot")
    expect.truthy(a.ok)
    expect.equal(a.name, "Fuel")
    expect.same(a.stand, { x = 0, y = 64, z = 11 })
    expect.equal(a.face, 0)
    expect.equal(a.items, 80)
    expect.equal(a.depot, "Depot")
  end)
  it("says why it has nothing", function()
    expect.falsy(depot.answer(chests, { role = "materials", x = 0, y = 0, z = 0 }).ok)
    expect.match(depot.answer(chests, { role = "dump" }).message, "x, y, z")
    expect.match(depot.answer(chests, { role = "lava", x = 0, y = 0, z = 0 }).message, "unknown role")
  end)
end)

describe("the depot config", function()
  it("is saved and read back, dropping broken records", function()
    local path = "/tmp_depot_test.cfg"
    expect.truthy(depot.saveConfig({ chests = { chest("A", "dump", 1, 2, 3, "east"), { name = "bad" } } }, path))
    local cfg = depot.loadConfig(path)
    fs.delete(path)
    expect.equal(#cfg.chests, 1)
    expect.equal(cfg.chests[1].name, "A")
  end)
end)
