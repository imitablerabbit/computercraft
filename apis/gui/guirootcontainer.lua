GUIRootContainer = guicomponent.GUIComponent:new()

function GUIRootContainer:new(t)
    local object = guicomponent.GUIComponent:new(t)
    self.__index = self
    setmetatable(object, self)
    return object
end

