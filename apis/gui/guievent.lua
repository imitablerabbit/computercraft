--[[
GUIEvent is a base class that contains the minimum level
of information needed for a GUIEvent. GUIEvents are passed to
listener functions whenever an event they are observing happens.
--]]

GUIEvent = {}
GUIEvent.__index = GUIEvent

-- Constructor
function GUIEvent.new(type)
    local object = {}
    object.type = type
    setmetatable(object, GUIEvent)
    return object
end

function GUIEvent:getType()
    return self.type
end

--[[
GUIMouseClickEvent is an event that is triggered whenever the mouse
is clicked inside the normal terminal. If a monitor is used then you
will also need to handle the GUIMonitorTouchEvent.    
--]]

GUIMouseClickEvent = {}
GUIMouseClickEvent.__index = GUIMouseClickEvent
setmetatable(GUIMouseClickEvent, {__index = GUIEvent})

function GUIMouseClickEvent.new(button, x, y)
    local object = GUIEvent.new("mouse_click")
    object.button = button
    object.x = x
    object.y = y
    setmetatable(object, GUIMouseClickEvent)
    return object
end

--[[
GUIMonitorTouchEvent is an event that is triggered whenever a
monitor is right clicked.
--]]

GUIMonitorTouchEvent = {}
GUIMonitorTouchEvent.__index = GUIMonitorTouchEvent
setmetatable(GUIMonitorTouchEvent, {__index = GUIEvent})

function GUIMonitorTouchEvent.new(side, x, y)
    local object = GUIEvent.new("monitor_touch")
    object.side = side
    object.x = x
    object.y = y
    setmetatable(object, GUIMonitorTouchEvent)
    return object
end

--[[
GUIButtonClick is an event that is triggered whenever a
button is clicked within its bounds.
--]]

GUIButtonClickEvent = {}
GUIButtonClickEvent.__index = GUIButtonClickEvent
setmetatable(GUIButtonClickEvent, {__index = GUIEvent})

function GUIButtonClickEvent.new(x, y)
    local object = GUIEvent.new("button_click")
    object.x = x
    object.y = y
    setmetatable(object, GUIButtonClickEvent)
    return object
end
