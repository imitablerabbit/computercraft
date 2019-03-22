--[[
GUIComponentUI is used to render the components inside
their bounds. The passed in term object should be used to
paint the ui.
--]]

GUIComponentUI = {}

function GUIComponentUI:new(t)
    t = t or term.current()
    local object = {
        term = t,
        component = nil,
    }
    self.__index = self
    setmetatable(object, self)
    return object
end

function GUIComponentUI:paint()

end

function GUIComponentUI:setTerm(t)
    self.term = t
end

function GUIComponentUI:setComponent(c)
    self.component = c
end