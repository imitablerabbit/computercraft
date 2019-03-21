local GUIButton = GUIComponent:new{}

function GUIButton:new(text)
    local object = {
        model = GUIButtonModel:new{},
        ui = GUIButtonUI:new{},

        text = text,
        borderColor = colors.gray,
        backgroundColor = colors.lightGray,
        textColor = colors.white,
    }
    self.__index = self
    setmetatable(object, self)
    return object
end

function GUIButton:update()
    
end

