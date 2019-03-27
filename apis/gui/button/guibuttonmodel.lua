GUIButtonModel = {}
GUIButtonModel.__index = GUIButtonModel
setmetatable(GUIButtonModel, {__index = guimodel.GUIModel})

function GUIButtonModel.new()
    local object = guimodel.GUIModel.new()
    object.pressed = false
    setmetatable(object, GUIButtonModel)
    return object
end

function GUIButtonModel:setPressed(p)
    self.pressed = p
end

function GUIButtonModel:isPressed()
    return self.pressed
end