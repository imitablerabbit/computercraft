GUITextModel = guimodel.GUIModel:new()

function GUITextModel:new()
    local object = {}
    self.__index = self
    setmetatable(object, self)
    return object
end
