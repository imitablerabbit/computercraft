GUICheckboxUI = {}
GUICheckboxUI.__index = GUICheckboxUI
setmetatable(GUICheckboxUI, {__index = guicomponentui.GUIComponentUI})

function GUICheckboxUI.new(component)
    local object = guicomponentui.GUIComponentUI.new(component, nil)
    setmetatable(object, GUICheckboxUI)
    return object
end

function GUICheckboxUI:paint()
    local c = self.component
    if not c or not c.term then return end
    local old = term.redirect(c.term)
    local w, h = term.getSize()
    term.setBackgroundColor(c.backgroundColor)
    term.clear()
    local y = math.floor(h / 2) + 1
    term.setCursorPos(1, y)
    term.setTextColor(c.checked and c.checkedColor or c.uncheckedColor)
    term.write(c.checked and "[x]" or "[ ]")
    if c.text ~= "" and w > 4 then
        term.setTextColor(c.textColor)
        term.write(" " .. string.sub(c.text, 1, w - 4))
    end
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    term.redirect(old)
end
