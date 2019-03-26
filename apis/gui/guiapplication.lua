--[[
GUIApplication is the main root level object for creating a
gui application.
--]]

GUIApplication = {}
GUIApplication.__index = GUIApplication

function GUIApplication.new()
    local object = {
        -- The child container of the GUIApplication
        child = nil,

        -- Whether or not the application should continue running
        running = false,
        shouldRun = false,

        -- Update Rate / per second
        ups = 60,
        upsSleep = 1/60,
    }
    setmetatable(object, GUIApplication)
    return object
end

-- Start the GUI application loop.
function GUIApplication:start()
    self.running = true
    self.shouldRun = true
    if self.child then -- intial paint of component tree
        self.child:setStarted(true)
        self.child:repaint()
    end
    while self.shouldRun do
        self:update()
    end
end

function GUIApplication:stop()
    if self.child then
        self.child:setStarted(false)
    end
    self.shouldRun = false
end

function GUIApplication:update()
    if self.child then
        self.child:update()
    end

    function handleEvent()
        while true do
            local event = table.pack(os.pullEvent())
            if not event then return end
            if event[1] == "mouse_click" then
                local button, x, y = event[2], event[3], event[4]
                local e = guievent.GUIMouseClickEvent.new(button, x, y)
                if self.child then
                    self.child:triggerMouseClickEvent(e)
                end
            elseif event[1] == "monitor_touch" then
                local side, x, y = event[2], event[3], event[4]
                local e = guievent.GUIMonitorTouchEvent.new(side, x, y)
                if self.child then
                    self.child:triggerMonitorTouchEvent(e)
                end
            else
                -- os.queueEvent(table.unpack(event)) -- add event back to queue
            end
        end
    end
    
    function sleepRate() -- TODO: change this to a new stop event and add it to queue
        sleep(self.upsSleep)
    end

    parallel.waitForAny(handleEvent, sleepRate)
end

function GUIApplication:setRootContainer(container)
    self.child = container
end

function GUIApplication:setUPS(ups)
    self.ups = ups
    self.upsSleep = 1/ups
end