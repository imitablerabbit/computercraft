GUIText= guicomponent.GUIComponent:new()

function GUIText:new(text)
    local object = {
        text = text,
        model = guitextmodel.GUITextModel:new(),
    }
    self.__index = self
    setmetatable(object, self)
    object.ui = guitextui.GUITextUI:new(object, object.model)
    return object
end

function GUIText:setText(t)
    self.text = t
    self:repaint()
end

function GUIText:getText()
    return self.text
end
