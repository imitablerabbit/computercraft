GUIButtonUI = guicomponentui.GUIComponent:new()

function GUIButtonUI:new(term)
    local object = guicomponentui.GUIComponentUI:new(term)
    self.__index = self
    setmetatable(object, self)
    return object
end

function GUIButtonUI:paint()
    if not self.term then
        return
    end
    
    t = term.current()
    term.redirect(self.term)
    w, h = term.getSize()

    -- Button background
    paintutils.paintBox(1, 1, w, h, self.backgroundColor)

    -- draw button border
    paintutils.paintBox(2, 2, w-1, h-1, self.borderColor)

    -- Write the text
    -- TODO: make this centered in the button
    
    -- Set the terminal object back to what it was
    term.redirect(t)
end