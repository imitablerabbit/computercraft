--[[
GUIRootContainer is a top level component that should be added
to the GUIApplication. All other components should be added to
a GUIRootContainer. This component is responsible for drawing
window decorations and handling the operation of the close
button. If the GUIRootContainer has the decorations set then
a grey border on the top and a red close button will appear at
the top right of the screen
--]]

GUIRootContainer = {}
GUIRootContainer.__index = GUIRootContainer
setmetatable(GUIRootContainer, {__index = guicomponent.GUIComponent})

-- t is the terminal to draw on (default: the current one). When the
-- root is drawn on a monitor, pass the monitor's peripheral name as
-- side so that only touches on that monitor are delivered and mouse
-- clicks on the computer's own screen are ignored.
function GUIRootContainer.new(t, side)
    local object = guicomponent.GUIComponent.new(t)
    object.ui = guirootcontainerui.GUIRootContainerUI.new(object)
    object.decorations = true
    object.monitorSide = side
    object:setBorder(false)
    
    object.title = ""
    -- The title bar is drawn in the border colour.
    object:themed("borderColor", "header", colors.gray)
    object:themed("textColor", "headerText", colors.white)
    
    -- Create the close button
    local cb = guibutton.GUIButton.new("x")
    cb:themed("backgroundColor", "danger", colors.red)
    cb:themed("textColor", "dangerText", colors.white)
    cb:setPreferredBounds(object.w, 1, 1, 1)
    local close = function(event)
        object.parent:stop()
    end
    cb:addButtonListener(close)
    object.closeButton = cb
    object:add(cb)
    
    setmetatable(object, GUIRootContainer)
    return object
end

function GUIRootContainer:treeInit(parent)
    GUIComponent.treeInit(self, parent)
end

function GUIRootContainer:triggerMonitorTouchEvent(e)
    if self.monitorSide and e.side ~= self.monitorSide then return end
    local captured = guicomponent.getCapture()
    if captured then return captured:triggerMonitorTouchEvent(e) end
    guicomponent.GUIComponent.triggerMonitorTouchEvent(self, e)
end

function GUIRootContainer:triggerMouseClickEvent(e)
    if self.monitorSide then return end
    local captured = guicomponent.getCapture()
    if captured then return captured:triggerMouseClickEvent(e) end
    guicomponent.GUIComponent.triggerMouseClickEvent(self, e)
end

-- Keys, typed characters and the mouse wheel go only to a captured
-- component that asks for them (a dialog), otherwise to everything.
function GUIRootContainer:triggerKeyPressEvent(e)
    local captured = guicomponent.getCapture()
    if captured and captured.capturesKeys then return captured:triggerKeyPressEvent(e) end
    guicomponent.GUIComponent.triggerKeyPressEvent(self, e)
end

function GUIRootContainer:triggerCharEvent(e)
    local captured = guicomponent.getCapture()
    if captured and captured.capturesKeys then return captured:triggerCharEvent(e) end
    guicomponent.GUIComponent.triggerCharEvent(self, e)
end

function GUIRootContainer:triggerMouseScrollEvent(e)
    local captured = guicomponent.getCapture()
    if captured and captured.capturesKeys then return captured:triggerMouseScrollEvent(e) end
    guicomponent.GUIComponent.triggerMouseScrollEvent(self, e)
end

function GUIRootContainer:setDecorations(d)
    self.decorations = d
    self.closeButton:setVisible(d)
end

function GUIRootContainer:hasDecorations()
    return self.decorations
end

function GUIRootContainer:setTitle(t)
    self.title = t
end

function GUIRootContainer:getTitle()
    return self.title
end

