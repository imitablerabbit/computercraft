GUIDialogUI = {}
GUIDialogUI.__index = GUIDialogUI
setmetatable(GUIDialogUI, {__index = guicomponentui.GUIComponentUI})

function GUIDialogUI.new(component)
    local object = guicomponentui.GUIComponentUI.new(component, nil)
    setmetatable(object, GUIDialogUI)
    return object
end

-- The box, the title bar and the message; the buttons draw themselves.
function GUIDialogUI:paint()
    local c = self.component
    if not c or not c.term then return end
    local old = term.redirect(c.term)
    local w, h = term.getSize()
    term.setBackgroundColor(c.backgroundColor)
    term.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(c.titleColor)
    term.setTextColor(c.titleTextColor)
    term.write(guicomponentui.fitText(" " .. c.title, w))
    term.setBackgroundColor(c.backgroundColor)
    term.setTextColor(c.textColor)
    for i, line in ipairs(c.lines) do
        term.setCursorPos(3, 2 + i)
        term.write(line:sub(1, math.max(0, w - 4)))
    end
    term.redirect(old)
end
