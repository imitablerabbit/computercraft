--[[
guibuild makes a component tree from a nested table that describes it,
instead of creating, sizing and adding every component by hand:

  local root, ids = guibuild.build({
    type = "root", title = "Settings", dir = "vertical", gap = 1,
    children = {
      { type = "text", text = "Hi", id = "title" },
      { type = "box", dir = "horizontal", gap = 1, h = 3, children = {
        { type = "button", text = "Go", flex = 1, onPress = go },
        { type = "button", text = "Quit", w = 8, onPress = quit },
      } },
    },
  })
  ids.title:setText("Hello")

build returns the top component and a table of every component that
was given an id. Containers ("box", "grid", "root", "scroll", "tabs")
lay out their children; the rest are leaves.

Every spec may give:
  id            name in the returned ids table
  w, h          preferred size (otherwise worked out from the content)
  x, y          position, for a component in a container without a layout
  flex          share of spare space along the parent box's axis
  stretch       false to keep the preferred size across the axis
  border        true or false
  bg, fg        background and text colour (otherwise the theme's)
  bgRole, fgRole  the same as theme roles ("muted", "danger" ...), so
                they change with the theme
  borderColor
  visible       false to start hidden
  init          function(component) called once it is made

Types and their own fields:
  root       a GUIRootContainer: title, decorations, term, side; its
             children go in a box under the title bar (dir, gap, padding)
  box        a container stacking children: dir ("vertical" or
             "horizontal"), gap, padding
  panel      a container without a layout; children use x, y
  grid       rows, columns, gap, padding
  scroll     a GUIScrollPane around one child (or a vertical box of
             all the children)
  tabs       a GUITabs; each child is a tab with a title; onChange
  text       text, align, valign
  button     text, onPress, pressColor
  input      text, onDone, keyboard ("touch", "always" or false: when
             an on-screen keyboard opens), keyboardTitle, keyboardHint
  checkbox   text, checked, onChange
  dropdown   options, selected (index) or value, onSelect
  progress   value, max, label, showPercent, warnBelow, fill, empty
  gauge      min, max, value, label, dir, warnBelow, format, fill
  sparkline  capacity, samples, min, max, showRange, fill
  table      columns, rows, striped, emptyText, onSelect
  turtleicon info, onSelect
  inventory  items, selected, onSelect
  dialog     title, message, buttons: made but not added or shown, use
             ids.name:show(root) to open it

register(type, fn) adds a type: fn(spec) returns the new component.
--]]

local makers = {}

function register(typeName, fn)
  makers[typeName] = fn
end

-- The preferred size of a leaf when the spec gives none.
local function defaultSize(spec, c)
  local w, h = spec.w, spec.h
  local pw, ph = c.prefW, c.prefH
  if spec.type == "text" then pw, ph = #tostring(spec.text or ""), 1
  elseif spec.type == "button" then pw, ph = #tostring(spec.text or "") + 2, (spec.border and 3 or 1)
  elseif spec.type == "input" then pw, ph = math.max(10, #tostring(spec.text or "") + 2), (spec.border == false and 1 or 3)
  elseif spec.type == "checkbox" then pw, ph = #tostring(spec.text or "") + 4, 1
  elseif spec.type == "dropdown" then
    local longest = 0
    for i, o in ipairs(spec.options or {}) do longest = math.max(longest, #tostring(o)) end
    pw, ph = longest + 3, 1
  elseif spec.type == "turtleicon" then pw, ph = guiturtleicon.GUITurtleIcon.MinWidth, guiturtleicon.GUITurtleIcon.MinHeight
  end
  return w or pw, h or ph
end

local function boxLayout(spec)
  return guilayout.GUIBoxLayout.new(spec.dir or spec.axis or "vertical", spec.gap or 0, spec.padding or 0)
end

local function container(spec)
  local c = guicomponent.GUIComponent.new()
  c:setBorder(false)
  return c
end

makers.box = function(spec)
  local c = container(spec)
  c:setLayout(boxLayout(spec))
  return c
end
makers.vbox = function(spec) spec.dir = spec.dir or "vertical"; return makers.box(spec) end
makers.hbox = function(spec) spec.dir = spec.dir or "horizontal"; return makers.box(spec) end
makers.panel = container
makers.grid = function(spec)
  local c = container(spec)
  c:setLayout(guilayout.GUIGridLayout.new(spec.rows, spec.columns, spec.gap or 0, spec.padding or 0))
  return c
end
makers.scroll = function(spec) return guiscrollpane.GUIScrollPane.new() end
makers.tabs = function(spec)
  local c = guitabs.GUITabs.new()
  if spec.onChange then c:addChangeListener(spec.onChange) end
  return c
end
makers.text = function(spec)
  local c = guitext.GUIText.new(tostring(spec.text or ""))
  c:setBorder(false)
  if spec.align then c:setTextAlign(spec.align) end
  if spec.valign then c:setTextVerticalAlign(spec.valign) end
  return c
end
makers.label = makers.text
makers.button = function(spec)
  local c = guibutton.GUIButton.new(tostring(spec.text or ""))
  c:setBorder(spec.border and true or false)
  if spec.onPress then c:addButtonListener(spec.onPress) end
  if spec.pressColor then c.pressColor = spec.pressColor end
  return c
end
makers.input = function(spec)
  local c = guiinput.GUIInput.new(tostring(spec.text or ""))
  if spec.onDone then c:addDoneListener(spec.onDone) end
  if spec.keyboard ~= nil or spec.keyboardTitle or spec.keyboardHint then
    c:setKeyboard(spec.keyboard == nil and "touch" or spec.keyboard, spec.keyboardTitle, spec.keyboardHint)
  end
  return c
end
makers.checkbox = function(spec)
  local c = guicheckbox.GUICheckbox.new(spec.text, spec.checked)
  if spec.onChange then c:addChangeListener(spec.onChange) end
  return c
end
makers.dropdown = function(spec)
  local c = guidropdown.GUIDropdown.new(spec.options or {}, spec.selected)
  if spec.value ~= nil then c:setValue(spec.value) end
  if spec.onSelect then c:addSelectListener(spec.onSelect) end
  return c
end
makers.progress = function(spec)
  local c = guiprogressbar.GUIProgressBar.new(spec.value, spec.max)
  if spec.label then c:setLabel(spec.label) end
  if spec.showPercent then c:setShowPercent(true) end
  if spec.warnBelow then c:setWarnBelow(spec.warnBelow, spec.warnColor) end
  if spec.fill then c:setFillColor(spec.fill) end
  if spec.empty then c:setEmptyColor(spec.empty) end
  return c
end
makers.gauge = function(spec)
  local c = guigauge.GUIGauge.new(spec.min, spec.max, spec.value)
  if spec.dir then c:setOrientation(spec.dir) end
  if spec.label then c:setLabel(spec.label) end
  if spec.warnBelow then c:setWarnBelow(spec.warnBelow, spec.warnColor) end
  if spec.format then c:setFormat(spec.format) end
  if spec.fill then c:setFillColor(spec.fill) end
  return c
end
makers.sparkline = function(spec)
  local c = guisparkline.GUISparkline.new(spec.capacity)
  if spec.samples then c:setSamples(spec.samples) end
  if spec.min or spec.max then c:setRange(spec.min, spec.max) end
  if spec.showRange then c:setShowRange(true) end
  if spec.fill then c:setFillColor(spec.fill) end
  return c
end
makers.table = function(spec)
  local c = guitable.GUITable.new(spec.columns or {})
  if spec.rows then c:setRows(spec.rows) end
  if spec.striped then c:setStriped(true) end
  if spec.emptyText then c:setEmptyText(spec.emptyText) end
  if spec.onSelect then c:addSelectListener(spec.onSelect) end
  return c
end
makers.turtleicon = function(spec)
  local c = guiturtleicon.GUITurtleIcon.new(spec.info)
  if spec.onSelect then c:addSelectListener(spec.onSelect) end
  return c
end
makers.inventory = function(spec)
  local c = guiinventorygrid.GUIInventoryGrid.new(spec.items, spec.selected)
  if spec.onSelect then c:addSelectListener(spec.onSelect) end
  return c
end
makers.dialog = function(spec)
  return guidialog.GUIDialog.new(spec.title, spec.message, spec.buttons)
end

-- Colours, border, flex and the rest every type shares.
local function common(spec, c)
  if spec.border ~= nil and spec.type ~= "button" then c:setBorder(spec.border) end
  if spec.bg then c:setBackgroundColor(spec.bg) end
  if spec.fg then c:setTextColor(spec.fg) end
  if spec.borderColor then c:setBorderColor(spec.borderColor) end
  if spec.bgRole then c:themed("backgroundColor", spec.bgRole) end
  if spec.fgRole then c:themed("textColor", spec.fgRole) end
  if spec.flex then c:setFlex(spec.flex) end
  if spec.stretch ~= nil then c:setStretch(spec.stretch) end
end

local containers = { box = true, vbox = true, hbox = true, panel = true, grid = true, scroll = true, tabs = true }

local buildSpec

-- Add the children of a container spec to c.
local function addChildren(spec, c, ids)
  local children = spec.children or {}
  if spec.type == "scroll" then
    local content
    if #children == 1 then
      content = buildSpec(children[1], ids)
    else
      content = makers.box({ dir = "vertical" })
      content:setBackgroundColor(c.backgroundColor)
      for i, child in ipairs(children) do content:add(buildSpec(child, ids)) end
    end
    c:setContent(content)
  elseif spec.type == "tabs" then
    for i, child in ipairs(children) do
      c:addTab(child.title or ("Tab " .. i), buildSpec(child, ids))
    end
    if spec.selected then c:select(spec.selected, false) end
  else
    for i, child in ipairs(children) do c:add(buildSpec(child, ids)) end
  end
end

buildSpec = function(spec, ids)
  if spec.component then
    -- an existing component dropped into the tree
    local c = spec.component
    common(spec, c)
    if spec.id then ids[spec.id] = c end
    return c
  end
  local make = makers[spec.type]
  if not make then error("guibuild: unknown type " .. tostring(spec.type)) end
  local c = make(spec)
  common(spec, c)
  if containers[spec.type] then
    if spec.w or spec.h then
      local pw, ph = c:getPreferredSize()
      c:setPreferredBounds(spec.x or 1, spec.y or 1, spec.w or pw, spec.h or ph)
    elseif spec.x or spec.y then
      c.x, c.y = spec.x or 1, spec.y or 1
    end
    addChildren(spec, c, ids)
  elseif spec.type ~= "dialog" then
    local w, h = defaultSize(spec, c)
    c:setPreferredBounds(spec.x or 1, spec.y or 1, math.max(1, w), math.max(1, h))
  end
  if spec.visible == false then c:setVisible(false) end
  if spec.id then ids[spec.id] = c end
  if spec.init then spec.init(c) end
  return c
end

-- Build a tree. A "root" spec makes a GUIRootContainer filling the
-- screen with its children in a box under the title bar (ids.page is
-- that box unless the spec names it with pageId). Anything else is
-- made to fill the screen (or its own x, y, w, h). Returns the top
-- component and the ids table.
function build(spec, ids)
  ids = ids or {}
  if spec.type == "root" then
    local root = guirootcontainer.GUIRootContainer.new(spec.term, spec.side)
    root:setTitle(spec.title or "")
    if spec.decorations ~= nil then root:setDecorations(spec.decorations) end
    if spec.bg then root:setBackgroundColor(spec.bg) end
    if spec.fg then root:setTextColor(spec.fg) end
    local top = (root:hasDecorations() or (spec.title or "") ~= "") and 1 or 0
    local page = guicomponent.GUIComponent.new()
    page:setBorder(false)
    page:setBackgroundColor(root.backgroundColor)
    -- the page follows the theme like the root does unless bg was given
    if not spec.bg then page:themed("backgroundColor", "background", colors.white) end
    page:setPreferredBounds(1, 1 + top, root.w, root.h - top)
    root:add(page)
    page:setLayout(spec.grid and guilayout.GUIGridLayout.new(spec.rows, spec.columns, spec.gap or 0, spec.padding or 0) or boxLayout(spec))
    for i, child in ipairs(spec.children or {}) do page:add(buildSpec(child, ids)) end
    ids[spec.pageId or "page"] = page
    if spec.id then ids[spec.id] = root end
    return root, ids
  end
  local c = buildSpec(spec, ids)
  if containers[spec.type] and not (spec.w and spec.h) then
    local tw, th = (spec.term or term.current()).getSize()
    c:setPreferredBounds(spec.x or 1, spec.y or 1, spec.w or tw, spec.h or th)
  end
  return c, ids
end
