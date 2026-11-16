--[[
GUITabs is a row of tabs over a content area. Each tab has a title and
a component (usually a container with a layout); only the selected
tab's component is in the tree, so only it draws and gets clicks,
touches and keys. Touching a title selects that tab; select does the
same from code. Change listeners get an event with index and title.

The strip is the top row. Titles share it evenly and are cut short
when they do not fit; the selected one is drawn in the accent colour.
Extra components can sit at the right end of the strip (a Back button):
keep those columns free with setStripReserve(columns) and add the
component to the tabs with add, so it is drawn after the strip.
--]]

GUITabs = {}
GUITabs.__index = GUITabs
setmetatable(GUITabs, {__index = guicomponent.GUIComponent})

-- A tab that is not shown keeps its window, and CraftOS redraws a
-- visible window whenever it is moved or resized, so a hidden tab whose
-- layout changes would draw over the shown one. Hide its window; adding
-- the tab again gives it fresh visible windows.
local function hideTerm(c)
    if c.term and c.term.setVisible then c.term.setVisible(false) end
end

function GUITabs.new()
    local object = guicomponent.GUIComponent.new()
    object.tabs = {} -- { title, component }
    object.selected = nil
    object.reserve = 0
    object.changeListeners = {}
    object:setBorder(false)
    object.ui = guitabsui.GUITabsUI.new(object)
    setmetatable(object, GUITabs)
    object:themed("backgroundColor", "background")
    object:themed("textColor", "text")
    object:themed("stripColor", "surface")
    object:themed("tabTextColor", "muted")
    object:themed("selectedColor", "accent")
    object:themed("selectedTextColor", "accentText")
    local l = function(e)
        object:clickHandler(e)
    end
    object:addMouseClickListener(l)
    object:addMonitorTouchListener(l)
    return object
end

-- Add a tab; the first one added is selected. Returns its index.
function GUITabs:addTab(title, component)
    table.insert(self.tabs, { title = title, component = component })
    local index = #self.tabs
    if not self.selected then self:select(index, false) else
        hideTerm(component)
        self:repaint()
    end
    return index
end

function GUITabs:getTabCount()
    return #self.tabs
end

-- The component of a tab.
function GUITabs:getTab(index)
    local tab = self.tabs[index]
    return tab and tab.component
end

-- The index of the tab with that title, or nil.
function GUITabs:indexOf(title)
    for i, tab in ipairs(self.tabs) do
        if tab.title == title then return i end
    end
    return nil
end

function GUITabs:setTabTitle(index, title)
    if self.tabs[index] then
        self.tabs[index].title = title
        self:repaint()
    end
end

function GUITabs:getSelected()
    return self.selected
end

function GUITabs:getSelectedTitle()
    local tab = self.tabs[self.selected or 0]
    return tab and tab.title
end

function GUITabs:getSelectedComponent()
    return self:getTab(self.selected or 0)
end

-- Columns kept free at the right end of the strip.
function GUITabs:setStripReserve(columns)
    self.reserve = columns or 0
    self:repaint()
end

-- The content area inside the tabs: x, y, w, h.
function GUITabs:contentArea()
    return 1, 2, self.w, math.max(1, self.h - 1)
end

-- Put the selected component in the content area.
function GUITabs:placeContent()
    local c = self:getSelectedComponent()
    if c then
        local x, y, w, h = self:contentArea()
        c:setBounds(x, y, w, h)
    end
end

-- Show a tab. With notify (the default) the change listeners are told,
-- even when it was already selected, so they can refresh it.
function GUITabs:select(index, notify)
    local tab = self.tabs[index]
    if not tab then return end
    local current = self:getSelectedComponent()
    if current and current ~= tab.component then
        guicomponent.GUIComponent.remove(self, current)
        current:setStarted(false)
        hideTerm(current)
    end
    self.selected = index
    if current ~= tab.component then
        guicomponent.GUIComponent.add(self, tab.component)
        tab.component:setStarted(self.started)
    end
    self:placeContent()
    self:repaint()
    if notify ~= false then
        local event = guievent.GUIEvent.new("tab_change")
        event.index = index
        event.title = tab.title
        event.component = tab.component
        for i, l in pairs(self.changeListeners) do
            l(event)
        end
    end
end

function GUITabs:setBounds(x, y, w, h)
    guicomponent.GUIComponent.setBounds(self, x, y, w, h)
    self:placeContent()
end

function GUITabs:setPreferredBounds(x, y, w, h)
    guicomponent.GUIComponent.setPreferredBounds(self, x, y, w, h)
    self:placeContent()
end

-- The tabs need the widest tab content plus the strip.
function GUITabs:getPreferredSize()
    if self.prefSet then return self.prefW, self.prefH end
    local w, h = 1, 1
    for i, tab in ipairs(self.tabs) do
        local pw, ph = tab.component:getPreferredSize()
        w, h = math.max(w, pw), math.max(h, ph)
    end
    return w, h + 1
end

-- Where each title sits on the strip: list of { x, w, index }.
function GUITabs:stripLayout()
    local n = #self.tabs
    local out = {}
    if n == 0 then return out end
    local width = math.max(n, self.w - self.reserve)
    local natural = 0
    for i, tab in ipairs(self.tabs) do natural = natural + #tostring(tab.title) + 2 end
    local x = 1
    for i, tab in ipairs(self.tabs) do
        local tw
        if natural <= width then
            tw = #tostring(tab.title) + 2
        else
            -- share the strip evenly; the first ones get the spare columns
            tw = math.floor(width / n) + ((i <= width % n) and 1 or 0)
        end
        out[i] = { x = x, w = tw, index = i }
        x = x + tw
    end
    return out
end

function GUITabs:clickHandler(e)
    local x, y = e.x - self.ax + 1, e.y - self.ay + 1
    if y ~= 1 or x < 1 or x > self.w then return end
    for i, slot in ipairs(self:stripLayout()) do
        if x >= slot.x and x < slot.x + slot.w then
            self:select(slot.index, true)
            return
        end
    end
end

function GUITabs:addChangeListener(l)
    table.insert(self.changeListeners, l)
end

function GUITabs:removeChangeListener(l)
    for i, l2 in pairs(self.changeListeners) do
        if l == l2 then
            table.remove(self.changeListeners, i)
        end
    end
end

-- Every tab follows the theme, not only the one on show.
function GUITabs:themeChildren()
    local list = {}
    for i, c in ipairs(self.children) do list[#list + 1] = c end
    for i, tab in ipairs(self.tabs) do
        if tab.component ~= self:getSelectedComponent() then list[#list + 1] = tab.component end
    end
    return list
end
