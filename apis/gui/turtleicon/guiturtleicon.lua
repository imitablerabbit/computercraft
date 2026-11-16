--[[
GUITurtleIcon shows a single turtle as a small picture with its label and
state underneath. The picture changes with the state (idle, busy, error,
offline). Clicking or touching the icon triggers the select listeners.
--]]

GUITurtleIcon = {}
GUITurtleIcon.__index = GUITurtleIcon
setmetatable(GUITurtleIcon, {__index = guicomponent.GUIComponent})

-- Smallest size that fits the picture, label and state line.
GUITurtleIcon.MinWidth = 12
GUITurtleIcon.MinHeight = 9

-- info is a table with id, label, state and optionally job and fuel.
function GUITurtleIcon.new(info)
    local object = guicomponent.GUIComponent.new()
    object.info = info or {}
    object.selectListeners = {}
    object.frame = 0 -- animation frame for the busy state
    object:setBorder(true)
    object.ui = guiturtleiconui.GUITurtleIconUI.new(object)
    setmetatable(object, GUITurtleIcon)
    object:themed("backgroundColor", "background")
    object:themed("textColor", "text")
    object:themed("borderColor", "border")
    local l = function(e)
        object:clickHandler(e)
    end
    object:addMouseClickListener(l)
    object:addMonitorTouchListener(l)
    return object
end

function GUITurtleIcon:clickHandler(e)
    if e.x >= self.ax and e.x < self.ax + self.w and
       e.y >= self.ay and e.y < self.ay + self.h then
        local event = guievent.GUIEvent.new("turtle_select")
        event.x, event.y = e.x, e.y
        event.turtle = self.info
        for i, l in pairs(self.selectListeners) do
            l(event)
        end
    end
end

function GUITurtleIcon:addSelectListener(l)
    table.insert(self.selectListeners, l)
end

function GUITurtleIcon:removeSelectListener(l)
    for i, l2 in pairs(self.selectListeners) do
        if l == l2 then
            table.remove(self.selectListeners, i)
        end
    end
end

-- Replace the turtle info and redraw.
function GUITurtleIcon:setInfo(info)
    self.info = info
    self:repaint()
end

function GUITurtleIcon:getInfo()
    return self.info
end

-- A turtle that has raised an alert shows as needing help, whatever
-- it is doing, until it goes offline.
function GUITurtleIcon:getState()
    local info = self.info
    if info.alerts and next(info.alerts) ~= nil and info.state ~= "offline" then return "alert" end
    return info.state or "offline"
end

-- Advance the busy animation (or the alert blink) by one frame.
function GUITurtleIcon:tick()
    local state = self:getState()
    if state == "busy" or state == "alert" then
        self.frame = self.frame + 1
        self:repaint()
    end
end
