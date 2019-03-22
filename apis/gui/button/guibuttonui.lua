GUIButtonUI = guicomponentui.GUIComponentUI:new()

function GUIButtonUI:new(term, button)
    local object = guicomponentui.GUIComponentUI:new(term)
    self.__index = self
    setmetatable(object, self)
    return object
end

function GUIButtonUI:paint()
    if not self.term then
        return
    end
    if not self.component then
        return
    end
    
    t = term.current()
    term.redirect(self.term)
    w, h = term.getSize()

    -- Button background
    paintutils.fillBox(2, 2, w-1, h-1, self.component.backgroundColor)

    -- draw button border
    paintutils.drawBox(1, 1, w, h, self.component.borderColor)

    -- Write the text
    -- TODO: make this centered in the button
    term.setCursorPos(w/2, h/2)
    local tc = term.getTextColor()
    local bc = term.getBackgroundColor()
    term.setTextColor(self.component.textColor)
    term.setBackgroundColor(self.component.backgroundColor)
    term.write(self.component.text)
    term.setTextColor(tc)
    term.setBackgroundColor(bc)
    
    -- Set the terminal object back to what it was
    term.redirect(t)
end