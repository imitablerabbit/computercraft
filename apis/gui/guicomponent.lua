--[[
GUIComponent is the container for a GUI object. This is the base class
for all GUI containers. This base class contains code for adding mouse
and key listeners.
--]]

local GUIComponent = {}

function GUIComponent:new()
    local object = {
        -- Parent component. This will be nil if there is no parent
        parent = nil,
        child = nil,

        -- Terminal object that this component should interact with
        term = nil,

        -- UI used to paint this component. A repaint will trigger this
        -- objects paint method
        ui = nil,
        
        -- Mouse listeners
        monitorClickListeners = {},
        mouseClickListeners = {},

        -- Position and size
        x = 0, y = 0,
        w = 0, h = 0,
    }
    self.__index = GUIComponent
    setmetatable(object, self)
    return object
end

-- Handle the update loop. This function is responsible for
-- converting os mouse and key events into GUI events.
function GUIComponent:update()
    -- do nothing
end

-- Repaint will paint this component and propagate through all
-- other children.
function GUIComponent:repaint()
    if self.ui then
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
    c.parent = p

    
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
    for l in pairs(self.monitorTouchListeners) do
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
    for l in pairs(self.mouseClickListeners) do
        l(e)
    end
    if self.child then
        self.child:triggerMouseClickEvent(e)
    end
end

-- Set the bounds of the object. There is no guarantee that these
-- bounds will be respected. If a layout manager is used then these
-- can and probably will be ignored.
function GUIComponent:setPrefferedBounds(x, y, w, h)
    self.x = x
    self.y = y
    self.w = w
    self.h = h
end

-- Set the UI that is going to paint this component. The UI
function GUIComponent:setUI(ui)
    self.ui = ui
    if ui then
        ui.setComponent(self)
    end
end