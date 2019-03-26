GUIRootContainer = {}
GUIRootContainer.__index = GUIRootContainer
setmetatable(GUIRootContainer, {__index = guicomponent.GUIComponent})

function GUIRootContainer.new(t)
    local object = guicomponent.GUIComponent.new(t)
    setmetatable(object, GUIRootContainer)
    return object
end

