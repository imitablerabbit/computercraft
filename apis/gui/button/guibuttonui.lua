GUIButtonUI = guicomponentui.GUIComponentUI:new()

function GUIButtonUI:new(component, button)
    local object = guicomponentui.GUIComponentUI:new(component)
    self.__index = self
    setmetatable(object, self)
    return object
end

function GUIButtonUI:paint()
    guicomponentui.GUIComponentUI.paint(self) -- Call parent paint
    if not self.component then
        return
    end
    if not self.component.term then
        return
    end
    local c = term.redirect(self.component.term)
    local w, h = term.getSize()

    -- Write the text
    local textOffset = math.floor(string.len(self.component.text) / 2)
    local x = math.floor(w / 2) + 1 - textOffset
    local y = math.floor(h / 2) + 1
    term.setCursorPos(x, y)
    local tc = term.getTextColor()
    local bc = term.getBackgroundColor()
    term.setTextColor(self.component.textColor)
    term.setBackgroundColor(self.component.backgroundColor)
    term.write(self.component.text)
    term.setTextColor(tc)
    term.setBackgroundColor(bc)
    term.redirect(c)
end