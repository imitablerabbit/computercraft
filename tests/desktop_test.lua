--[[
Tests for the desktop's catalogue and settings, and for GUI state kept
per screen so programs in different tabs do not share dialogs.
--]]

local path = "/.desktop_test.cfg"

describe("desktop settings", function()
  it("opens the desktop and starts nothing by default", function()
    if fs.exists(path) then fs.delete(path) end
    local c = desktop.loadConfig(path)
    expect.equal(c.enabled, true)
    expect.same(c.autostart, {})
  end)

  it("keeps the apps to start at boot, each once", function()
    local c = desktop.loadConfig(path)
    desktop.setAutostart(c, "storage", true)
    desktop.setAutostart(c, "pager", true)
    desktop.setAutostart(c, "storage", true)
    expect.same(c.autostart, { "pager", "storage" })
    expect.truthy(desktop.isAutostart(c, "pager"))
    desktop.setAutostart(c, "pager", false)
    desktop.saveConfig(c, path)
    expect.same(desktop.loadConfig(path).autostart, { "storage" })
    fs.delete(path)
  end)

  it("does not start by itself in the simulator", function()
    expect.truthy(desktop.inSimulator())
    expect.falsy(desktop.startsAtBoot({ enabled = true, autostart = { "storage" } }))
  end)

  it("starts in the game when enabled on a colour screen or with autostart apps", function()
    testing.stub(_G, "_HOST", "ComputerCraft 1.109.2 (Minecraft 1.20.1)")
    expect.truthy(desktop.startsAtBoot({ enabled = true, autostart = {} }))
    expect.falsy(desktop.startsAtBoot({ enabled = false, autostart = {} }))
    expect.truthy(desktop.startsAtBoot({ enabled = false, autostart = { "crafter" } }))
  end)
end)

describe("applications menu", function()
  local function names(list)
    local out = {}
    for _, a in ipairs(list) do out[#out + 1] = a.name end
    return out
  end

  it("lists a category's apps that can run here", function()
    testing.stub(_G, "turtle", nil)
    expect.contains(names(desktop.list("Base")), "Storage")
    expect.falsy(table.concat(names(desktop.list("Turtles")), ","):find("Crafter"))
    expect.contains(names(desktop.list("Turtles")), "Dispatcher")
  end)

  it("shows turtle apps on a turtle and leaves out computer ones", function()
    testing.stub(_G, "turtle", testing.fakeTurtle())
    local list = names(desktop.list("Turtles"))
    expect.contains(list, "Crafter")
    expect.falsy(table.concat(list, ","):find("Dispatcher"))
  end)

  it("lists other programs by themselves under Programs", function()
    local dir = "/.desktop_test_programs"
    if fs.exists(dir) then fs.delete(dir) end
    for _, f in ipairs({ "storage.lua", "mytool.lua", "turtle/digger.lua", "notes.txt" }) do
      local h = fs.open(fs.combine(dir, f), "w"); h.write("-- x"); h.close()
    end
    testing.stub(_G, "turtle", nil)
    expect.same(names(desktop.otherPrograms(dir)), { "mytool" })
    testing.stub(_G, "turtle", testing.fakeTurtle())
    expect.same(names(desktop.otherPrograms(dir)), { "digger", "mytool" })
    fs.delete(dir)
  end)

  it("names a command by its app", function()
    expect.equal(desktop.nameOf("turtlecontrol"), "Turtle control")
    expect.equal(desktop.nameOf("stripmine 3 2 12"), "stripmine")
  end)
end)

describe("GUI state per screen", function()
  it("keeps a dialog's capture and overlay to its own screen", function()
    local a = guirootcontainer.GUIRootContainer.new(window.create(term.current(), 1, 1, 30, 10))
    local b = guirootcontainer.GUIRootContainer.new(window.create(term.current(), 1, 1, 30, 10))
    local d = guidialog.GUIDialog.new("Hi", "There", { { text = "OK" } })
    d:show(a)
    expect.equal(guicomponent.getCapture(a), d)
    expect.equal(guicomponent.getCapture(b), nil)
    expect.equal(#guicomponent.getOverlays(b), 0)
    expect.equal(#guicomponent.getOverlays(a), 1)
    d:close()
    expect.equal(guicomponent.getCapture(a), nil)
    expect.equal(#guicomponent.getOverlays(a), 0)
  end)
end)
