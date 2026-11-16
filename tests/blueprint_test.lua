--[[
Tests for the blueprint API: parsing the text format, writing it back,
positions, palettes made up on the fly and counting materials.
--]]

local hut = table.concat({
  "--[[",
  "-- a tiny test hut",
  "name Test hut",
  "# = minecraft:cobblestone",
  "= = minecraft:oak_planks",
  "layer 1 (walls)",
  "###",
  "#.#",
  "#.#",
  "",
  "layer 2 roof",
  "===",
  "= =",
  "===",
  "]]",
}, "\n")

describe("blueprint.parse", function()
  it("reads the name, palette and layers", function()
    local bp = assert(blueprint.parse(hut))
    expect.equal(bp.name, "Test hut")
    expect.equal(bp.width, 3)
    expect.equal(bp.length, 3)
    expect.equal(bp.height, 2)
    expect.equal(bp.palette["#"], "minecraft:cobblestone")
    expect.equal(bp.palette["."], "air")
  end)
  it("puts the front row last and counts layers from the bottom", function()
    local bp = assert(blueprint.parse(table.concat({
      "a = minecraft:stone", "b = minecraft:dirt", "layer", "aaa", "b..", "layer", "...", "..a",
    }, "\n")))
    expect.equal(blueprint.at(bp, 0, 0, 0), "minecraft:dirt", "front left of the bottom layer")
    expect.equal(blueprint.at(bp, 0, 0, 1), "minecraft:stone", "back left")
    expect.equal(blueprint.at(bp, 2, 1, 0), "minecraft:stone", "front right of the top layer")
    expect.equal(blueprint.at(bp, 1, 1, 1), "air")
  end)
  it("treats spaces and short rows as don't care", function()
    local bp = assert(blueprint.parse(hut))
    expect.equal(blueprint.at(bp, 1, 1, 1), nil)
    local bp2 = assert(blueprint.parse("a = minecraft:stone\nlayer\naaa\na\n"))
    expect.equal(bp2.width, 3)
    expect.equal(blueprint.at(bp2, 2, 0, 0), nil)
    expect.equal(bp2.layers[1][2], "a  ")
  end)
  it("keeps a row of spaces as a row", function()
    local bp = assert(blueprint.parse("a = minecraft:stone\nlayer\naa\n  \naa\n"))
    expect.equal(bp.length, 3)
  end)
  it("lets the palette redefine the dot", function()
    local bp = assert(blueprint.parse(". = minecraft:glass\nlayer\n.\n"))
    expect.equal(blueprint.at(bp, 0, 0, 0), "minecraft:glass")
  end)
  it("refuses a character that is not in the palette", function()
    local bp, err = blueprint.parse("a = minecraft:stone\nlayer\nab\n")
    expect.falsy(bp)
    expect.match(err, "line 3: 'b' is not in the palette")
  end)
  it("refuses layers of different lengths", function()
    local bp, err = blueprint.parse("a = minecraft:stone\nlayer\na\na\nlayer\na\n")
    expect.falsy(bp)
    expect.match(err, "layer 2 has 1 rows but layer 1 has 2")
  end)
  it("refuses a bad palette line and a file without layers", function()
    local bp, err = blueprint.parse("ab = minecraft:stone\nlayer\na\n")
    expect.match(err, "line 1")
    bp, err = blueprint.parse("a = minecraft:stone\n")
    expect.match(err, "no layers")
  end)
  it("refuses reserved palette characters", function()
    local bp, err = blueprint.parse("- = minecraft:stone\nlayer\n-\n")
    expect.falsy(bp)
  end)
  it("reads Windows line endings", function()
    local bp = assert(blueprint.parse(hut:gsub("\n", "\r\n")))
    expect.equal(bp.width, 3)
    expect.equal(blueprint.at(bp, 0, 0, 0), "minecraft:cobblestone")
  end)
end)

describe("blueprint.serialize", function()
  it("writes text that parses back to the same blueprint", function()
    local bp = assert(blueprint.parse(hut))
    local text = blueprint.serialize(bp)
    local again = assert(blueprint.parse(text))
    expect.same(again, bp)
  end)
  it("wraps the text in a Lua comment so the installers copy it", function()
    local text = blueprint.serialize(assert(blueprint.parse(hut)))
    expect.match(text, "^%-%-%[%[\n")
    expect.match(text, "\n%]%]\n$")
    expect.truthy(load(text), "the file is valid Lua")
  end)
  it("keeps rows that are all don't care", function()
    local bp = blueprint.new(2, 3, 1)
    blueprint.set(bp, 0, 0, 0, "minecraft:stone")
    local again = assert(blueprint.parse(blueprint.serialize(bp)))
    expect.equal(again.length, 3)
    expect.equal(blueprint.at(again, 0, 0, 0), "minecraft:stone")
  end)
end)

describe("blueprint.set and charFor", function()
  it("picks readable characters for common blocks", function()
    local bp = blueprint.new(1, 1, 1)
    expect.equal(blueprint.charFor(bp, "minecraft:cobblestone"), "#")
    expect.equal(blueprint.charFor(bp, "minecraft:oak_planks"), "=")
    expect.equal(blueprint.charFor(bp, "minecraft:spruce_log"), "o")
    expect.equal(blueprint.charFor(bp, "air"), ".")
    expect.equal(blueprint.charFor(bp, nil), " ")
  end)
  it("reuses a character once given", function()
    local bp = blueprint.new(1, 1, 1)
    local c = blueprint.charFor(bp, "minecraft:cobblestone")
    expect.equal(blueprint.charFor(bp, "minecraft:cobblestone"), c)
  end)
  it("falls back to the block's first letter, then others", function()
    local bp = blueprint.new(1, 1, 1)
    expect.equal(blueprint.charFor(bp, "mod:copper_thing"), "c")
    expect.equal(blueprint.charFor(bp, "mod:cheese"), "C")
    local third = blueprint.charFor(bp, "mod:cabbage")
    expect.truthy(third ~= "c" and third ~= "C" and third ~= " " and third ~= "-")
  end)
  it("sets blocks by position", function()
    local bp = blueprint.new(3, 2, 2)
    blueprint.set(bp, 2, 1, 0, "minecraft:glass")
    expect.equal(blueprint.at(bp, 2, 1, 0), "minecraft:glass")
    expect.equal(bp.layers[2][2], "  g")
    blueprint.set(bp, 2, 1, 0, nil)
    expect.equal(blueprint.at(bp, 2, 1, 0), nil)
  end)
end)

describe("blueprint.materials and missing", function()
  it("counts the blocks to place, not air or don't care", function()
    local bp = assert(blueprint.parse(hut))
    expect.same(blueprint.materials(bp), { ["minecraft:cobblestone"] = 7, ["minecraft:oak_planks"] = 8 })
  end)
  it("lists what is short, sorted by name", function()
    local mats = { ["minecraft:cobblestone"] = 7, ["minecraft:oak_planks"] = 8, ["minecraft:glass"] = 2 }
    local list = blueprint.missing(mats, { ["minecraft:cobblestone"] = 10, ["minecraft:oak_planks"] = 3 })
    expect.same(list, {
      { name = "minecraft:glass", need = 2, have = 0, short = 2 },
      { name = "minecraft:oak_planks", need = 8, have = 3, short = 5 },
    })
  end)
  it("counts the example blueprints", function()
    for _, name in ipairs({ "hut", "watchtower" }) do
      local path = blueprint.find("/blueprints/" .. name)
      expect.truthy(path, name .. " is installed")
      local bp, err = blueprint.load(path)
      expect.truthy(bp, err)
      expect.truthy(next(blueprint.materials(bp)), name .. " has something to build")
    end
  end)
end)
