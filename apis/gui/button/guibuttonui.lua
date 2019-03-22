GUIButtonUI = guicomponentui.GUIComponentUI:new()

function GUIButtonUI:new(term, button)
    local object = guicomponentui.GUIComponentUI:new(term)
    self.__index = self
    setmetatable(object, self)
    return object
end

function GUIButtonUI:paint()
    GUIComponentUI.paint(self) -- Call parent paint

    -- Button background
    paintutils.drawFilledBox(2, 2, w-1, h-1, self.component.backgroundColor)

    -- draw button border
    paintutils.drawBox(1, 1, w, h, self.component.borderColor)

    -- Write the text
    -- TODO: make this centered in the button
    local x = math.floor(w / 2) + 1
    local y = math.floor(h / 2) + 1
    term.setCursorPos(x, y)
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