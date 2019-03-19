--[[
GUIApplication is the main root level object for creating a
gui application.
--]]

local GUIApplication = {}

function GUIApplication:new()
    local object = {
        -- The child container of the GUIApplication
        child = nil,

        -- The monitor that the GUI application should be displayed on
        monitor = nil,

        -- Whether or not the application should continue running
        running = false,
        shouldRun = false
    }
    self.__index = GUIApplication
    setmetatable(object, self)
    return object
end

-- Start the GUI application loop.
function GUIApplication:start()
    self.running = true
    self.shouldRun = true
    while self.ShouldRun do
        self.update()
    end
end

function GUIApplication:stop()
    self.shouldRun = false
end

function GUIApplucation:update()
    if self.child then
        self.child.update()
    end
end

function GUIApplication:setRootContainer(container)
    self.child = container
end