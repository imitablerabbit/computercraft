--[[
GUIEvent is a base class that contains the minimum level
of information needed for a GUIEvent. GUIEvents are passed to
listener functions whenever an event they are observing happens.
--]]

GUIEvent = {}

-- Constructor
function GUIEvent:new(type)
    local object = {}
    object.type = type
    self.__index = self
    setmetatable(object, self)
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

GUIMouseClickEvent = GUIEvent:new{}

function GUIMouseClickEvent:new(button, x, y)
    local object = GUIEvent:new("mouse_click")
    object.button = button
    object.x = x
    object.y = y
    self.__index = self
    setmetatable(object, self)
    return object
end

--[[
GUIMonitorTouchEvent is an event that is triggered whenever a
monitor is right clicked.
--]]

GUIMonitorTouchEvent = GUIEvent:new{}

function GUIMonitorTouchEvent:new(side, x, y)
    local object = GUIEvent:new("monitor_touch")
    object.side = side
    object.x = x
    object.y = y
    self.__index = self
    setmetatable(object, self)
    return object
end

--[[
GUIButtonClick is an event that is triggered whenever a
button is clicked within its bounds.
--]]

GUIButtonClickEvent = GUIEvent:new{}

function GUIButtonClickEvent:new(x, y)
    local object = GUIEvent:new("button_click")
    object.x = x
    object.y = y
    self.__index = self
    setmetatable(object, self)
    return object
end
