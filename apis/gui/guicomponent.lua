--[[
GUIComponent is the container for a GUI object. This is the base class
for all GUI containers. This base class contains code for adding mouse
and key listeners.
--]]

GUIComponent = {}

function GUIComponent:new(t)
    t = t or term.current()
    width, height = t:getSize()
    w = window.create(t, 1, 1, width, height)

    local object = {
        -- Parent component. This will be nil if there is no parent
        parent = nil,
        child = nil,

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

        -- Default color settings
        visible = true,
        backgroundColor = colors.white,
        hasBorder = true,
        borderColor = colors.gray,
        textColor = colors.black,
    }
    self.__index = self
    setmetatable(object, self)
    object.ui = guicomponentui.GUIComponentUI:new(object)
    return object
end

-- Handle the update loop. This function is responsible for
-- converting os mouse and key events into GUI events.
function GUIComponent:update()
    if self.child then
        self.child:update()
    end
end

-- Repaint will paint this component and propagate through all
-- other children.
function GUIComponent:repaint()
    if self.ui and self.visible and self.started then
        self.ui:paint()
    end
    if self.child then
        self.child:repaint()
    end
end

-- Add a child component to this component.
function GUIComponent:add(c)
    self.child = c
    c:treeInit(self)
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

function GUIComponent:removeMonitorTouchListeners(l)
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
    if self.child then
        self.child:triggerMonitorTouchEvent(e)
    end
end

function GUIComponent:addMouseClickListener(l)
    table.insert(self.mouseClickListeners, l)
end

function GUIComponent:removeMouseClickListeners(l)
    for i, l2 in pairs(self.listeners) do
        if l == l2 then
            table.remove(self.listeners, i)
        end
    end
end

function GUIComponent:triggerMouseClickEvent(e)
    if not e then error("missing GUIEvent") end
    if e.type ~= "mouse_click" then error("incorrect event") end
    for i, l in pairs(self.mouseClickListeners) do
        l(e)
    end
    if self.child then
        self.child:triggerMouseClickEvent(e)
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
    self:repaint() -- TODO: stop this from rendering the button when the application has not started
end

-- Set the UI that is going to paint this component. The UI
function GUIComponent:setUI(ui)
    self.ui = ui
    if ui then
        ui.setComponent(self)
    end
    self:repaint() -- TODO: stop this from rendering the button when the application has not started
end

function GUIComponent:setStarted(s)
    self.started = s
    if self.child then
        self.child:setStarted(s)
    end
end

function GUIComponent:setVisible(v)
    self.visible = v
    if self.child then
        self.child:setVisible(v)
    end
    self:repaint()
end