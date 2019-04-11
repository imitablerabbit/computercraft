GUIInputUI = {}
GUIInputUI.__index = GUIInputUI
setmetatable(GUIInputUI, {__index = guicomponentui.GUIComponentUI})

function GUIInputUI.new(component, model)
    local object = guicomponentui.GUIComponentUI.new(component, model)
    setmetatable(object, GUIInputUI)
    return object
end

function GUIInputUI:paint()
    if not self.component then
        return
    end
    if not self.component.term then
        return
    end
    local c = term.redirect(self.component.term)
    local w, h = term.getSize()

    -- If the button is pressed then we need to render a
    -- darker background
    local bc = self.component.backgroundColor
    if self.model:isActive() then
        bc = self.component.activeColor
    end

    -- Re-render background and border
    paintutils.drawFilledBox(1, 1, w, h, bc)
    if self.component:hasBorder() then
        paintutils.drawBox(1, 1, w, h, self.component.borderColor)
    end
    
    -- TODO: add other options when rending the text
    -- Should it be centered or at the start, e.g alignment
    -- Should the text be cut off and elipses used.

    local y
    if self.component.textVerticalAlign == "top" then
        if self.component:hasBorder() then
            y = 2
        else
            y = 1
        end
    elseif self.component.textVerticalAlign == "middle" then
        y = math.floor(h / 2) + 1
    elseif self.component.textVerticalAlign == "bottom" then
        if self.component:hasBorder() then
            y = h - 1
        else
            y = h
        end
    end

    local x
    if self.component.textAlign == "left" then
        if self.component:hasBorder() then
            x = 2
        else
            x = 1
        end
    elseif self.component.textAlign == "center" then
        local textOffset = math.floor(string.len(self.component.text) / 2)
        x = math.floor(w / 2) + 1 - textOffset 
    elseif self.component.textAlign == "right" then
        x = w - string.len(self.component.text)
    end
    
    -- Render the text with the proper colors
    term.setCursorPos(x, y)
    local tc = term.getTextColor()
    local oldbc = term.getBackgroundColor()
    term.setTextColor(self.component.textColor)
    term.setBackgroundColor(self.component.backgroundColor)
    term.write(self.component.text)
    term.setTextColor(self.component.cursorTextColor)
    term.setBackgroundColor(self.component.cursorBackgroundColor)
    term.setCursorPos(x + self.component.cursorPos, y)
    local cPos = self.component.cursorPos
    local c = self.component.text:sub(cPos, cPos)
    term.write(c)
    term.setTextColor(tc)
    term.setBackgroundColor(oldbc)
    term.redirect(c)
end
