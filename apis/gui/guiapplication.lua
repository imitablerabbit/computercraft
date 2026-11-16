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

    -- Listeners that receive every raw os event (timers, rednet
    -- messages, ...) that the application pulls.
    eventListeners = {},
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
  term.clear()
  term.setCursorPos(1, 1)
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

  local function handleEvent()
    while true do
      local event = table.pack(os.pullEvent())
      if not event then return end
      for i, l in pairs(self.eventListeners) do
        l(event)
      end
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
      elseif event[1] == "mouse_scroll" then
        local direction, x, y = event[2], event[3], event[4]
        local e = guievent.GUIMouseScrollEvent.new(direction, x, y)
        if self.child then
          self.child:triggerMouseScrollEvent(e)
        end
      elseif event[1] == "char" then
        local e = guievent.GUICharEvent.new(event[2])
        if self.child then
          self.child:triggerCharEvent(e)
        end
      elseif event[1] == "key" then
        local keycode = event[2]
        local e = guievent.GUIKeyPressEvent.new(keycode)
        if self.child then
          self.child:triggerKeyPressEvent(e)
        end
      else
        -- os.queueEvent(table.unpack(event)) -- add event back to queue
      end
    end
  end

  local function sleepRate() -- TODO: change this to a new stop event and add it to queue
    sleep(self.upsSleep)
  end

  parallel.waitForAny(handleEvent, sleepRate)
end

-- A new root replaces the whole screen, so dialogs and open lists of
-- the old one are forgotten.
function GUIApplication:setRootContainer(container)
  guicomponent.resetModal(container)
  self.child = container
  container.parent = self
end

-- Add a listener that is called with the packed os event table
-- ({name, p1, p2, ...}) for every event the application pulls.
function GUIApplication:addEventListener(l)
  table.insert(self.eventListeners, l)
end

function GUIApplication:removeEventListener(l)
  for i, l2 in pairs(self.eventListeners) do
    if l == l2 then
      table.remove(self.eventListeners, i)
    end
  end
end

function GUIApplication:setUPS(ups)
  self.ups = ups
  self.upsSleep = 1/ups
end
