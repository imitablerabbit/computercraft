--[[
GUIComponentUI is used to render the components inside
their bounds.
--]]

GUIComponentUI = {}

function GUIComponentUI:new(component)
    local object = {
        component = component,
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
    
    term.redirect(self.component.term)
    term.clear()
    w, h = term.getSize()
    paintutils.drawFilledBox(1, 1, w, h, self.component.backgroundColor)
end

function GUIComponentUI:setComponent(c)
    self.component = c
end