--[[
Turtle inventory reads the turtle's slots and works out what each
item is good for: whether the turtle can burn it as fuel and whether
it looks like a block that can be placed. The item tables it builds
are plain data, so they can be sent over rednet to the turtle control
monitor and drawn there with the same code as on the turtle.

An item table has: slot, name, count, damage, displayName, maxCount,
maxDamage, fuel (true/false, or nil when unknown), block (true/false)
and tags (a sorted list of tag names, when the game reports them).
--]]

MinSlot = 1
MaxSlot = 16

-- Fuel checks have to select the slot and ask the turtle, so the
-- answer is cached per item name to keep rescans cheap.
local fuelCache = {}

-- Tag suffixes that only placeable blocks carry.
local blockTags = {
  "logs", "planks", "slabs", "stairs", "walls", "fences", "fence_gates",
  "doors", "trapdoors", "rails", "buttons", "pressure_plates", "saplings",
  "leaves", "flowers", "wool", "carpets", "terracotta", "concrete",
  "candles", "beds", "banners", "signs", "shulker_boxes", "ores",
  "coral_blocks", "dirt", "sand", "ice", "anvil", "bricks", "_blocks",
}

-- Name fragments that usually mean a block, and fragments that
-- mean an item even when the first list matches (stone_pickaxe).
local blockNames = {
  "stone", "cobble", "dirt", "grass", "sand", "gravel", "log", "planks",
  "leaves", "sapling", "ore", "wool", "glass", "bricks", "brick_block",
  "torch", "chest", "furnace", "crafting_table", "ladder", "rail", "fence",
  "door", "slab", "stairs", "wall", "obsidian", "netherrack", "glowstone",
  "clay", "terracotta", "concrete", "ice", "snow", "block", "wood",
  "lantern", "lamp", "carpet", "bookshelf", "sponge", "pumpkin", "melon",
  "cactus", "hay", "tnt", "piston", "hopper", "dropper", "dispenser",
  "observer", "lever", "button", "plate", "redstone", "bed", "sign",
  "banner", "shulker", "anvil", "enchanting_table", "beacon", "mycelium",
  "podzol", "mud", "moss", "basalt", "blackstone", "deepslate", "tuff",
  "calcite", "andesite", "diorite", "granite", "amethyst", "dripstone",
  "sculk", "nylium", "shroomlight", "fungus", "roots", "vine", "kelp",
  "coral", "prismarine", "purpur", "quartz", "barrel", "composter",
  "loom", "smoker", "stonecutter", "grindstone", "bell", "campfire",
  "scaffolding", "cauldron", "brewing_stand", "jukebox", "note_block",
  "noteblock", "tripwire", "web", "flower", "tulip", "lily", "fern",
  "bush", "mushroom", "bars", "cane", "bamboo", "sea_lantern", "rose",
  "dandelion", "wart_block", "end_stone", "end_rod", "chorus",
}
local itemNames = {
  "ingot", "nugget", "dust", "seeds", "pickaxe", "_axe", "shovel", "hoe",
  "sword", "bucket", "boat", "minecart", "stick$", "bowl", "ball", "slice",
  "pie", "bottle", "brick$", "soup", "stew", "bread", "blaze_powder",
  "shard", "crystal", "map$", "book$", "arrow", ":egg$", "wheat$",
  "string", "feather", "leather", "paper", "sugar$", "gunpowder",
  "flint$", "pearl", "fishing_rod", "blaze_rod", "breeze_rod", "tear",
  "shears", "helmet", "chestplate", "leggings", "boots", "potion",
  "music_disc", "charcoal", "coal$", "spyglass", "quartz$", "fruit",
  "dried_kelp$", "pattern",
}

local function anyMatch(s, patterns)
  for _, p in ipairs(patterns) do
    if string.find(s, p) then return true end
  end
  return false
end

-- Guess whether the item can be placed as a block. ComputerCraft
-- does not say, so this looks at the creative tab and item tags when
-- the turtle reports them (CC: Tweaked) and falls back to the name.
-- tags is a list of tag names.
function guessBlock(name, groups, tags)
  if type(groups) == "table" and next(groups) then
    for _, g in pairs(groups) do
      local id = string.lower(tostring(g.id or "") .. " " .. tostring(g.displayName or ""))
      if string.find(id, "block") then return true end
    end
    return false
  end
  if type(tags) == "table" then
    for _, tag in ipairs(tags) do
      for _, suffix in ipairs(blockTags) do
        if string.sub(tag, -#suffix) == suffix then return true end
      end
    end
  end
  local short = string.lower(name)
  if anyMatch(short, itemNames) then return false end
  return anyMatch(short, blockNames)
end

-- Ask the turtle whether the slot holds fuel. refuel(0) answers
-- without burning anything but needs the slot selected, so when
-- allowSelect is false (a job is running) only cached answers are
-- given and nil means unknown.
function isFuel(slot, name, allowSelect)
  if fuelCache[name] ~= nil then return fuelCache[name] end
  if allowSelect == false then return nil end
  local ok, fuel = false, false
  local selected = turtle.getSelectedSlot()
  if turtle.select(slot) then
    ok, fuel = pcall(turtle.refuel, 0)
    turtle.select(selected)
  end
  fuel = ok and fuel == true
  fuelCache[name] = fuel
  return fuel
end

-- Human friendly short name: the display name when known, otherwise
-- the id without its mod prefix and underscores.
function shortName(item)
  if item.displayName then return item.displayName end
  local name = tostring(item.name):gsub("^[^:]+:", ""):gsub("_", " ")
  return name
end

-- Read one slot into an item table, or nil when it is empty. Detailed
-- information is only available on newer versions, so it is optional.
function readSlot(slot, allowSelect)
  local basic = turtle.getItemDetail(slot)
  if not basic then return nil end
  local item = {
    slot = slot,
    name = basic.name or "?",
    count = basic.count or 0,
    damage = basic.damage,
  }
  local ok, detail = pcall(turtle.getItemDetail, slot, true)
  local groups = nil
  if ok and type(detail) == "table" and detail.displayName then
    item.displayName = detail.displayName
    item.maxCount = detail.maxCount
    item.maxDamage = detail.maxDamage
    if detail.damage then item.damage = detail.damage end
    if type(detail.tags) == "table" then
      item.tags = {}
      for tag, on in pairs(detail.tags) do
        if on then table.insert(item.tags, tag) end
      end
      table.sort(item.tags)
    end
    groups = detail.itemGroups
  end
  item.fuel = isFuel(slot, item.name, allowSelect)
  item.block = guessBlock(item.name, groups, item.tags)
  return item
end

-- Read every slot. Returns a table of slot -> item.
function scan(allowSelect)
  local items = {}
  for slot = MinSlot, MaxSlot do
    items[slot] = readSlot(slot, allowSelect)
  end
  return items
end

-- Has the slot's content changed between two reads?
function changed(before, after)
  if (before == nil) ~= (after == nil) then return true end
  if not before then return false end
  return before.name ~= after.name or before.count ~= after.count
      or before.damage ~= after.damage or before.fuel ~= after.fuel
end

-- The rows a detail screen shows for an item: a list of
-- { label, value, color }. Tags are returned separately by tagText.
function detailRows(item)
  local rows = {}
  local function row(label, value, color)
    table.insert(rows, { label = label, value = tostring(value), color = color or colors.white })
  end
  row("Name", item.name)
  if item.displayName then row("Display", item.displayName) end
  row("Count", tostring(item.count) .. (item.maxCount and (" / " .. item.maxCount) or ""))
  if item.maxDamage and item.maxDamage > 0 then
    row("Damage", tostring(item.damage or 0) .. " / " .. item.maxDamage)
  elseif item.damage and item.damage ~= 0 then
    row("Damage", item.damage)
  end
  if item.fuel == nil then
    row("Fuel", "unknown while a job runs", colors.lightGray)
  else
    row("Fuel", item.fuel and "yes, burns in the turtle" or "no", item.fuel and colors.orange or colors.white)
  end
  row("Block", item.block and "yes, looks placeable" or "no, probably an item", item.block and colors.lime or colors.white)
  return rows
end

-- The item's tags as one line of text without the minecraft: prefix.
function tagText(item)
  if type(item.tags) ~= "table" or #item.tags == 0 then return nil end
  local short = {}
  for i, tag in ipairs(item.tags) do short[i] = (tag:gsub("^minecraft:", "")) end
  return table.concat(short, " ")
end

-- Break text into lines no longer than width, at spaces when possible.
function wrap(text, width)
  local lines = {}
  while #text > 0 do
    local chunk = string.sub(text, 1, width)
    if #text > width then
      local cut = chunk:match("^(.*) ")
      if cut and #cut > 0 then chunk = cut end
    end
    table.insert(lines, chunk)
    text = text:sub(#chunk + 1):gsub("^ ", "")
  end
  return lines
end
