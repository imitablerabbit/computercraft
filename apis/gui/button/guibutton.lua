GUIButton = guicomponent.GUIComponent:new()

function GUIButton:new(text)
    local object = {
        model = guibuttonmodel.GUIButtonModel:new(),
        ui = guibuttonui.GUIButtonUI:new(self.term),

        buttonListeners = {},

        text = text,
        borderColor = colors.gray,
        backgroundColor = colors.lightGray,
        textColor = colors.white,
    }
    self.__index = self
    setmetatable(object, self)
    local l = function(e)
        object:mouseClickHandler(e)    
    end
    object:addMouseClickListener(l)
    return object
end

function GUIButton:treeInit(p)
    guicomponent.GUIComponent.treeInit(self, p)
    self.ui:setTerm(self.term)
end

function GUIButton:mouseClickHandler(e)
    -- Check if the mouse click is within the bounds
    -- of the absolute button position.
    if e.x > self.ax and e.x < self.ax + self.w and
       e.y > self.ay and e.y < self.ay + self.h then

        local event = guievent.GUIButtonClickEvent:new(e.x, e.y)
        self.triggerButtonPress(event)
    end
end

function GUIButton:addButtonListener(l)
    table.insert(self.buttonListeners, l)
end

function GUIButton:removeButtonListener(l)
    for i, l2 in pairs(self.buttonListeners) do
        if l == l2 then
            table.remove(self.buttonListeners, i)
        end
    end
end

function GUIButton:triggerButtonListener(e)
    if not e then error("missing GUIEvent") end
    if e.type ~= "button_click" then error("incorrect event") end
    for l in pairs(self.buttonListeners) do
        l(e)
    end
    if self.child then -- There probably wont be a child
        self.child:triggerButtonListener(e)
    end
end
