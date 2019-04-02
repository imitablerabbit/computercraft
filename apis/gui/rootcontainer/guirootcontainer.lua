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

function GUIRootContainer.new(t)
    local object = guicomponent.GUIComponent.new(t)
    object.ui = guirootcontainerui.GUIRootContainerUI.new(object)
    object.decorations = true
    local cb = guibutton.GUIButton.new("x")
    cb:setBackgroundColor(colors.red)
    cb:setTextColor(colors.white)
    cb:setPreferredBounds(1, object.w, 1, 1)
    local close = function(event)
        parent:stop()
    end
    cb:addButtonListener(close)
    object.closeButton = cb
    setmetatable(object, GUIRootContainer)
    return object
end

function GUIRootContainer:treeInit(parent)
    GUIComponent.treeInit(self, parent)
    if self.decorations then
        self:addCloseButton()
    end
end

function GUIRootContainer:setDecorations(d)
    self.decorations = d
    self.closeButton:setVisible(d)
end

function GUIRootContainer:hasDecorations()
    return self.decorations
end
