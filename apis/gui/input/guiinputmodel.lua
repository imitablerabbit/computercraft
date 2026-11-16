GUIInputModel = {}
GUIInputModel.__index = GUIInputModel
setmetatable(GUIInputModel, {__index = guimodel.GUIModel})

function GUIInputModel.new()
    local object = guimodel.GUIModel.new()
    -- Is the input current ready to be typed in
    object.active = false
    setmetatable(object, GUIInputModel)
    return object
end

function GUIInputModel:setActive(a)
    self.active = a
end

function GUIInputModel:isActive()
    return self.active
end