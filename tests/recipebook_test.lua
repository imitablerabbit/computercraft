--[[
Tests for the built-in recipes (apis/recipebook.lua) and the tags the
crafting API resolves for them.
--]]

local function byName(name)
  for _, r in ipairs(recipebook.Recipes) do
    if r.name == name then return r end
  end
end

describe("recipebook", function()
  it("has the everyday recipes", function()
    for _, name in ipairs({ "Oak Planks", "Stick", "Torch", "Chest", "Crafting Table", "Oak Fence", "Oak Sign",
                            "Oak Door", "Oak Pressure Plate", "Glass Pane", "Iron Pickaxe", "Diamond Chestplate",
                            "Furnace", "Turtle", "Wired Modem" }) do
      expect.truthy(byName(name), name)
    end
  end)

  it("writes every recipe out in full", function()
    local seen = {}
    for _, r in ipairs(recipebook.Recipes) do
      expect.falsy(seen[r.name:lower()], "two recipes called " .. r.name)
      seen[r.name:lower()] = true
      expect.truthy(r.builtin, r.name)
      expect.truthy(r.output.count >= 1, r.name)
      expect.match(r.output.name, "^%w+:[%w_]+$", r.name)
      local cells = 0
      for cell, key in pairs(r.grid) do
        cells = cells + 1
        expect.truthy(type(cell) == "number" and cell >= 1 and cell <= 9, r.name .. " cell " .. tostring(cell))
        if crafting.isTag(key) then
          expect.truthy(#crafting.members(key) > 0, r.name .. ": unknown tag " .. key)
        else
          expect.match(key, "^%w+:[%w_]+$", r.name)
        end
      end
      expect.truthy(cells >= 1, r.name)
    end
  end)

  it("lays the rows out on the 3x3 grid", function()
    expect.same(byName("Chest").grid, {
      "#planks", "#planks", "#planks", "#planks", nil, "#planks", "#planks", "#planks", "#planks",
    })
    expect.same(byName("Oak Fence").grid, {
      [1] = "minecraft:oak_planks", [2] = "minecraft:stick", [3] = "minecraft:oak_planks",
      [4] = "minecraft:oak_planks", [5] = "minecraft:stick", [6] = "minecraft:oak_planks",
    })
    expect.same(byName("Iron Boots").grid, {
      [1] = "minecraft:iron_ingot", [3] = "minecraft:iron_ingot", [4] = "minecraft:iron_ingot", [6] = "minecraft:iron_ingot",
    })
    expect.same(byName("Oak Sign").output, { name = "minecraft:oak_sign", count = 3, displayName = "Oak Sign" })
  end)

  it("names an item differently from its recipe where needed", function()
    local r = byName("Iron Ingot (from nuggets)")
    expect.equal(r.output.displayName, "Iron Ingot")
    expect.equal(r.output.name, "minecraft:iron_ingot")
  end)

  it("lists saved recipes first, in place of built-in ones of the same name", function()
    local mine = { name = "torch", grid = { [1] = "minecraft:charcoal", [4] = "minecraft:stick" } }
    local extra = { name = "My Thing", grid = { [1] = "minecraft:dirt" } }
    local list = recipebook.merge({ extra, mine })
    expect.equal(list[1], extra)
    expect.equal(list[2], mine)
    expect.equal(#list, #recipebook.Recipes + 1)
    for i = 3, #list do expect.truthy(list[i].name:lower() ~= "torch") end
  end)

  it("names tags for people", function()
    expect.equal(recipebook.tagName("#planks"), "Any planks")
    expect.equal(recipebook.tagName("#oak_logs"), "Oak logs (any)")
    expect.equal(recipebook.tagName("#crimson_logs"), "Crimson stems (any)")
  end)
end)

describe("crafting tags", function()
  local chest = { name = "Chest", grid = { "#planks", "#planks", "#planks", "#planks", nil, "#planks", "#planks", "#planks", "#planks" } }

  it("counts a tag as the member storage has most of", function()
    local items = { ["minecraft:oak_planks"] = { count = 10 }, ["minecraft:spruce_planks"] = { count = 30 } }
    local n, item = crafting.stock("#planks", items)
    expect.equal(n, 30)
    expect.equal(item, "minecraft:spruce_planks")
    expect.equal((crafting.stock("minecraft:oak_planks", items)), 10)
    expect.equal((crafting.stock("#planks", {})), 0)
  end)

  it("works out crafts from one kind of planks, not a mix", function()
    local items = { ["minecraft:oak_planks"] = { count = 10 }, ["minecraft:spruce_planks"] = { count = 20 } }
    local n, short = crafting.maxCrafts(chest, items)
    expect.equal(n, 2)
    expect.equal(short, "#planks")
  end)

  it("resolves a tag to the item storage has most of", function()
    local items = { ["minecraft:birch_planks"] = { count = 64 }, ["minecraft:stick"] = { count = 5 } }
    local fence = { name = "Fence", grid = { [1] = "#planks", [2] = "minecraft:stick" }, output = { name = "x", count = 1 } }
    local r = crafting.resolve(fence, items)
    expect.equal(r.grid[1], "minecraft:birch_planks")
    expect.equal(r.grid[2], "minecraft:stick")
    expect.equal(r.output, fence.output)
    expect.equal(fence.grid[1], "#planks")
    local plain = { name = "Plain", grid = { [1] = "minecraft:dirt" } }
    expect.equal(crafting.resolve(plain, items), plain)
  end)
end)
