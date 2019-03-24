GUIButtonModel = guimodel.GUIModel:new()

function GUIButtonModel:new()
    local object = {
        pressed = false,
    }
    self.__index = self
    setmetatable(object, self)
    return object
end

function GUIButtonModel:setPressed(p)
    self.pressed = p
end

function GUIButtonModel:isPressed()
    return self.pressed
end