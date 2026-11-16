--[[
GUIDropdown shows one value from a list of options. Closed, it is a
one line box with the value and a down arrow. Clicking or touching it
opens the list underneath (or above when there is more room there);
clicking an option selects it and closes the list, clicking anywhere
else just closes it. Long lists get scroll rows at the top and bottom.

While the list is open the dropdown captures every click, so nothing
underneath it is pressed by accident. The list is drawn in a window
on the top level component, so it can hang over other containers.
Select listeners get an event with value and index.
--]]

GUIDropdown = {}
GUIDropdown.__index = GUIDropdown
setmetatable(GUIDropdown, {__index = guicomponent.GUIComponent})

-- Most option rows shown at once.
GUIDropdown.MaxVisible = 6

-- options is a list of strings; selected is the index of the current
-- one (default 1).
function GUIDropdown.new(options, selected)
    local object = guicomponent.GUIComponent.new()
    object.options = options or {}
    object.selected = selected or 1
    object.open = false
    object.scroll = 0
    object.visible = 0
    object.upward = false
    object.closedH = 1
    object.selectListeners = {}
    object:setBorder(false)
    object.ui = guidropdownui.GUIDropdownUI.new(object)
    setmetatable(object, GUIDropdown)
    object:themed("backgroundColor", "accent")
    object:themed("textColor", "accentText")
    object:themed("listColor", "surface")
    object:themed("highlightColor", "highlight")
    object:themed("highlightTextColor", "highlightText")
    local l = function(e)
        object:clickHandler(e)
    end
    object:addMouseClickListener(l)
    object:addMonitorTouchListener(l)
    return object
end

-- The closed height is remembered so the list can be folded away.
function GUIDropdown:setPreferredBounds(x, y, w, h)
    self.closedH = h
    guicomponent.GUIComponent.setPreferredBounds(self, x, y, w, h)
end

function GUIDropdown:setBounds(x, y, w, h)
    self.closedH = h
    guicomponent.GUIComponent.setBounds(self, x, y, w, h)
end

-- The top level component (the root container), whose window the
-- open list is drawn on.
function GUIDropdown:top()
    local c = self
    while c.parent and c.parent.term do c = c.parent end
    return c
end

function GUIDropdown:addSelectListener(l)
    table.insert(self.selectListeners, l)
end

function GUIDropdown:removeSelectListener(l)
    for i, l2 in pairs(self.selectListeners) do
        if l == l2 then
            table.remove(self.selectListeners, i)
        end
    end
end

function GUIDropdown:getValue()
    return self.options[self.selected]
end

function GUIDropdown:getSelectedIndex()
    return self.selected
end

-- Select by value (no event is fired).
function GUIDropdown:setValue(value)
    for i, o in ipairs(self.options) do
        if o == value then self.selected = i end
    end
    self:repaint()
end

function GUIDropdown:setOptions(options, selected)
    self.options = options or {}
    self.selected = selected or 1
    if self.open then self:closeList() else self:repaint() end
end

function GUIDropdown:setListColor(c)
    self.listColor = c
end

function GUIDropdown:setHighlightColor(c)
    self.highlightColor = c
end

-- How many rows the open list gets and whether it opens upward,
-- from the room on the screen below and above the box.
function GUIDropdown:listLayout()
    local total = #self.options
    local wanted = math.min(total, GUIDropdown.MaxVisible)
    local top = self:top()
    local topY = top.ay or 1
    local screenH = top.h
    local below = topY + screenH - 1 - (self.ay + self.closedH - 1)
    local above = self.ay - topY
    if below >= wanted or below >= above then
        return math.max(1, math.min(wanted, below)), false
    end
    return math.max(1, math.min(wanted, above)), true
end

-- The rows of the open list, top to bottom: { kind = "option", index }
-- or { kind = "up" } / { kind = "down" } scroll rows.
function GUIDropdown:listRows()
    local total, visible = #self.options, self.visible
    local rows = {}
    if total <= visible then
        for i = 1, total do rows[#rows + 1] = { kind = "option", index = i } end
        return rows
    end
    rows[1] = { kind = "up" }
    for i = self.scroll + 1, math.min(total, self.scroll + visible - 2) do
        rows[#rows + 1] = { kind = "option", index = i }
    end
    rows[#rows + 1] = { kind = "down" }
    return rows
end

function GUIDropdown:maxScroll()
    return math.max(0, #self.options - (self.visible - 2))
end

function GUIDropdown:openList()
    if #self.options == 0 or not self.parent then return end
    local visible, upward = self:listLayout()
    if #self.options > visible and visible < 3 then visible = math.min(#self.options, 3) end
    self.open = true
    self.visible = visible
    self.upward = upward
    self.scroll = math.max(0, math.min(self.selected - 2, self:maxScroll()))
    -- The box plus the list, as a window on the top level component so
    -- it is not clipped by the container the dropdown sits in.
    local top = self:top()
    local h = self.closedH + visible
    self.popupY = upward and (self.ay - visible) or self.ay
    self.popup = window.create(top.term, self.ax - (top.ax or 1) + 1, self.popupY - (top.ay or 1) + 1, self.w, h)
    -- A dropdown in a dialog takes the capture from it and gives it back.
    local previous = guicomponent.getCapture(self)
    self.previousCapture = previous ~= self and previous or nil
    guicomponent.setCapture(self)
    self:repaint()
end

function GUIDropdown:closeList()
    if not self.open then return end
    self.open = false
    self.popup = nil
    if guicomponent.getCapture(self) == self then guicomponent.setCapture(self.previousCapture, self) end
    self.previousCapture = nil
    -- whatever the list covered has to be drawn again
    self:top():repaint()
end

function GUIDropdown:select(index)
    self.selected = index
    self:repaint() -- the list closed, and was drawn, before the choice changed
    local event = guievent.GUIEvent.new("dropdown_select")
    event.value = self.options[index]
    event.index = index
    for i, l in pairs(self.selectListeners) do
        l(event)
    end
end

function GUIDropdown:clickHandler(e)
    if not self.open then
        if e.x >= self.ax and e.x < self.ax + self.w and e.y >= self.ay and e.y < self.ay + self.closedH then
            self:openList()
        end
        return
    end
    local lx, ly = e.x - self.ax + 1, e.y - self.popupY + 1
    if lx < 1 or lx > self.w or ly < 1 or ly > self.closedH + self.visible then
        self:closeList()
        return
    end
    local listStart = self.upward and 1 or (self.closedH + 1)
    local row = ly - listStart + 1
    local r = self:listRows()[row]
    if row < 1 or row > self.visible or not r then
        self:closeList() -- the header, or an empty row
    elseif r.kind == "up" then
        self.scroll = math.max(0, self.scroll - 1)
        self:repaint()
    elseif r.kind == "down" then
        self.scroll = math.min(self:maxScroll(), self.scroll + 1)
        self:repaint()
    else
        self:closeList()
        self:select(r.index)
    end
end
