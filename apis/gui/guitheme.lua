--[[
guitheme names the colours a GUI uses by what they are for (background,
text, accent, button, danger ...) and keeps a few sets of them, so a
program can switch its whole look at once.

Components take their default colours from the theme when they are
made. A colour set with setBackgroundColor (or any other setter) is
the program's own and is never touched by the theme. Until a program
chooses a theme with setTheme, plain components (containers, text,
buttons, inputs, the root container) keep the classic white look they
always had and the others (dropdowns, checkboxes, scroll panes,
progress bars ...) use the dark theme, so older programs look the same.

  guitheme.setTheme("light")   choose a theme for components made from now
  guitheme.apply(root)         recolour an existing tree and repaint it
  guitheme.color("danger")     one colour of the current theme

Roles: background, surface (lists, tracks, panels), text, muted (less
important text), border, header and headerText (title bars and table
headers), accent and accentText (dropdowns, selected tabs), button,
buttonText, buttonPress, field and fieldText (text inputs), highlight
and highlightText (selected rows), danger, dangerText, warn, ok, fill
(progress bars) and track (the empty part of bars and meters).

fit picks a monitor text scale for a screen size and says whether the
screen is compact (narrow, like a pocket computer), so one program can
lay itself out for a large monitor and a 26x20 pocket alike.
--]]

themes = {
  dark = {
    background = colors.black, surface = colors.gray, text = colors.white, muted = colors.lightGray,
    border = colors.gray, header = colors.gray, headerText = colors.yellow,
    accent = colors.blue, accentText = colors.white,
    button = colors.blue, buttonText = colors.white, buttonPress = colors.lightGray,
    field = colors.gray, fieldText = colors.white,
    highlight = colors.lightGray, highlightText = colors.black,
    danger = colors.red, dangerText = colors.white, warn = colors.orange, ok = colors.lime,
    fill = colors.green, track = colors.gray,
  },
  light = {
    background = colors.white, surface = colors.lightGray, text = colors.black, muted = colors.gray,
    border = colors.lightGray, header = colors.lightBlue, headerText = colors.black,
    accent = colors.blue, accentText = colors.white,
    button = colors.lightBlue, buttonText = colors.black, buttonPress = colors.gray,
    field = colors.lightGray, fieldText = colors.black,
    highlight = colors.lightBlue, highlightText = colors.black,
    danger = colors.red, dangerText = colors.white, warn = colors.orange, ok = colors.green,
    fill = colors.green, track = colors.lightGray,
  },
}

DefaultTheme = "dark"

local chosen = nil -- the theme picked with setTheme, nil until then

-- Add (or replace) a theme. Roles it leaves out come from dark.
function register(name, roles)
  themes[name] = roles
end

-- Choose the theme for components made from now on; apply recolours
-- existing ones. nil goes back to the start (classic plain components).
function setTheme(name)
  if name ~= nil and not themes[name] then error("unknown theme " .. tostring(name)) end
  chosen = name
end

-- The name of the theme in use.
function getTheme()
  return chosen or DefaultTheme
end

-- Has a program chosen a theme?
function isChosen()
  return chosen ~= nil
end

-- The names of the themes, sorted.
function names()
  local list = {}
  for name in pairs(themes) do list[#list + 1] = name end
  table.sort(list)
  return list
end

-- The colour for a role. classic is what a plain component used before
-- themes; it is used until a theme is chosen.
function color(role, classic)
  if not chosen and classic ~= nil then return classic end
  local theme = themes[chosen or DefaultTheme] or themes.dark
  return theme[role] or themes.dark[role] or classic or colors.white
end

-- Recolour a component tree for the current theme and repaint it.
function apply(component)
  if component then component:applyTheme() end
end

-- Choose a theme and apply it to a tree in one go.
function use(name, component)
  setTheme(name)
  apply(component)
end

--[[
Screen size
--]]

-- Narrow screens (pocket computers, turtles, small monitors) get the
-- compact layouts.
CompactWidth = 40
CompactHeight = 16

function isCompact(w, h)
  return w < CompactWidth or (h ~= nil and h < CompactHeight)
end

-- Pick the text scale for a display: the largest monitor scale (0.5 to
-- 5) that still gives at least minW x minH characters, or 0.5 when none
-- does. scale forces a scale instead. Screens that cannot scale (a
-- computer's own) are measured as they are. Returns a table
-- { scale, w, h, compact }.
function fit(display, minW, minH, scale)
  minW, minH = minW or 26, minH or 20
  if display.setTextScale then
    if scale then
      display.setTextScale(scale)
    else
      scale = 0.5
      for s = 5, 0.5, -0.5 do
        display.setTextScale(s)
        local w, h = display.getSize()
        if w >= minW and h >= minH then scale = s; break end
      end
      display.setTextScale(scale)
    end
  end
  local w, h = display.getSize()
  return { scale = scale or 1, w = w, h = h, compact = isCompact(w, h) }
end
