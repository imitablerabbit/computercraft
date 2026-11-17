--[[
Desktop is the screen a computer starts in: an applications menu over
the programs in this repo. Touch or click an app to open it. On an
advanced computer, turtle or pocket computer each app opens in its own
tab (multishell): the tab bar at the top switches between them and the
desktop, and an app's tab closes when it ends. Without tabs the app
takes over the screen and the desktop comes back when it ends.

The bar at the top picks a category (Apps for the whole catalogue,
Base, Turtles, Tools, Programs for the rest of /programs, and Running
for the open tabs) and shows the time. Along the
bottom: Run... types any command on the on-screen keyboard, Boot apps
switches to choosing the apps that start with the computer (touch them,
then Done), and Power reboots, shuts down or leaves the desktop for the
shell; the x at the top right leaves for the shell too. An app that
ends within a few seconds, or with an error, waits for a key so its
last words can be read. The catalogue and the settings are in
apis/desktop.lua; the settings are kept in /desktop.cfg.

startup.lua runs "desktop boot" once the APIs are loaded: it starts the
autostart apps, each in a background tab, then opens the desktop. On a
computer without tabs only the first autostart app runs, in place of
the desktop. The simulator does not start it by itself.

Usage: desktop                       open the desktop
       desktop boot                  start the autostart apps, then the desktop
       desktop on|off                open the desktop at startup or not
       desktop autostart [add|remove <command>]
       desktop run <command>         run a command, waiting for a key when it
                                     ends quickly or fails (each tab runs this)
--]]

local args = { ... }
local config = desktop.loadConfig()

local function tabs()
  return multishell ~= nil and shell.openTab ~= nil
end

-- Wait for a key, a click or a touch.
local function waitForAny()
  while true do
    local e = os.pullEvent()
    if e == "key" or e == "char" or e == "mouse_click" or e == "monitor_touch" then return end
  end
end

-- Run command on this screen. One that ends quickly (it printed its
-- usage or an answer) or with an error waits for a key first.
local function runCommand(command)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  local started = os.clock()
  local ok = shell.run(command)
  if not ok or os.clock() - started < 3 then
    if term.isColor() then term.setTextColor(colors.yellow) end
    print()
    print((ok and "" or "It stopped with an error. ") .. "Press a key to go on.")
    term.setTextColor(colors.white)
    waitForAny()
  end
end

-- Open command in a new tab, running through "desktop run". Returns
-- the tab's number.
local function openTab(command, focus)
  local id = shell.openTab("desktop", "run", table.unpack(basepanel.words(command)))
  if id then
    multishell.setTitle(id, desktop.nameOf(command))
    if focus then multishell.setFocus(id) end
  end
  return id
end

--[[
The menu
--]]

-- Show the menu until the person picks something that needs the screen
-- or it has to be built again. Returns { kind = "run", command },
-- { kind = "rebuild" }, or nil to leave the desktop.
local function showMenu(state)
  local w = term.getSize()
  local compact = w < 40
  local app = guiapplication.GUIApplication.new()
  local root, ids
  local result = nil
  local bootMode = false
  state.category = state.category or "Apps"

  local categories = {}
  for _, c in ipairs(desktop.Categories) do categories[#categories + 1] = c end
  if tabs() then categories[#categories + 1] = "Running" end

  local function status(text)
    ids.status:setText(text)
  end

  -- The open tabs other than this one, as apps.
  local function running()
    local out = {}
    local here = multishell.getCurrent()
    for i = 1, multishell.getCount() do
      if i ~= here then
        out[#out + 1] = { name = multishell.getTitle(i) or ("Tab " .. i), about = "tab " .. i, tab = i }
      end
    end
    return out
  end

  local function refresh()
    local apps = state.category == "Running" and running() or desktop.list(state.category)
    local rows = {}
    for i, a in ipairs(apps) do
      local boot = (a.command and desktop.isAutostart(config, a.command)) and "yes" or ""
      rows[i] = compact and { a.name, boot, app = a } or { a.name, a.about or "", boot, app = a }
    end
    ids.apps:setRows(rows)
    ids.apps:select(nil)
  end

  local function launch(a)
    if bootMode then
      if not a.command then return end
      local on = desktop.setAutostart(config, a.command, not desktop.isAutostart(config, a.command))
      desktop.saveConfig(config)
      refresh()
      return status(a.name .. (on and " starts with the computer." or " no longer starts with the computer."))
    end
    if a.tab then
      multishell.setFocus(a.tab)
      ids.apps:select(nil)
      return
    end
    if tabs() then
      openTab(a.command, true)
      status("Opened " .. a.name .. " in a tab.")
      refresh()
    else
      result = { kind = "run", command = a.command }
      app:stop()
    end
  end

  local function runPrompt()
    guikeyboard.open(root, "Run", "", function(text)
      text = text:gsub("^%s+", ""):gsub("%s+$", "")
      if text ~= "" then launch({ name = desktop.nameOf(text), command = text }) end
    end, { hint = function(text)
      local first = text:match("^%S+")
      if not first then return "Type the program to run" end
      return shell.resolveProgram(first) and ("Runs " .. first) or ("No program called " .. first)
    end })
  end

  local function power()
    guidialog.GUIDialog.new("Power", "Leave the desktop?", {
      { text = "Cancel" },
      { text = "Shell", onPress = function() app:stop() end },
      { text = "Reboot", onPress = function() os.reboot() end },
      { text = "Off", role = "danger", onPress = function() os.shutdown() end },
    }):show(root)
  end

  local columns = compact
    and { { title = "App", flex = 1 }, { title = "Boot", width = 4 } }
    or { { title = "App", width = 15 }, { title = "About", flex = 1 }, { title = "Boot", width = 4 } }
  local label = os.getComputerLabel() or ("Computer " .. os.getComputerID())

  root, ids = guibuild.build({
    type = "root", title = label, dir = "vertical", gap = 0, children = {
      { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
        { type = "dropdown", id = "category", options = categories, value = state.category, flex = 1, onSelect = function()
            state.category = ids.category:getValue()
            refresh()
          end },
        { type = "text", id = "clock", text = textutils.formatTime(os.time(), true), w = 8, align = "right" },
      } },
      { type = "table", id = "apps", flex = 1, striped = true, emptyText = "Nothing here.", columns = columns,
        onSelect = function(e) launch(e.row.app) end },
      { type = "box", dir = "horizontal", gap = 1, h = 1, children = {
        { type = "button", text = "Run...", flex = 1, onPress = runPrompt },
        { type = "button", id = "bootMode", text = "Boot apps", flex = 1, onPress = function()
            bootMode = not bootMode
            ids.bootMode:setText(bootMode and "Done" or "Boot apps")
            ids.bootMode:repaint()
            status(bootMode and "Touch the apps to start with the computer." or "Touch an app to open it.")
          end },
        { type = "button", text = "Power", flex = 1, onPress = power },
      } },
      { type = "text", id = "status", text = "Touch an app to open it.", h = 1, fgRole = "muted" },
    },
  })
  app:setRootContainer(root)
  app:setUPS(20)
  app:addEventListener(function(event)
    if event[1] == "term_resize" then
      result = { kind = "rebuild" }
      app:stop()
    end
  end)
  refresh()

  local function clock()
    while true do
      sleep(1)
      ids.clock:setText(textutils.formatTime(os.time(), true))
      ids.clock:repaint()
      if state.category == "Running" and not bootMode then refresh() end
    end
  end
  parallel.waitForAny(function() app:start() end, clock)
  return result
end

local function openDesktop()
  if not term.isColor() then
    print("The desktop needs a colour screen (an advanced computer, turtle or pocket computer).")
    return
  end
  local previousTheme = guitheme.isChosen() and guitheme.getTheme() or nil
  guitheme.setTheme("dark")
  if tabs() then multishell.setTitle(multishell.getCurrent(), "Desktop") end
  local state = {}
  while true do
    local action = showMenu(state)
    if not action then break end
    if action.kind == "run" then runCommand(action.command) end
  end
  guitheme.setTheme(previousTheme)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  print("Type desktop to open the desktop again.")
end

--[[
Commands
--]]

local cmd = args[1]
if cmd == nil then
  openDesktop()
elseif cmd == "boot" then
  local useTabs = tabs()
  for i, command in ipairs(config.autostart) do
    if useTabs then
      openTab(command, false)
    elseif i == 1 then
      runCommand(command)
    end
  end
  if config.enabled ~= false and term.isColor() then openDesktop() end
elseif cmd == "run" then
  if not args[2] then
    print("Usage: desktop run <command>")
    return
  end
  runCommand(table.concat(args, " ", 2))
elseif cmd == "on" or cmd == "off" then
  config.enabled = cmd == "on"
  desktop.saveConfig(config)
  print("The desktop " .. (config.enabled and "opens" or "no longer opens") .. " when the computer starts.")
elseif cmd == "autostart" then
  local sub = args[2]
  local command = table.concat(args, " ", 3)
  if (sub == "add" or sub == "remove") and command ~= "" then
    desktop.setAutostart(config, command, sub == "add")
    desktop.saveConfig(config)
  elseif sub ~= nil then
    print("Usage: desktop autostart [add|remove <command>]")
    return
  end
  if #config.autostart == 0 then
    print("Nothing starts with the computer.")
  else
    print("Started with the computer:")
    for _, c in ipairs(config.autostart) do print("  " .. c) end
  end
else
  print("Usage: desktop [boot|on|off]")
  print("       desktop autostart [add|remove <command>]")
  print("       desktop run <command>")
end
