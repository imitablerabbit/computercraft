GUIButton = guicomponent.GUIComponent:new()

function GUIButton:new(text)
    local object = {
        model = guibuttonmodel.GUIButtonModel:new(), -- TODO: link model to ui and component.

        buttonListeners = {},

        text = text,
    }
    self.__index = self
    setmetatable(object, self)
    local l = function(e)
        object:mouseClickHandler(e)    
    end
    object:addMouseClickListener(l)
    object.ui = guibuttonui.GUIButtonUI:new(object)
    return object
end

function GUIButton:treeInit(p)
    guicomponent.GUIComponent.treeInit(self, p)
end

function GUIButton:mouseClickHandler(e)
    -- Check if the mouse click is within the bounds
    -- of the absolute button position.
    if e.x > self.ax and e.x < self.ax + self.w and
       e.y > self.ay and e.y < self.ay + self.h then

        -- TODO: update the model here so the button looks
        -- like it is being clicked.
        self:repaint()
        local event = guievent.GUIButtonClickEvent:new(e.x, e.y)
        self:triggerButtonClickEvent(event)
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

function GUIButton:triggerButtonClickEvent(e)
    if not e then error("missing GUIEvent") end
    if e.type ~= "button_click" then error("incorrect event") end
    for i, l in pairs(self.buttonListeners) do
        l(e)
    end
    if self.child then -- There probably wont be a child
        self.child:triggerButtonClickEvent(e)
    end
end
