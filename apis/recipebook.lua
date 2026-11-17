--[[
Built-in crafting recipes for the storage program, from vanilla
Minecraft (1.20 and later) and CC: Tweaked.

They are listed alongside the recipes made on the panel and never saved
to /recipes.cfg; a saved recipe with the same name takes the place of a
built-in one. Each is written as rows of letters, top row first, with
"/" between rows and "." for an empty square, and what each letter is:

  add("Chest", "chest", 1, "PPP/P.P/PPP", { P = "#planks" })

Names without a mod prefix are minecraft: ones. A "#" name is a tag,
one of the Tags below, for recipes that take any of several items (any
planks for a chest); the storage computer uses whichever it has most
of. The recipe tables are those of apis/crafting.lua, with builtin set.
--]]

local function mc(name)
  if name:sub(1, 1) == "#" or name:find(":", 1, true) then return name end
  return "minecraft:" .. name
end

local function list(names)
  local out = {}
  for i, n in ipairs(names) do out[i] = mc(n) end
  return out
end

-- The woods: id, name, log, wood (bark on all sides), and whether it
-- grows in the Nether (no boats).
Woods = {
  { "oak", "Oak", "log", "wood" }, { "spruce", "Spruce", "log", "wood" },
  { "birch", "Birch", "log", "wood" }, { "jungle", "Jungle", "log", "wood" },
  { "acacia", "Acacia", "log", "wood" }, { "dark_oak", "Dark Oak", "log", "wood" },
  { "mangrove", "Mangrove", "log", "wood" }, { "cherry", "Cherry", "log", "wood" },
  { "crimson", "Crimson", "stem", "hyphae", true }, { "warped", "Warped", "stem", "hyphae", true },
}

Tags = {
  planks = {}, logs = {}, wooden_slabs = {},
  coals = list({ "coal", "charcoal" }),
  stone_tool_materials = list({ "cobblestone", "blackstone", "cobbled_deepslate" }),
  stone_crafting_materials = list({ "cobblestone", "blackstone", "cobbled_deepslate" }),
  soul_fire_base_blocks = list({ "soul_sand", "soul_soil" }),
  wool = {},
}
for _, w in ipairs(Woods) do
  local id, log, wood = w[1], w[3], w[4]
  local logs = list({ id .. "_" .. log, id .. "_" .. wood, "stripped_" .. id .. "_" .. log, "stripped_" .. id .. "_" .. wood })
  Tags[id .. "_logs"] = logs
  table.insert(Tags.planks, mc(id .. "_planks"))
  table.insert(Tags.wooden_slabs, mc(id .. "_slab"))
  if not w[5] then for _, l in ipairs(logs) do table.insert(Tags.logs, l) end end
end
for _, c in ipairs({ "white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray",
                     "light_gray", "cyan", "purple", "blue", "brown", "green", "red", "black" }) do
  table.insert(Tags.wool, mc(c .. "_wool"))
end

-- Tag names for people: "#planks" -> "Any planks".
TagNames = {
  planks = "Any planks", logs = "Any logs", wooden_slabs = "Any wooden slab", coals = "Coal or charcoal",
  stone_tool_materials = "Cobblestone (any)", stone_crafting_materials = "Cobblestone (any)",
  soul_fire_base_blocks = "Soul sand or soil", wool = "Any wool",
}

function tagName(key)
  local tag = key:sub(2)
  if TagNames[tag] then return TagNames[tag] end
  local wood = tag:match("^(.+)_logs$")
  if wood then
    for _, w in ipairs(Woods) do
      if w[1] == wood then return w[2] .. " " .. (w[5] and "stems" or "logs") .. " (any)" end
    end
  end
  return tag:gsub("_", " ")
end

Recipes = {}

-- Add a recipe: its name, what it makes and how many, the rows and
-- what the letters are. display is the item's name when it is not the
-- recipe's ("Iron Ingot" for "Iron Ingot (from nuggets)").
function add(name, out, count, rows, key, display)
  local grid, r = {}, 0
  for row in (rows .. "/"):gmatch("([^/]*)/") do
    for c = 1, #row do
      local ch = row:sub(c, c)
      if ch ~= "." and ch ~= " " then
        local item = key[ch]
        if not item then error("recipe " .. name .. ": no item for " .. ch, 2) end
        grid[r * 3 + c] = mc(item)
      end
    end
    r = r + 1
  end
  local recipe = {
    name = name, grid = grid, builtin = true,
    output = { name = mc(out), count = count, displayName = display or name },
  }
  Recipes[#Recipes + 1] = recipe
  return recipe
end

-- Wood
for _, w in ipairs(Woods) do
  local id, Name = w[1], w[2]
  local P = { P = id .. "_planks", S = "stick" }
  add(Name .. " Planks", id .. "_planks", 4, "L", { L = "#" .. id .. "_logs" })
  add(Name .. " " .. (w[4] == "wood" and "Wood" or "Hyphae"), id .. "_" .. w[4], 3, "LL/LL", { L = id .. "_" .. w[3] })
  add(Name .. " Slab", id .. "_slab", 6, "PPP", P)
  add(Name .. " Stairs", id .. "_stairs", 4, "P../PP./PPP", P)
  add(Name .. " Fence", id .. "_fence", 3, "PSP/PSP", P)
  add(Name .. " Fence Gate", id .. "_fence_gate", 1, "SPS/SPS", P)
  add(Name .. " Door", id .. "_door", 3, "PP/PP/PP", P)
  add(Name .. " Trapdoor", id .. "_trapdoor", 2, "PPP/PPP", P)
  add(Name .. " Sign", id .. "_sign", 3, "PPP/PPP/.S.", P)
  add(Name .. " Hanging Sign", id .. "_hanging_sign", 6, "C.C/LLL/LLL",
      { C = "chain", L = "stripped_" .. id .. "_" .. w[3] })
  add(Name .. " Pressure Plate", id .. "_pressure_plate", 1, "PP", P)
  add(Name .. " Button", id .. "_button", 1, "P", P)
  if not w[5] then add(Name .. " Boat", id .. "_boat", 1, "P.P/PPP", P) end
end

local P = { P = "#planks", S = "stick", W = "#wooden_slabs" }
add("Stick", "stick", 4, "P/P", P)
add("Crafting Table", "crafting_table", 1, "PP/PP", P)
add("Chest", "chest", 1, "PPP/P.P/PPP", P)
add("Barrel", "barrel", 1, "PWP/P.P/PWP", P)
add("Bowl", "bowl", 4, "P.P/.P.", P)
add("Ladder", "ladder", 3, "S.S/SSS/S.S", P)
add("Bookshelf", "bookshelf", 1, "PPP/BBB/PPP", { P = "#planks", B = "book" })
add("Composter", "composter", 1, "W.W/W.W/WWW", P)
add("Note Block", "note_block", 1, "PPP/PRP/PPP", { P = "#planks", R = "redstone" })
add("Jukebox", "jukebox", 1, "PPP/PDP/PPP", { P = "#planks", D = "diamond" })
add("Shield", "shield", 1, "PIP/PPP/.P.", { P = "#planks", I = "iron_ingot" })
add("Tripwire Hook", "tripwire_hook", 2, "I/S/P", { P = "#planks", S = "stick", I = "iron_ingot" })
add("Smithing Table", "smithing_table", 1, "II/PP/PP", { P = "#planks", I = "iron_ingot" })
add("Fletching Table", "fletching_table", 1, "FF/PP/PP", { P = "#planks", F = "flint" })
add("Cartography Table", "cartography_table", 1, "AA/PP/PP", { P = "#planks", A = "paper" })
add("Loom", "loom", 1, "SS/PP", { P = "#planks", S = "string" })
add("Lectern", "lectern", 1, "WWW/.B./.W.", { W = "#wooden_slabs", B = "bookshelf" })
add("Grindstone", "grindstone", 1, "SLS/P.P", { P = "#planks", S = "stick", L = "stone_slab" })
add("Item Frame", "item_frame", 1, "SSS/SLS/SSS", { S = "stick", L = "leather" })
add("Painting", "painting", 1, "SSS/SWS/SSS", { S = "stick", W = "#wool" })
add("Armor Stand", "armor_stand", 1, "SSS/.S./SLS", { S = "stick", L = "smooth_stone_slab" })
add("Campfire", "campfire", 1, ".S./SCS/LLL", { S = "stick", C = "#coals", L = "#logs" })
add("White Bed", "white_bed", 1, "WWW/PPP", { P = "#planks", W = "white_wool" })
add("Daylight Detector", "daylight_detector", 1, "GGG/QQQ/WWW", { G = "glass", Q = "quartz", W = "#wooden_slabs" })
add("Piston", "piston", 1, "PPP/CIC/CRC", { P = "#planks", C = "cobblestone", I = "iron_ingot", R = "redstone" })
add("Sticky Piston", "sticky_piston", 1, "S/P", { S = "slime_ball", P = "piston" })

-- Tools and armour
local materials = {
  { "Wooden", "wooden", "#planks" }, { "Stone", "stone", "#stone_tool_materials" },
  { "Iron", "iron", "iron_ingot" }, { "Golden", "golden", "gold_ingot" }, { "Diamond", "diamond", "diamond" },
}
for _, m in ipairs(materials) do
  local key = { M = m[3], S = "stick" }
  add(m[1] .. " Pickaxe", m[2] .. "_pickaxe", 1, "MMM/.S./.S.", key)
  add(m[1] .. " Axe", m[2] .. "_axe", 1, "MM/MS/.S", key)
  add(m[1] .. " Shovel", m[2] .. "_shovel", 1, "M/S/S", key)
  add(m[1] .. " Hoe", m[2] .. "_hoe", 1, "MM/.S/.S", key)
  add(m[1] .. " Sword", m[2] .. "_sword", 1, "M/M/S", key)
end
local armour = {
  { "leather", "leather", { "Leather Cap", "Leather Tunic", "Leather Pants", "Leather Boots" } },
  { "iron", "iron_ingot", { "Iron Helmet", "Iron Chestplate", "Iron Leggings", "Iron Boots" } },
  { "golden", "gold_ingot", { "Golden Helmet", "Golden Chestplate", "Golden Leggings", "Golden Boots" } },
  { "diamond", "diamond", { "Diamond Helmet", "Diamond Chestplate", "Diamond Leggings", "Diamond Boots" } },
}
for _, a in ipairs(armour) do
  local key = { M = a[2] }
  add(a[3][1], a[1] .. "_helmet", 1, "MMM/M.M", key)
  add(a[3][2], a[1] .. "_chestplate", 1, "M.M/MMM/MMM", key)
  add(a[3][3], a[1] .. "_leggings", 1, "MMM/M.M/M.M", key)
  add(a[3][4], a[1] .. "_boots", 1, "M.M/M.M", key)
end
add("Bow", "bow", 1, ".ST/S.T/.ST", { S = "stick", T = "string" })
add("Arrow", "arrow", 4, "F/S/E", { F = "flint", S = "stick", E = "feather" })
add("Crossbow", "crossbow", 1, "SIS/THT/.S.", { S = "stick", I = "iron_ingot", T = "string", H = "tripwire_hook" })
add("Fishing Rod", "fishing_rod", 1, "..S/.ST/S.T", { S = "stick", T = "string" })
add("Shears", "shears", 1, ".I/I.", { I = "iron_ingot" })
add("Flint and Steel", "flint_and_steel", 1, "IF", { I = "iron_ingot", F = "flint" })
add("Bucket", "bucket", 1, "I.I/.I.", { I = "iron_ingot" })
add("Compass", "compass", 1, ".I./IRI/.I.", { I = "iron_ingot", R = "redstone" })
add("Clock", "clock", 1, ".G./GRG/.G.", { G = "gold_ingot", R = "redstone" })

-- Stone
local C = { C = "cobblestone" }
local S = { S = "stone" }
add("Furnace", "furnace", 1, "CCC/C.C/CCC", { C = "#stone_crafting_materials" })
add("Cobblestone Slab", "cobblestone_slab", 6, "CCC", C)
add("Cobblestone Stairs", "cobblestone_stairs", 4, "C../CC./CCC", C)
add("Cobblestone Wall", "cobblestone_wall", 6, "CCC/CCC", C)
add("Stone Slab", "stone_slab", 6, "SSS", S)
add("Stone Stairs", "stone_stairs", 4, "S../SS./SSS", S)
add("Stone Bricks", "stone_bricks", 4, "SS/SS", S)
add("Stone Brick Slab", "stone_brick_slab", 6, "BBB", { B = "stone_bricks" })
add("Stone Brick Stairs", "stone_brick_stairs", 4, "B../BB./BBB", { B = "stone_bricks" })
add("Stone Brick Wall", "stone_brick_wall", 6, "BBB/BBB", { B = "stone_bricks" })
add("Smooth Stone Slab", "smooth_stone_slab", 6, "SSS", { S = "smooth_stone" })
add("Stone Pressure Plate", "stone_pressure_plate", 1, "SS", S)
add("Stone Button", "stone_button", 1, "S", S)
add("Lever", "lever", 1, "S/C", { S = "stick", C = "cobblestone" })
add("Stonecutter", "stonecutter", 1, ".I./SSS", { I = "iron_ingot", S = "stone" })
add("Smoker", "smoker", 1, ".L./LFL/.L.", { L = "#logs", F = "furnace" })
add("Blast Furnace", "blast_furnace", 1, "III/IFI/SSS", { I = "iron_ingot", F = "furnace", S = "smooth_stone" })
add("Brewing Stand", "brewing_stand", 1, ".B./CCC", { B = "blaze_rod", C = "#stone_crafting_materials" })
add("Polished Andesite", "polished_andesite", 4, "SS/SS", { S = "andesite" })
add("Polished Diorite", "polished_diorite", 4, "SS/SS", { S = "diorite" })
add("Polished Granite", "polished_granite", 4, "SS/SS", { S = "granite" })
add("Bricks", "bricks", 1, "BB/BB", { B = "brick" })
add("Brick Slab", "brick_slab", 6, "BBB", { B = "bricks" })
add("Brick Stairs", "brick_stairs", 4, "B../BB./BBB", { B = "bricks" })
add("Brick Wall", "brick_wall", 6, "BBB/BBB", { B = "bricks" })
add("Flower Pot", "flower_pot", 1, "B.B/.B.", { B = "brick" })
add("Sandstone", "sandstone", 1, "SS/SS", { S = "sand" })
add("Quartz Block", "quartz_block", 1, "QQ/QQ", { Q = "quartz" })
add("Dispenser", "dispenser", 1, "CCC/CBC/CRC", { C = "cobblestone", B = "bow", R = "redstone" })
add("Dropper", "dropper", 1, "CCC/C.C/CRC", { C = "cobblestone", R = "redstone" })
add("Observer", "observer", 1, "CCC/RRQ/CCC", { C = "cobblestone", R = "redstone", Q = "quartz" })

-- Iron and gold things
local I = { I = "iron_ingot" }
add("Iron Bars", "iron_bars", 16, "III/III", I)
add("Iron Door", "iron_door", 3, "II/II/II", I)
add("Iron Trapdoor", "iron_trapdoor", 1, "II/II", I)
add("Heavy Weighted Pressure Plate", "heavy_weighted_pressure_plate", 1, "II", I)
add("Light Weighted Pressure Plate", "light_weighted_pressure_plate", 1, "GG", { G = "gold_ingot" })
add("Chain", "chain", 1, "N/I/N", { N = "iron_nugget", I = "iron_ingot" })
add("Lantern", "lantern", 1, "NNN/NTN/NNN", { N = "iron_nugget", T = "torch" })
add("Soul Lantern", "soul_lantern", 1, "NNN/NTN/NNN", { N = "iron_nugget", T = "soul_torch" })
add("Cauldron", "cauldron", 1, "I.I/I.I/III", I)
add("Hopper", "hopper", 1, "I.I/ICI/.I.", { I = "iron_ingot", C = "chest" })
add("Anvil", "anvil", 1, "BBB/.I./III", { B = "iron_block", I = "iron_ingot" })
add("Minecart", "minecart", 1, "I.I/III", I)
add("Minecart with Chest", "chest_minecart", 1, "C/M", { C = "chest", M = "minecart" })
add("Minecart with Furnace", "furnace_minecart", 1, "F/M", { F = "furnace", M = "minecart" })
add("Minecart with Hopper", "hopper_minecart", 1, "H/M", { H = "hopper", M = "minecart" })
add("Minecart with TNT", "tnt_minecart", 1, "T/M", { T = "tnt", M = "minecart" })
add("Rail", "rail", 16, "I.I/ISI/I.I", { I = "iron_ingot", S = "stick" })
add("Powered Rail", "powered_rail", 6, "G.G/GSG/GRG", { G = "gold_ingot", S = "stick", R = "redstone" })
add("Detector Rail", "detector_rail", 6, "I.I/IPI/IRI", { I = "iron_ingot", P = "stone_pressure_plate", R = "redstone" })
add("Activator Rail", "activator_rail", 6, "ISI/ITI/ISI", { I = "iron_ingot", S = "stick", T = "redstone_torch" })

-- Storage blocks and back
local blocks = {
  { "Iron", "iron_block", "iron_ingot", "Iron Ingot", "iron_nugget", "Iron Nugget" },
  { "Gold", "gold_block", "gold_ingot", "Gold Ingot", "gold_nugget", "Gold Nugget" },
  { "Copper", "copper_block", "copper_ingot", "Copper Ingot" },
  { "Diamond", "diamond_block", "diamond", "Diamond" },
  { "Emerald", "emerald_block", "emerald", "Emerald" },
  { "Lapis Lazuli", "lapis_block", "lapis_lazuli", "Lapis Lazuli" },
  { "Redstone", "redstone_block", "redstone", "Redstone Dust" },
  { "Coal", "coal_block", "coal", "Coal" },
  { "Raw Iron", "raw_iron_block", "raw_iron", "Raw Iron" },
  { "Raw Gold", "raw_gold_block", "raw_gold", "Raw Gold" },
  { "Raw Copper", "raw_copper_block", "raw_copper", "Raw Copper" },
}
for _, b in ipairs(blocks) do
  add("Block of " .. b[1], b[2], 1, "MMM/MMM/MMM", { M = b[3] })
  add(b[4], b[3], 9, "B", { B = b[2] })
  if b[5] then
    add(b[6], b[5], 9, "I", { I = b[3] })
    add(b[4] .. " (from nuggets)", b[3], 1, "NNN/NNN/NNN", { N = b[5] }, b[4])
  end
end
add("Slime Block", "slime_block", 1, "SSS/SSS/SSS", { S = "slime_ball" })
add("Slimeball", "slime_ball", 9, "S", { S = "slime_block" })
add("Hay Bale", "hay_block", 1, "WWW/WWW/WWW", { W = "wheat" })
add("Wheat", "wheat", 9, "H", { H = "hay_block" })
add("Bone Block", "bone_block", 1, "BBB/BBB/BBB", { B = "bone_meal" })
add("Bone Meal", "bone_meal", 3, "B", { B = "bone" })
add("Bone Meal (from block)", "bone_meal", 9, "B", { B = "bone_block" }, "Bone Meal")
add("Melon", "melon", 1, "MMM/MMM/MMM", { M = "melon_slice" })

-- Redstone and light
add("Torch", "torch", 4, "C/S", { C = "#coals", S = "stick" })
add("Soul Torch", "soul_torch", 4, "C/S/O", { C = "#coals", S = "stick", O = "#soul_fire_base_blocks" })
add("Redstone Torch", "redstone_torch", 1, "R/S", { R = "redstone", S = "stick" })
add("Redstone Repeater", "repeater", 1, "TRT/SSS", { T = "redstone_torch", R = "redstone", S = "stone" })
add("Redstone Comparator", "comparator", 1, ".T./TQT/SSS", { T = "redstone_torch", Q = "quartz", S = "stone" })
add("Redstone Lamp", "redstone_lamp", 1, ".R./RGR/.R.", { R = "redstone", G = "glowstone" })
add("Glowstone", "glowstone", 1, "GG/GG", { G = "glowstone_dust" })
add("TNT", "tnt", 1, "GSG/SGS/GSG", { G = "gunpowder", S = "sand" })
add("Glass Pane", "glass_pane", 16, "GGG/GGG", { G = "glass" })
add("Glass Bottle", "glass_bottle", 3, "G.G/.G.", { G = "glass" })

-- Odds and ends
add("Paper", "paper", 3, "SSS", { S = "sugar_cane" })
add("Sugar", "sugar", 1, "S", { S = "sugar_cane" })
add("Book", "book", 1, "PPP/L", { P = "paper", L = "leather" })
add("White Wool", "white_wool", 1, "SS/SS", { S = "string" })
add("White Carpet", "white_carpet", 3, "WW", { W = "white_wool" })
add("Snow Block", "snow_block", 1, "SS/SS", { S = "snowball" })
add("Clay", "clay", 1, "CC/CC", { C = "clay_ball" })
add("Bread", "bread", 1, "WWW", { W = "wheat" })
add("Cookie", "cookie", 8, "WCW", { W = "wheat", C = "cocoa_beans" })
add("Pumpkin Pie", "pumpkin_pie", 1, "PSE", { P = "pumpkin", S = "sugar", E = "egg" })
add("Golden Apple", "golden_apple", 1, "GGG/GAG/GGG", { G = "gold_ingot", A = "apple" })
add("Golden Carrot", "golden_carrot", 1, "NNN/NCN/NNN", { N = "gold_nugget", C = "carrot" })
add("Blaze Powder", "blaze_powder", 2, "R", { R = "blaze_rod" })
add("Eye of Ender", "ender_eye", 1, "PB", { P = "ender_pearl", B = "blaze_powder" })
add("Ender Chest", "ender_chest", 1, "OOO/OEO/OOO", { O = "obsidian", E = "ender_eye" })
add("Enchanting Table", "enchanting_table", 1, ".B./DOD/OOO", { B = "book", D = "diamond", O = "obsidian" })
add("Scaffolding", "scaffolding", 6, "BSB/B.B/B.B", { B = "bamboo", S = "string" })

-- CC: Tweaked
local function cc(name) return "computercraft:" .. name end
add("Computer", cc("computer_normal"), 1, "SSS/SRS/SGS", { S = "stone", R = "redstone", G = "glass_pane" })
add("Advanced Computer", cc("computer_advanced"), 1, "SSS/SRS/SGS", { S = "gold_ingot", R = "redstone", G = "glass_pane" })
add("Turtle", cc("turtle_normal"), 1, "III/ICI/IHI", { I = "iron_ingot", C = cc("computer_normal"), H = "chest" })
add("Advanced Turtle", cc("turtle_advanced"), 1, "III/ICI/IHI", { I = "gold_ingot", C = cc("computer_advanced"), H = "chest" })
add("Pocket Computer", cc("pocket_computer_normal"), 1, "SSS/SAS/SGS", { S = "stone", A = "golden_apple", G = "glass_pane" })
add("Advanced Pocket Computer", cc("pocket_computer_advanced"), 1, "SSS/SAS/SGS", { S = "gold_ingot", A = "golden_apple", G = "glass_pane" })
add("Monitor", cc("monitor_normal"), 1, "SSS/SGS/SSS", { S = "stone", G = "glass_pane" })
add("Advanced Monitor", cc("monitor_advanced"), 4, "SSS/SGS/SSS", { S = "gold_ingot", G = "glass_pane" })
add("Wired Modem", cc("wired_modem"), 1, "SSS/SRS/SSS", { S = "stone", R = "redstone" })
add("Wired Modem (block)", cc("wired_modem_full"), 1, "M", { M = cc("wired_modem") })
add("Wired Modem (from block)", cc("wired_modem"), 1, "M", { M = cc("wired_modem_full") }, "Wired Modem")
add("Networking Cable", cc("cable"), 6, ".S./SRS/.S.", { S = "stone", R = "redstone" })
add("Wireless Modem", cc("wireless_modem_normal"), 1, "SSS/SES/SSS", { S = "stone", E = "ender_pearl" })
add("Ender Modem", cc("wireless_modem_advanced"), 1, "SSS/SES/SSS", { S = "gold_ingot", E = "ender_eye" })
add("Disk Drive", cc("disk_drive"), 1, "SSS/SRS/SRS", { S = "stone", R = "redstone" })
add("Speaker", cc("speaker"), 1, "SSS/SNS/SRS", { S = "stone", N = "note_block", R = "redstone" })

table.sort(Recipes, function(a, b) return a.name < b.name end)

-- The recipes to show: the saved ones in their order, then the
-- built-in ones whose names none of them have.
function merge(saved)
  local out, taken = {}, {}
  for _, r in ipairs(saved or {}) do
    out[#out + 1] = r
    taken[r.name:lower()] = true
  end
  for _, r in ipairs(Recipes) do
    if not taken[r.name:lower()] then out[#out + 1] = r end
  end
  return out
end
