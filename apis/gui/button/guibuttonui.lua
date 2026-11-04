GUIButtonUI = {}
GUIButtonUI.__index = GUIButtonUI
setmetatable(GUIButtonUI, {__index = guicomponentui.GUIComponentUI})

function GUIButtonUI.new(component, model)
    local object = guicomponentui.GUIComponentUI.new(component, model)
    setmetatable(object, GUIButtonUI)
    return object
end

function GUIButtonUI:paint()
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
    if self.model:isPressed() then
        bc = self.component.pressColor
    end

    -- Re-render background and border
    paintutils.drawFilledBox(1, 1, w + 1, h + 1, bc)
    if self.component:hasBorder() then
        paintutils.drawBox(1, 1, w, h, self.component.borderColor)
    end

    -- Write the text, cut to the button width so narrow buttons
    -- show the start of the label rather than its middle.
    local text = self.component.text
    if string.len(text) > w then
        text = string.sub(text, 1, w)
    end
    local textOffset = math.floor(string.len(text) / 2)
    local x = math.floor(w / 2) + 1 - textOffset
    local y = math.floor(h / 2) + 1
    term.setCursorPos(x, y)
    local tc = term.getTextColor()
    local oldbc = term.getBackgroundColor()
    term.setTextColor(self.component.textColor)
    term.setBackgroundColor(bc)
    term.write(text)
    term.setTextColor(tc)
    term.setBackgroundColor(oldbc)
    term.redirect(c)
end
