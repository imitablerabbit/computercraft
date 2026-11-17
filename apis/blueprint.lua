--[==[
Blueprint reads, writes and counts the blueprint files that build puts
up and scan writes. A blueprint is plain text that can be written by
hand: a palette giving each character a block, then the layers from
the bottom up, each drawn as seen from above.

  --[[
  name Small hut
  # = minecraft:cobblestone
  = = minecraft:oak_planks
  . = air
  layer 1
  #####
  #...#
  #...#
  #...#
  ##.##
  layer 2
  ...
  ]]

Lines:
  `--[[` and `]]`   ignored, so the whole file can be a Lua comment
                    and be called hut.lua: the installers (github.lua
                    and serve.py) only copy .lua files, so blueprints
                    in the repo's blueprints/ folder reach every
                    computer that way.
  `-- text`         a comment, anywhere.
  `name <text>`     the blueprint's name (optional, before the layers).
  `<c> = <block>`   a palette entry, before the first layer: one
                    character, a space, =, a space and a block (item)
                    name, or `air` for a block that should be empty.
                    `.` is air unless the palette says otherwise.
                    A space is always "don't care": build leaves
                    whatever is there.
  `layer [text]`    starts the next layer up; anything after the word
                    is a note for the reader.
  rows              everything else inside a layer. The first row is
                    the back of the footprint and the last row the
                    front, columns run left to right, as seen by a
                    turtle standing in front of it looking in. Short
                    rows are padded with spaces. Every layer must have
                    the same number of rows.

Where the turtle starts (build and scan):

            back
        . . . . .     each layer, drawn as in the file
        . . . . .
        . . . . .
        # . . . .     front row (the last row of a layer)
        T             the turtle: on the block in front of the front
      left   right    row's left end, at the height of the first
                      layer, facing into the footprint

So the footprint is straight ahead and to the right of the turtle, and
the first layer is level with the turtle (it stands on the ground the
first layer sits on).

In code a blueprint is a table:
  { name, width, length, height,
    palette = { [char] = block name or "air" },
    layers = { { row, ... }, ... } }    bottom layer first, rows in file
                                        order (back to front), padded
Positions are x (column from the left, 0 based), y (layer from the
bottom, 0 based) and z (row from the front, 0 based: the front row is
0, the last row in the file).

API:
  blueprint.parse(text) -> bp or nil, error (with the line number)
  blueprint.serialize(bp) -> text (wrapped in --[[ ]])
  blueprint.load(path) -> bp or nil, error
  blueprint.save(path, bp) -> true or false, error
  blueprint.find(name) -> path or nil: name as given, name.lua, then
                          /blueprints/name and /blueprints/name.lua
  blueprint.new(width, length, height) -> an empty (all don't care) bp
  blueprint.at(bp, x, y, z) -> block name, "air", or nil (don't care)
  blueprint.set(bp, x, y, z, name) -> sets a block (nil for don't care),
                          picking a palette character for a new name
  blueprint.charFor(bp, name) -> the palette character for a name,
                          adding one when needed
  blueprint.materials(bp) -> { [name] = count } of blocks to place
  blueprint.missing(materials, have) -> sorted list of
                          { name, need, have, short } for what is short
--]==]

-- Characters picked for common blocks when a palette is made up
-- (scan), in this order; then the first letter of the block, upper
-- case, then whatever is left.
Defaults = {
  { "^minecraft:cobblestone$", "#" },
  { "_planks$", "=" },
  { "_log$", "o" }, { "_wood$", "o" },
  { "^minecraft:stone$", "s" },
  { "^minecraft:stone_bricks$", "B" },
  { "glass", "g" },
  { "^minecraft:dirt$", "d" },
  { "^minecraft:grass_block$", "G" },
  { "slab", "_" },
  { "stairs", "/" },
  { "fence", "|" },
  { "door", "D" },
  { "torch", "i" },
  { "ladder", "H" },
  { "wool", "w" },
}

-- Characters that can never be palette entries: space is don't care,
-- and ] and - would upset the Lua comment wrapper and comments.
local reserved = { [" "] = true, ["]"] = true, ["-"] = true, ["["] = true }
local spare = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@$%&*+!?<>^~;:,'\"`(){}\\"

function new(width, length, height)
  local bp = { width = width, length = length, height = height, palette = { ["."] = "air" }, layers = {} }
  for y = 1, height do
    local rows = {}
    for z = 1, length do rows[z] = string.rep(" ", width) end
    bp.layers[y] = rows
  end
  return bp
end

-- The palette character for a block name, adding one if it has none.
function charFor(bp, name)
  if name == nil then return " " end
  for c, n in pairs(bp.palette) do
    if n == name then return c end
  end
  local used = function(c) return reserved[c] or bp.palette[c] ~= nil end
  local pick
  for _, d in ipairs(Defaults) do
    if name:find(d[1]) and not used(d[2]) then pick = d[2] break end
  end
  if not pick then
    local base = name:match(":(.*)$") or name
    local first = base:sub(1, 1)
    for _, c in ipairs({ first:lower(), first:upper() }) do
      if c:match("%w") and not used(c) then pick = c break end
    end
  end
  if not pick then
    for i = 1, #spare do
      local c = spare:sub(i, i)
      if not used(c) then pick = c break end
    end
  end
  if not pick then error("no palette characters left for " .. name) end
  bp.palette[pick] = name
  return pick
end

local function rowIndex(bp, z) return bp.length - z end

function at(bp, x, y, z)
  local rows = bp.layers[y + 1]
  if not rows then return nil end
  local row = rows[rowIndex(bp, z)]
  if not row then return nil end
  local c = row:sub(x + 1, x + 1)
  if c == "" or c == " " then return nil end
  return bp.palette[c]
end

function set(bp, x, y, z, name)
  local c = charFor(bp, name)
  local rows = bp.layers[y + 1]
  local i = rowIndex(bp, z)
  local row = rows[i]
  rows[i] = row:sub(1, x) .. c .. row:sub(x + 2)
end

function parse(text)
  local bp = { palette = { ["."] = "air" }, layers = {} }
  local layer = nil
  local lineNo = 0
  local width = 0
  local rowLines = {} -- [layer][row] = line number, for errors
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    lineNo = lineNo + 1
    line = line:gsub("\r$", "")
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed:find("^%-%-") or trimmed:find("^%]=*%]$") then
      -- a comment or the Lua wrapper
    elseif trimmed:lower():find("^layer") and (#trimmed == 5 or trimmed:sub(6, 6) == " ") then
      layer = {}
      table.insert(bp.layers, layer)
      rowLines[#bp.layers] = {}
    elseif not layer then
      if trimmed == "" then
        -- blank lines before the layers are fine
      elseif trimmed:find("^name ") or trimmed == "name" then
        bp.name = trimmed:sub(6)
      else
        local c, name = line:match("^(%S) = (%S+)%s*$")
        if not c then
          return nil, "line " .. lineNo .. ": expected a palette entry like '# = minecraft:cobblestone', a name or a layer line"
        end
        if reserved[c] then return nil, "line " .. lineNo .. ": '" .. c .. "' cannot be a palette character" end
        bp.palette[c] = name
      end
    else
      local row = line:gsub("%s+$", "")
      -- Blank lines between layers are skipped; a blank row in the
      -- middle of a layer is all don't care, so write it as spaces.
      if row ~= "" or line ~= "" then
        for i = 1, #row do
          local c = row:sub(i, i)
          if c ~= " " and not bp.palette[c] then
            return nil, "line " .. lineNo .. ": '" .. c .. "' is not in the palette"
          end
        end
        table.insert(layer, row)
        table.insert(rowLines[#bp.layers], lineNo)
        if #row > width then width = #row end
      end
    end
  end
  if #bp.layers == 0 then return nil, "no layers (a layer starts with a line saying layer)" end
  local length = #bp.layers[1]
  for i, rows in ipairs(bp.layers) do
    if #rows ~= length then
      return nil, "layer " .. i .. " has " .. #rows .. " rows but layer 1 has " .. length
    end
  end
  if length == 0 or width == 0 then return nil, "the layers are empty" end
  for _, rows in ipairs(bp.layers) do
    for i, row in ipairs(rows) do rows[i] = row .. string.rep(" ", width - #row) end
  end
  bp.width, bp.length, bp.height = width, length, #bp.layers
  return bp
end

function serialize(bp)
  local lines = { "--[[" }
  if bp.name then lines[#lines + 1] = "name " .. bp.name end
  local chars = {}
  for c in pairs(bp.palette) do chars[#chars + 1] = c end
  table.sort(chars)
  for _, c in ipairs(chars) do lines[#lines + 1] = c .. " = " .. bp.palette[c] end
  for i, rows in ipairs(bp.layers) do
    lines[#lines + 1] = "layer " .. i
    for _, row in ipairs(rows) do
      -- Trailing don't cares are dropped, but a row of nothing but
      -- spaces keeps one so it still counts as a row.
      local r = row:gsub("%s+$", "")
      if r == "" then r = " " end
      lines[#lines + 1] = r
    end
  end
  lines[#lines + 1] = "]]"
  return table.concat(lines, "\n") .. "\n"
end

function load(path)
  if not fs.exists(path) or fs.isDir(path) then return nil, "no blueprint file " .. path end
  local f = fs.open(path, "r")
  if not f then return nil, "cannot read " .. path end
  local text = f.readAll()
  f.close()
  local bp, err = parse(text)
  if not bp then return nil, path .. ": " .. err end
  return bp
end

function save(path, bp)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(path, "w")
  if not f then return false, "cannot write " .. path end
  f.write(serialize(bp))
  f.close()
  return true
end

function find(name)
  local candidates = { name, name .. ".lua", "/blueprints/" .. name, "/blueprints/" .. name .. ".lua" }
  if shell and shell.resolve then
    table.insert(candidates, 1, shell.resolve(name))
  end
  for _, path in ipairs(candidates) do
    if fs.exists(path) and not fs.isDir(path) then return path end
  end
  return nil
end

function materials(bp)
  local counts = {}
  for y = 0, bp.height - 1 do
    for z = 0, bp.length - 1 do
      for x = 0, bp.width - 1 do
        local name = at(bp, x, y, z)
        if name and name ~= "air" then counts[name] = (counts[name] or 0) + 1 end
      end
    end
  end
  return counts
end

function missing(mats, have)
  local list = {}
  for name, need in pairs(mats) do
    local got = (have and have[name]) or 0
    if got < need then
      list[#list + 1] = { name = name, need = need, have = got, short = need - got }
    end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end
