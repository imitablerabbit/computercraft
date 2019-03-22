GUIButtonModel = guimodel.GUIModel:new()

function GUIButtonModel:new()
    local object = {}
    self.__index = self
    setmetatable(object, self)
    return object
end