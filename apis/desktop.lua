--[[
The desktop's applications and settings (the program is
programs/desktop.lua).

Apps is the catalogue the applications menu shows, by category. An
app has a name, the command it runs, a line about it, and needs:
"turtle" for one that only works on a turtle, "computer" for one that
does not. Programs in /programs that the catalogue does not name are
listed under Programs by themselves, so a new program shows up
without being added here.

The settings are kept in /desktop.cfg:

  enabled    open the desktop when the computer starts (default true;
             it needs a colour screen)
  autostart  commands started when the computer starts, before the
             desktop: each in its own tab on an advanced computer, or
             only the first, in place of the desktop, on one without
             tabs (multishell)
--]]

ConfigFile = "/desktop.cfg"

-- Apps is every app in the catalogue; Programs the rest of /programs.
Categories = { "Apps", "Base", "Turtles", "Tools", "Programs" }

Apps = {
  { name = "Storage", command = "storage", category = "Base", about = "Chest network: find, deposit, sort and craft" },
  { name = "Storage remote", command = "storage remote", category = "Base", about = "The base storage from afar, to your own chest" },
  { name = "Doors", command = "doors", category = "Base", about = "Lights and doors on schedules and sensors" },
  { name = "Machines", command = "machines", category = "Base", about = "Energy, tanks and inventories" },
  { name = "Lift", command = "lift", category = "Base", about = "Elevator or train between stops" },
  { name = "Pager", command = "pager", category = "Base", about = "Every alert in the base" },
  { name = "Turtle control", command = "turtlecontrol", category = "Turtles", about = "Drive turtles running the turtle agent" },
  { name = "Dispatcher", command = "dispatcher", category = "Turtles", needs = "computer", about = "Queue jobs for the turtle fleet" },
  { name = "Depot", command = "depot", category = "Turtles", about = "Fuel and dump chests for turtles" },
  { name = "Turtle agent", command = "turtleagent", category = "Turtles", needs = "turtle", about = "Let turtle control drive this turtle" },
  { name = "Crafter", command = "crafter", category = "Turtles", needs = "turtle", about = "Craft for storage beside its crafting chest" },
  { name = "Inventory", command = "inventorygui", category = "Turtles", needs = "turtle", about = "This turtle's slots" },
  { name = "Where", command = "where", category = "Turtles", needs = "turtle", about = "Where this turtle is" },
  { name = "Shell", command = "shell", category = "Tools", about = "The CraftOS shell; exit comes back" },
  { name = "Lua", command = "lua", category = "Tools", about = "Lua prompt; exit() comes back" },
  { name = "Files", command = "files", category = "Tools", about = "Browse the computer's files" },
  { name = "Update", command = "update", category = "Tools", file = "/update.lua", about = "Fetch the latest programs" },
}

--[[
Settings
--]]

local function defaults()
  return { enabled = true, autostart = {} }
end

-- Read the settings, with defaults for anything missing.
function loadConfig(path)
  local config = defaults()
  path = path or ConfigFile
  if fs.exists(path) then
    local h = fs.open(path, "r")
    local data = h and textutils.unserialize(h.readAll() or "")
    if h then h.close() end
    if type(data) == "table" then
      for k, v in pairs(data) do config[k] = v end
    end
  end
  if type(config.autostart) ~= "table" then config.autostart = {} end
  return config
end

function saveConfig(config, path)
  local h = fs.open(path or ConfigFile, "w")
  if not h then return false end
  h.write(textutils.serialize(config))
  h.close()
  return true
end

function isAutostart(config, command)
  for _, c in ipairs(config.autostart) do
    if c == command then return true end
  end
  return false
end

-- Start command at boot or stop doing so. Returns whether it now starts.
function setAutostart(config, command, on)
  for i = #config.autostart, 1, -1 do
    if config.autostart[i] == command then table.remove(config.autostart, i) end
  end
  if on then table.insert(config.autostart, command) end
  return on and true or false
end

-- Is this the simulator? It boots each computer to its scenario's
-- command, so the desktop does not start there by itself.
function inSimulator()
  return type(_HOST) == "string" and _HOST:find("simulator", 1, true) ~= nil
end

-- Should startup hand over to "desktop boot"?
function startsAtBoot(config)
  config = config or loadConfig()
  if inSimulator() then return false end
  if #config.autostart > 0 then return true end
  return config.enabled ~= false and term.isColor()
end

--[[
The applications menu
--]]

-- Can this app run here? (a turtle, the file it needs)
function available(app)
  if app.needs == "turtle" and not turtle then return false end
  if app.needs == "computer" and turtle then return false end
  if app.file and not fs.exists(app.file) then return false end
  return true
end

-- Programs in dir (recursively) that are not in the catalogue, as
-- apps in the Programs category. The turtle folder only on turtles.
function otherPrograms(dir)
  dir = dir or "/programs"
  local known = { desktop = true }
  for _, app in ipairs(Apps) do known[app.command] = true end
  local out = {}
  local function walk(d)
    if not fs.isDir(d) then return end
    for _, name in ipairs(fs.list(d)) do
      local path = fs.combine(d, name)
      if fs.isDir(path) then
        if name ~= "turtle" or turtle then walk(path) end
      elseif name:match("%.lua$") then
        local command = name:gsub("%.lua$", "")
        if not known[command] then
          known[command] = true
          out[#out + 1] = { name = command, command = command, category = "Programs", about = "" }
        end
      end
    end
  end
  walk(dir)
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- The apps to show for a category, those that can run here: "Apps"
-- for the whole catalogue, "Programs" for the other programs.
function list(category)
  local out = {}
  for _, app in ipairs(Apps) do
    if available(app) and (category == "Apps" or category == app.category) then out[#out + 1] = app end
  end
  if category == "Programs" then
    for _, app in ipairs(otherPrograms()) do out[#out + 1] = app end
  end
  return out
end

-- A name for a command: its app's, or the command's first word.
function nameOf(command)
  for _, app in ipairs(Apps) do
    if app.command == command then return app.name end
  end
  return (tostring(command):match("^%S+") or tostring(command))
end
