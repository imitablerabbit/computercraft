GUITextUI = guicomponentui.GUIComponentUI:new()

function GUITextUI:new(component, model)
    local object = guicomponentui.GUIComponentUI:new(component, model)
    self.__index = self
    setmetatable(object, self)
    return object
end

function GUITextUI:paint()
    guicomponentui.GUIComponentUI.paint(self)
    if not self.component then
        return
    end
    if not self.component.term then
        return
    end
    local c = term.redirect(self.component.term)
    local w, h = term.getSize()
    
    -- TODO: add other options when rending the text
    -- Should it be centered or at the start, e.g alignment
    -- Should the text be cut off and elipses used.

    term.setCursorPos(1, 1) -- default at the start of window
    local tc = term.getTextColor()
    local oldbc = term.getBackgroundColor()
    term.setTextColor(self.component.textColor)
    term.setBackgroundColor(self.component.backgroundColor)
    term.write(self.component.text)
    term.setTextColor(tc)
    term.setBackgroundColor(oldbc)
    term.redirect(c)
end
