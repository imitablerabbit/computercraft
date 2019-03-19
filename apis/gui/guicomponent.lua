--[[
GUIComponent is the container for a GUI object. This is the base class
for all GUI containers. This base class contains code for adding mouse
and key listeners.
--]]

local GUIComponent = {}

function GUIComponent:new()
    local object = {
        -- Mouse listeners
        monitorClickListeners = {},
        mouseClickListeners = {},

        -- Update Rate / per second
        ups = 60,
        upsSleep = 1/60,

        -- Position and size
        x = 0, y = 0,
        w = 0, h = 0
    }
    self.__index = GUIComponent
    setmetatable(object, self)
    return object
end

-- Handle the update loop. This function is responsible for
-- converting os mouse and key events into GUI events.
function GUIComponent:update()
    parallel.waitForAny(handleEvent, sleepRate)
end

function GUIComponent:handleEvent()
    local event = table.pack(os.pullEvent())
    if not event then return end
    if event[1] == "mouse_click" then
        local button, x, y = event[2], event[3], event[4]
        local e = guievents.GUIMouseClickEvent:new(button, x, y)
        self:triggerMouseClickEvent(e)
    elseif event[1] == "monitor_touch" then
        local side, x, y = event[2], event[3], event[4]
        local e = guievents.GUIMonitorTouchEvent:new(side, x, y)
        self:triggerMonitorTouchEvent(e)
    end
end

function GUIComponent:sleepRate()
    sleep(self.upsSleep)
end

-- Add the mouse listeners

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
end

function GUIComponent:addMouseClickListener(l)
    table.insert(self.mouseClickListeners, l)
end

function GUIComponent:removeEventListeners(l)
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
end

-- Getters and setters

-- Set the minimum number of updates that should happen per second.
function GUIComponent:setUPS(ups)
    self.ups = ups
    self.upsSleep = 1/ups
end

-- Set bounds of the container. This function should not allow
-- the bounds to be larger than the parent container.

-- Set the UI object. This object is responsible for painting
-- what this container looks like.