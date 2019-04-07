--[[
GUIComponent is the container for a GUI object. This is the base class
for all GUI containers. This base class contains code for adding mouse
and key listeners.
--]]

GUIComponent = {}
GUIComponent.__index = GUIComponent

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
        
        -- Mouse listeners
        monitorTouchListeners = {},
        mouseClickListeners = {},

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
end

function GUIComponent:remove(c)
    for i, c2 in pairs(self.children) do
        if c == c2 then
            table.remove(self.children, i)
        end
    end
end

-- treeInit is called whenever this component is added to
-- parent object. The parent object is passed in as a parameter.
function GUIComponent:treeInit(p)
    self.parent = p
    self.ax = p.ax + self.x - 1
    self.ay = p.ay + self.y - 1
    self.term = window.create(p.term, self.x, self.y, self.w, self.h)
end

-- Add the mouse listeners, propagate listeners down tree

function GUIComponent:addMonitorTouchListener(l)
    table.insert(self.monitorTouchListeners, l)
end

function GUIComponent:removeMouseClickListeners(l)
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

-- Set the bounds of the object. There is no guarantee that these
-- bounds will be respected. If a layout manager is used then these
-- can and probably will be ignored.
function GUIComponent:setPreferredBounds(x, y, w, h)
    self.x = x
    self.y = y
    self.w = w
    self.h = h
    if self.parent then
        self.ax = self.parent.ax
        self.ay = self.parent.ay
    end
    self.term.reposition(x, y, w, h)
    self:repaint()
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
