--[[
Tests for crafting: the recipe sums the storage computer does, and the
crafter turtle's job against a fake chest and a fake crafting table.
--]]

local sticks = { name = "Sticks", grid = { [2] = "minecraft:oak_planks", [5] = "minecraft:oak_planks" } }
local torch = { name = "Torch", grid = { [1] = "minecraft:coal", [4] = "minecraft:stick" },
                output = { name = "minecraft:torch", count = 4 } }
local pearls = { name = "Eye", grid = { [1] = "minecraft:ender_pearl", [2] = "minecraft:blaze_powder" } }

describe("recipes", function()
  it("adds up what one craft needs", function()
    expect.same(crafting.needs(sticks), { ["minecraft:oak_planks"] = 2 })
    expect.same(crafting.cells(sticks), { 2, 5 })
  end)

  it("works out how many crafts storage is enough for, and what runs out", function()
    local items = { ["minecraft:coal"] = { count = 10 }, ["minecraft:stick"] = { count = 3 } }
    local n, short = crafting.maxCrafts(torch, items)
    expect.equal(n, 3)
    expect.equal(short, "minecraft:stick")
    expect.equal((crafting.maxCrafts(sticks, {})), 0)
  end)

  it("keeps a batch to a stack of every ingredient", function()
    local maxCount = function(key) return key == "minecraft:ender_pearl" and 16 or 64 end
    expect.equal(crafting.batchSize(pearls, 100, maxCount), 16)
    expect.equal(crafting.batchSize(sticks, 100, maxCount), 64)
    expect.equal(crafting.batchSize(sticks, 5, maxCount), 5)
  end)

  it("turns items wanted into crafts", function()
    expect.equal(crafting.craftsFor(torch, 10), 3)
    expect.equal(crafting.itemsFrom(torch, 3), 12)
    expect.equal(crafting.craftsFor(sticks, 10), 10)
  end)

  it("finds a recipe by name", function()
    local list = { sticks, torch, { name = "Torch Wall", grid = {} } }
    expect.equal(crafting.findRecipe(list, "sticks"), sticks)
    expect.equal(crafting.findRecipe(list, "TORCH"), torch)
    expect.equal(crafting.findRecipe(list, "stic"), sticks)
    local none, why = crafting.findRecipe(list, "chest")
    expect.equal(none, nil)
    expect.match(why, "no recipe")
  end)

  it("shortens names to whole words", function()
    expect.equal(crafting.shortName("Oak Planks", 20), "Oak Planks")
    expect.equal(crafting.shortName("Polished Blackstone Bricks", 12), "Polished")
    expect.equal(crafting.shortName("Cobblestone", 6), "Cobble")
  end)

  it("saves and loads recipes", function()
    local path = "/.recipes_test.cfg"
    expect.same(crafting.loadRecipes(path), {})
    crafting.saveRecipes({ sticks, torch }, path)
    local back = crafting.loadRecipes(path)
    expect.equal(#back, 2)
    expect.same(back[2], torch)
    fs.delete(path)
  end)
end)

-- A chest beside the turtle and a crafting table that knows one
-- recipe: two planks (anywhere in a column) make four sticks.
local function station(chestSlots, opts)
  opts = opts or {}
  local fake = testing.fakeTurtle({ slots = opts.turtleSlots })
  testing.useTurtle(fake)
  local chest = { slots = chestSlots, size = opts.size or 27 }
  local io = { side = "front", chest = {} }
  io.chest.list = function()
    local out = {}
    for i, s in pairs(chest.slots) do out[i] = { name = s.name, count = s.count } end
    return out
  end
  io.suck = function(count)
    for i = 1, chest.size do
      local s = chest.slots[i]
      if s then
        local n = math.min(count or 64, s.count)
        local into = fake.slots[fake.selected]
        if into and into.name ~= s.name then return false end
        fake.slots[fake.selected] = { name = s.name, count = (into and into.count or 0) + n }
        s.count = s.count - n
        if s.count == 0 then chest.slots[i] = nil end
        return true
      end
    end
    return false, "No items to take"
  end
  io.drop = function()
    local s = fake.slots[fake.selected]
    if not s then return false end
    for i = 1, chest.size do
      if not chest.slots[i] then
        chest.slots[i] = s
        fake.slots[fake.selected] = nil
        return true
      end
    end
    return false, "No space for items"
  end
  io.craft = function(n)
    if opts.craft then return opts.craft(fake, n) end
    local grid = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }
    local planks = {}
    for _, slot in ipairs(grid) do
      local s = fake.slots[slot]
      if s and s.name ~= "minecraft:oak_planks" then return false, "No matching recipes" end
      if s then planks[#planks + 1] = slot end
    end
    if #planks ~= 2 then return false, "No matching recipes" end
    for slot = 1, 16 do
      local inGrid = false
      for _, g in ipairs(grid) do if g == slot then inGrid = true end end
      if not inGrid and fake.slots[slot] then return false, "No matching recipes" end
    end
    local k = math.min(n, fake.slots[planks[1]].count, fake.slots[planks[2]].count)
    for _, slot in ipairs(planks) do
      local s = fake.slots[slot]
      s.count = s.count - k
      if s.count == 0 then fake.slots[slot] = nil end
    end
    local made = k * 4
    for _, slot in ipairs({ 16, 4, 8, 12, 13, 14, 15 }) do
      if made <= 0 then break end
      if not fake.slots[slot] then
        fake.slots[slot] = { name = "minecraft:stick", count = math.min(64, made) }
        made = made - 64
      end
    end
    fake.crafts = (fake.crafts or 0) + 1
    return true
  end
  return io, chest, fake
end

local function chestCount(chest, name)
  local n = 0
  for _, s in pairs(chest.slots) do if s.name == name then n = n + s.count end end
  return n
end

local planks = function(n) return { name = "minecraft:oak_planks", count = n } end
local stickJob = function(n)
  return { jobId = "1:1", crafts = n, grid = { [2] = planks(n), [5] = planks(n) } }
end

describe("crafter jobs", function()
  it("takes the ingredients, crafts and puts the results in the chest", function()
    local io, chest, fake = station({ [2] = planks(40), [5] = planks(40) })
    local r = crafting.runJob(stickJob(40), io)
    expect.truthy(r.ok, r.why)
    expect.equal(r.crafted, 40)
    expect.same({ r.output.name, r.output.count }, { "minecraft:stick", 4 })
    expect.equal(chestCount(chest, "minecraft:stick"), 160)
    expect.equal(chestCount(chest, "minecraft:oak_planks"), 0)
    for slot = 1, 16 do expect.equal(fake.slots[slot], nil, "slot " .. slot) end
    -- one craft first, then rounds whose results fit outside the grid
    expect.equal(fake.crafts, 1 + math.ceil(39 / math.floor(7 * 64 / 4)))
  end)

  it("puts the cells in the right turtle slots", function()
    local seen
    local io, chest = station({ [1] = { name = "minecraft:coal", count = 3 }, [4] = { name = "minecraft:stick", count = 3 } }, {
      craft = function(fake)
        seen = { fake.slots[1] and fake.slots[1].name, fake.slots[5] and fake.slots[5].name }
        return false, "No matching recipes"
      end,
    })
    local r = crafting.runJob({ crafts = 3, grid = { [1] = { name = "minecraft:coal", count = 3 },
                                                      [4] = { name = "minecraft:stick", count = 3 } } }, io)
    expect.same(seen, { "minecraft:coal", "minecraft:stick" })
    expect.falsy(r.ok)
    expect.equal(r.why, "No matching recipes")
    -- everything went back
    expect.equal(chestCount(chest, "minecraft:coal"), 3)
    expect.equal(chestCount(chest, "minecraft:stick"), 3)
  end)

  it("refuses a chest that does not hold what the job says", function()
    local io, chest = station({ [2] = planks(10), [5] = { name = "minecraft:dirt", count = 10 } })
    local r = crafting.runJob(stickJob(10), io)
    expect.falsy(r.ok)
    expect.match(r.why, "does not hold")
    expect.equal(r.crafted, 0)
    expect.equal(chestCount(chest, "minecraft:dirt"), 10)
  end)

  it("refuses items the recipe does not use", function()
    local io = station({ [2] = planks(1), [5] = planks(1), [12] = planks(1) })
    local r = crafting.runJob(stickJob(1), io)
    expect.match(r.why, "slot 12")
  end)

  it("empties itself first when it holds anything", function()
    local io, chest = station({}, { turtleSlots = { [3] = { name = "minecraft:coal", count = 5 } } })
    local r = crafting.runJob(stickJob(1), io)
    expect.falsy(r.ok)
    expect.match(r.why, "not empty")
    expect.equal(chestCount(chest, "minecraft:coal"), 5)
  end)

  it("stops when the chest is too full for the results", function()
    local io, chest = station({ [2] = planks(2), [5] = planks(2) }, { size = 5 })
    -- fill the rest of the chest once the turtle has taken the planks
    local craft = io.craft
    io.craft = function(n)
      for i = 1, 5 do chest.slots[i] = chest.slots[i] or { name = "minecraft:dirt", count = 64 } end
      return craft(n)
    end
    local r = crafting.runJob(stickJob(2), io)
    expect.falsy(r.ok)
    expect.match(r.why, "full")
  end)
end)
