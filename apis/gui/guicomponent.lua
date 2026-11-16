--[[
GUIComponent is the container for a GUI object. This is the base class
for all GUI containers. This base class contains code for adding mouse
and key listeners.
--]]

GUIComponent = {}
GUIComponent.__index = GUIComponent

-- A component that has captured the pointer (an open dropdown) gets
-- every click and touch until it releases the capture.
local captured = nil
function setCapture(c) captured = c end
function getCapture() return captured end

function GUIComponent.new(t)
    t = t or term.current()
    width, height = t:getSize()
    w = window.create(t, 1, 1, width, height)

    local object = {
        -- Parent component. This will be nil if there is no parent
        parent = nil,
        children = {},

        -- Terminal object that this component should interact with
        term = w,
        
        -- Listeners
        monitorTouchListeners = {},
        mouseClickListeners = {},
        mouseScrollListeners = {},
        keyPressListeners = {},
        charListeners = {},

        -- Layout: a layout manager for the children (nil means the
        -- children keep the bounds they were given), the preferred size
        -- a layout starts from, and how this component is laid out by
        -- its parent: flex shares spare space along the main axis,
        -- stretch fills the cross axis.
        layout = nil,
        prefW = width, prefH = height, prefSet = false,
        flex = 0,
        stretch = true,

        -- Position and size
        ax = 1, ay = 1, -- absolute position
        x = 1, y = 1, -- relative position
        w = width, h = height, -- relative dimensions

        -- Has the application been started
        started = false,

        -- Is this element going to be shown and is it
        -- going to handle any events
        visible = true,

        -- Default color settings
        backgroundColor = colors.white,
        border = false,
        borderColor = colors.gray,
        textColor = colors.black,
    }
    setmetatable(object, GUIComponent)
    object.ui = guicomponentui.GUIComponentUI.new(object)
    return object
end

-- Handle the update loop. This function is responsible for
-- converting os mouse and key events into GUI events.
function GUIComponent:update()
    if self.children and self.visible then
        for i, c in pairs(self.children) do
            c:update()
        end
    end
end

-- Repaint will paint this component and propagate through all
-- other children.
function GUIComponent:repaint()
    if self.ui and self.visible and self.started then
        self.ui:paint()
    end
    if self.children then
        for i, c in pairs(self.children) do
            c:repaint()
        end
    end
end

-- Add a children component to this component.
function GUIComponent:add(c)
    table.insert(self.children, c)
    c:treeInit(self)
    -- A component added to a running tree is live straight away.
    if self.started then c:setStarted(true) end
    if self.layout then self:doLayout() end
end

function GUIComponent:remove(c)
    for i, c2 in pairs(self.children) do
        if c == c2 then
            table.remove(self.children, i)
        end
    end
    if self.layout then self:doLayout() end
end

function GUIComponent:removeAll()
    self.children = {}
    if self.layout then self:doLayout() end
end

-- Layouts

-- Give this container a layout manager (GUIBoxLayout, GUIGridLayout).
-- It places the children whenever one is added or the container is
-- resized.
function GUIComponent:setLayout(layout)
    self.layout = layout
    self:doLayout()
end

function GUIComponent:doLayout()
    if self.layout then self.layout:apply(self) end
end

-- Spare space share along a layout's main axis (0 = fixed size).
function GUIComponent:setFlex(flex)
    self.flex = flex or 0
end

-- Whether a layout stretches this component across its cross axis.
function GUIComponent:setStretch(stretch)
    self.stretch = stretch and true or false
end

-- Move and resize without touching the preferred size. Used by layouts
-- and scroll panes; the children move along with it.
function GUIComponent:setBounds(x, y, w, h)
    self.x, self.y, self.w, self.h = x, y, math.max(1, w), math.max(1, h)
    if self.parent and self.parent.ax then
        self.ax = self.parent.ax + x - 1
        self.ay = self.parent.ay + y - 1
    end
    if self.term and self.term.reposition then self.term.reposition(self.x, self.y, self.w, self.h) end
    self:relocateChildren()
    if self.layout then self:doLayout() end
end

-- Recompute the absolute positions of the children after this
-- component moved.
function GUIComponent:relocateChildren()
    for i, c in pairs(self.children) do
        c.ax = self.ax + c.x - 1
        c.ay = self.ay + c.y - 1
        if c.term and c.term.reposition then c.term.reposition(c.x, c.y, c.w, c.h) end
        c:relocateChildren()
    end
end

-- The size this component would like: the bounds it was given with
-- setPreferredBounds, or, for a container that was never given any,
-- what its layout needs.
function GUIComponent:getPreferredSize()
    if self.layout and self.layout.preferredSize and not self.prefSet then
        return self.layout:preferredSize(self)
    end
    return self.prefW or self.w, self.prefH or self.h
end

-- treeInit is called whenever this component is added to
-- parent object. The parent object is passed in as a parameter.
function GUIComponent:treeInit(p)
    self.parent = p
    self.ax = p.ax + self.x - 1
    self.ay = p.ay + self.y - 1
    self.term = window.create(p.term, self.x, self.y, self.w, self.h)
    -- Children added before this component had a parent drew into a
    -- placeholder window; hang them under the real one.
    for i, c in pairs(self.children) do
        c:treeInit(self)
    end
end

-- Add the mouse listeners, propagate listeners down tree

function GUIComponent:addMonitorTouchListener(l)
    table.insert(self.monitorTouchListeners, l)
end

function GUIComponent:removeMonitorTouchListener(l)
    for i, l2 in pairs(self.monitorTouchListeners) do
        if l == l2 then
            table.remove(self.monitorTouchListeners, i)
        end
    end
end

function GUIComponent:triggerMonitorTouchEvent(e)
    if not e then error("missing GUIEvent") end
    if e.type ~= "monitor_touch" then error("incorrect event") end
    for i, l in pairs(self.monitorTouchListeners) do
        l(e)
    end
    if self.children then
        for i, c in pairs(self.children) do
            c:triggerMonitorTouchEvent(e)
        end
    end
end

function GUIComponent:addMouseClickListener(l)
    table.insert(self.mouseClickListeners, l)
end

function GUIComponent:removeMouseClickListeners(l)
    for i, l2 in pairs(self.mouseClickListeners) do
        if l == l2 then
            table.remove(self.mouseClickListeners, i)
        end
    end
end

function GUIComponent:triggerMouseClickEvent(e)
    if not e then error("missing GUIEvent") end
    if e.type ~= "mouse_click" then error("incorrect event") end
    for i, l in pairs(self.mouseClickListeners) do
        l(e)
    end
    if self.children then
        for i, c in pairs(self.children) do
            c:triggerMouseClickEvent(e)
        end
    end
end

function GUIComponent:addKeyPressListener(l)
    table.insert(self.keyPressListeners, l)
end

function GUIComponent:removeKeyPressListeners(l)
    for i, l2 in pairs(self.keyPressListeners) do
        if l == l2 then
            table.remove(self.keyPressListeners, i)
        end
    end
end

function GUIComponent:triggerKeyPressEvent(e)
    if not e then error("missing GUIEvent") end
    if e.type ~= "key_press" then error("incorrect event") end
    for i, l in pairs(self.keyPressListeners) do
        l(e)
    end
    if self.children then
        for i, c in pairs(self.children) do
            c:triggerKeyPressEvent(e)
        end
    end
end

-- Set the bounds of the object. There is no guarantee that these
-- bounds will be respected. If a layout manager is used then these
-- can and probably will be ignored.
function GUIComponent:setPreferredBounds(x, y, w, h)
    self.x = x
    self.y = y
    self.w = w
    self.h = h
    self.prefW = w
    self.prefH = h
    self.prefSet = true
    if self.parent then
        self.ax = self.parent.ax + x - 1
        self.ay = self.parent.ay + y - 1
    end
    self.term.reposition(x, y, w, h)
    self:relocateChildren()
    self:repaint()
end

-- Typed characters.

function GUIComponent:addCharListener(l)
    table.insert(self.charListeners, l)
end

function GUIComponent:removeCharListener(l)
    for i, l2 in pairs(self.charListeners) do
        if l == l2 then
            table.remove(self.charListeners, i)
        end
    end
end

function GUIComponent:triggerCharEvent(e)
    if not e then error("missing GUIEvent") end
    if e.type ~= "char" then error("incorrect event") end
    for i, l in pairs(self.charListeners) do
        l(e)
    end
    if self.children then
        for i, c in pairs(self.children) do
            c:triggerCharEvent(e)
        end
    end
end

-- Mouse wheel (computers only; monitors have no wheel).

function GUIComponent:addMouseScrollListener(l)
    table.insert(self.mouseScrollListeners, l)
end

function GUIComponent:removeMouseScrollListener(l)
    for i, l2 in pairs(self.mouseScrollListeners) do
        if l == l2 then
            table.remove(self.mouseScrollListeners, i)
        end
    end
end

function GUIComponent:triggerMouseScrollEvent(e)
    if not e then error("missing GUIEvent") end
    if e.type ~= "mouse_scroll" then error("incorrect event") end
    for i, l in pairs(self.mouseScrollListeners) do
        l(e)
    end
    if self.children then
        for i, c in pairs(self.children) do
            c:triggerMouseScrollEvent(e)
        end
    end
end

-- Set the UI that is going to paint this component. The UI
function GUIComponent:setUI(ui)
    self.ui = ui
    if ui then
        ui.setComponent(self)
    end
    self:repaint()
end

function GUIComponent:setStarted(s)
    self.started = s
    if self.children then
        for i, c in pairs(self.children) do
            c:setStarted(s)
        end
    end
end

function GUIComponent:setVisible(v)
    self.visible = v
    if self.children then
        for i, c in pairs(self.children) do
            c:setVisible(v)
        end
    end
    self:repaint()
end

function GUIComponent:setBorder(b)
    self.border = b
    if self.children then
        for i, c in pairs(self.children) do
            c:setBorder(b)
        end
    end
    self:repaint()
end

function GUIComponent:hasBorder()
    return self.border
end

function GUIComponent:setBackgroundColor(c)
    self.backgroundColor = c
end

function GUIComponent:getBackgroundColor()
    return self.backgroundColor
end

function GUIComponent:setTextColor(c)
    self.textColor = c
end

function GUIComponent:getTextColor()
    return self.textColor
end

function GUIComponent:setBorderColor(c)
    self.borderColor = c
end

function GUIComponent:getBorderColor()
    return self.borderColor
end
