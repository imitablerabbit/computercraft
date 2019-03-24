--[[
GUIComponentUI is used to render the components inside
their bounds.
--]]

GUIComponentUI = {}

function GUIComponentUI:new(component, model)
    local object = {
        component = component,
        model = model,
    }
    self.__index = self
    setmetatable(object, self)
    return object
end

function GUIComponentUI:paint()
    if not self.component then
        return
    end
    if not self.component.term then
        return
    end
    
    local c = term.redirect(self.component.term)
    term.clear()
    w, h = term.getSize()
    paintutils.drawFilledBox(1, 1, w + 1, h + 1, self.component.backgroundColor)
    if self.component.hasBorder then
        paintutils.drawBox(1, 1, w, h, self.component.borderColor)
    end
    term.redirect(c)
end

function GUIComponentUI:setComponent(c)
    self.component = c
end

function GUIComponentUI:setModel(m)
    self.model = m
end
