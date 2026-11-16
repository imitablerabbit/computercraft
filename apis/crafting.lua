--[[
Crafting with a crafty turtle for the storage program.

A recipe is a 3x3 grid of items from storage, by item key (the name, or
name#nbt), with a name and, once it has been crafted, what it makes:

  { name = "Stick", grid = { [2] = "minecraft:oak_planks", [5] = "minecraft:oak_planks" },
    output = { name = "minecraft:stick", count = 4, displayName = "Stick", maxCount = 64 } }

Cells are numbered 1 to 9 row by row, as on a crafting table. The
recipes are kept in /recipes.cfg. The storage computer works out what
a number of crafts needs (needs, maxCrafts, batchSize) and moves the
ingredients into the crafting chest, one cell to a chest slot: slot 1
holds what goes in cell 1 and so on, each slot holding one item per
craft. Then it publishes "base.craft.job" on the bus:

  { jobId, to = <turtle id>, crafts = n, grid = { [cell] = { name, count } } }

The crafter program on a crafty turtle beside that chest (in front,
above or below) answers with "base.craft.done":

  { jobId, ok, crafted, why, output = { name, count, displayName, maxCount } }

runJob does the turtle's part. It checks the chest holds what the job
says, sucks each slot into the turtle's grid (turtle slots 1-3, 5-7 and
9-11; a suck takes from the chest's first slot with items, which is the
next cell because the ones before are already taken), crafts, and drops
everything it made back into the chest, where the storage computer
puts it away. The turtle needs every slot outside the grid empty to
craft, so it crafts in rounds small enough for the results to fit in
the seven slots outside the grid and drops them after each round. Its
first round is a single craft, which shows what the recipe makes.

The crafter says it is there with "base.craft.hello" { busy } when it
starts, every 30 seconds, and when asked with "base.craft.ping".
--]]

RecipeFile = "/recipes.cfg"

-- The turtle slot each grid cell goes in.
GridSlots = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }

--[[
Recipes
--]]

-- Read the recipes: a list, empty when there is no file.
function loadRecipes(path)
  path = path or RecipeFile
  if not fs.exists(path) then return {} end
  local h = fs.open(path, "r")
  if not h then return {} end
  local data = textutils.unserialize(h.readAll() or "")
  h.close()
  if type(data) ~= "table" then return {} end
  local out = {}
  for _, r in ipairs(data) do
    if type(r) == "table" and type(r.grid) == "table" then out[#out + 1] = r end
  end
  return out
end

function saveRecipes(recipes, path)
  local h = fs.open(path or RecipeFile, "w")
  if not h then return false end
  h.write(textutils.serialize(recipes))
  h.close()
  return true
end

-- The cells a recipe uses, in order.
function cells(recipe)
  local out = {}
  for cell = 1, 9 do
    if recipe.grid[cell] then out[#out + 1] = cell end
  end
  return out
end

-- How many of each item one craft takes: key -> count.
function needs(recipe)
  local out = {}
  for cell = 1, 9 do
    local key = recipe.grid[cell]
    if key then out[key] = (out[key] or 0) + 1 end
  end
  return out
end

-- How many crafts the items in storage are enough for. items is the
-- storage index (key -> { count }). Also returns the key that runs out
-- first.
function maxCrafts(recipe, items)
  local best, short = nil, nil
  for key, per in pairs(needs(recipe)) do
    local have = items[key] and items[key].count or 0
    local n = math.floor(have / per)
    if not best or n < best then best, short = n, key end
  end
  return best or 0, short
end

-- Crafts in one trip to the turtle: each cell's items go in one chest
-- slot and one turtle slot, so no more than a stack of any of them.
-- maxCount(key) is an item's stack size.
function batchSize(recipe, remaining, maxCount)
  local n = math.min(remaining, 64)
  for cell = 1, 9 do
    local key = recipe.grid[cell]
    if key then n = math.min(n, maxCount and maxCount(key) or 64) end
  end
  return math.max(0, n)
end

-- Crafts needed to make a number of items, when the recipe's output
-- is known (otherwise the number is taken as crafts).
function craftsFor(recipe, items)
  local per = recipe.output and recipe.output.count or 1
  return math.ceil(items / math.max(1, per))
end

-- How many items a number of crafts makes (crafts when not known).
function itemsFrom(recipe, crafts)
  return crafts * (recipe.output and recipe.output.count or 1)
end

-- A recipe by name: exact (ignoring case) first, then the only one
-- that starts with or contains text. Returns the recipe and its index,
-- or nil and why.
function findRecipe(recipes, text)
  text = tostring(text or ""):lower()
  for i, r in ipairs(recipes) do
    if r.name:lower() == text then return r, i end
  end
  local found = {}
  for i, r in ipairs(recipes) do
    if r.name:lower():find(text, 1, true) then found[#found + 1] = i end
  end
  if #found == 1 then return recipes[found[1]], found[1] end
  if #found == 0 then return nil, "no recipe called " .. text end
  return nil, #found .. " recipes match " .. text
end

-- A name cut to fit width: whole words while they fit, then letters.
function shortName(name, width)
  name = tostring(name or "")
  if #name <= width then return name end
  local out = ""
  for word in name:gmatch("%S+") do
    local next = out == "" and word or (out .. " " .. word)
    if #next > width then break end
    out = next
  end
  if out == "" then out = name:sub(1, width) end
  return out
end

--[[
The turtle's part
--]]

-- The chest a crafter works with and the turtle functions for its
-- side: front, top or bottom (the first with an inventory when side
-- is nil). Returns io = { side, chest, suck, drop, craft } or nil and
-- why.
function turtleIO(side)
  local verbs = {
    front = { "suck", "drop" }, top = { "suckUp", "dropUp" }, bottom = { "suckDown", "dropDown" },
  }
  if side and not verbs[side] then return nil, "the chest must be in front, on top or below" end
  if not side then
    for _, s in ipairs({ "front", "top", "bottom" }) do
      if peripheral.hasType(s, "inventory") then side = s; break end
    end
    if not side then return nil, "no chest in front of, above or below the turtle" end
  end
  local chest = peripheral.wrap(side)
  if not chest or not peripheral.hasType(side, "inventory") then return nil, "no chest " .. side end
  local craft = turtle.craft
  if not craft then
    local bench = peripheral.find and peripheral.find("workbench")
    if bench then craft = bench.craft end
  end
  if not craft then return nil, "no crafting table: equip one (a crafty turtle)" end
  return {
    side = side, chest = chest, craft = craft,
    suck = turtle[verbs[side][1]], drop = turtle[verbs[side][2]],
  }
end

-- Drop every slot into the chest. Returns true when the turtle is empty.
function emptyInto(io)
  local all = true
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      io.drop()
      if turtle.getItemCount(slot) > 0 then all = false end
    end
  end
  turtle.select(1)
  return all
end

-- Do a job (see the top of this file). Returns the done payload
-- without its jobId: { ok, crafted, why, output }.
function runJob(job, io)
  local crafts = tonumber(job.crafts) or 0
  local grid = job.grid or {}
  local result = { ok = false, crafted = 0 }
  local function fail(why)
    result.why = why
    emptyInto(io)
    return result
  end

  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      if not emptyInto(io) then return fail("the turtle has items it cannot put in the chest") end
      return fail("the turtle was not empty; its items are in the chest now")
    end
  end
  if crafts < 1 then return fail("nothing to craft") end

  -- the chest holds each cell's items in that cell's slot and nothing else
  local list = io.chest.list()
  for slot, stack in pairs(list) do
    local want = grid[slot]
    if not want then return fail("the crafting chest has " .. stack.name .. " in slot " .. slot .. ", which the recipe does not use") end
    if stack.name ~= want.name or stack.count < want.count then
      return fail("the crafting chest does not hold " .. want.count .. " " .. want.name .. " in slot " .. slot)
    end
  end

  -- take them into the grid, cell by cell
  local gridName = {}
  for cell = 1, 9 do
    local want = grid[cell]
    if want then
      if not list[cell] then return fail("the crafting chest has nothing in slot " .. cell) end
      local slot = GridSlots[cell]
      turtle.select(slot)
      io.suck(want.count)
      local got = turtle.getItemDetail(slot)
      if not got or got.name ~= want.name or got.count ~= want.count then
        return fail("could not take " .. want.count .. " " .. want.name .. " from the chest")
      end
      gridName[slot] = want.name
    end
  end

  -- craft in rounds, dropping what each round makes
  local per, maxCount = nil, 64
  while result.crafted < crafts do
    local n = 1
    if per then
      n = math.max(1, math.min(crafts - result.crafted, math.floor(7 * maxCount / per)))
    end
    turtle.select(16)
    local ok, err = io.craft(n)
    if not ok then
      result.why = err or "the recipe did not craft"
      break
    end
    -- everything that is not an ingredient in its own slot was made
    local made, details = {}, {}
    for slot = 1, 16 do
      local d = turtle.getItemDetail(slot)
      if d and gridName[slot] ~= d.name then
        made[d.name] = (made[d.name] or 0) + d.count
        if not result.output and not details[d.name] then
          details[d.name] = turtle.getItemDetail(slot, true) or d
        end
        turtle.select(slot)
        io.drop()
        if turtle.getItemCount(slot) > 0 then
          result.crafted = result.crafted + n
          return fail("the crafting chest is full")
        end
      end
    end
    if not result.output then
      local best
      for name, count in pairs(made) do
        if not best or count > made[best] then best = name end
      end
      if best then
        local full = details[best]
        per = math.max(1, math.floor(made[best] / n))
        maxCount = full.maxCount or 64
        result.output = { name = best, count = per, displayName = full.displayName, maxCount = maxCount }
      end
    end
    result.crafted = result.crafted + n
  end

  -- whatever was not used goes back
  if not emptyInto(io) and not result.why then result.why = "the crafting chest is full" end
  result.ok = result.why == nil
  turtle.select(1)
  return result
end
