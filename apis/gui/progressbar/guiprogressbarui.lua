GUIProgressBarUI = {}
GUIProgressBarUI.__index = GUIProgressBarUI
setmetatable(GUIProgressBarUI, {__index = guicomponentui.GUIComponentUI})

function GUIProgressBarUI.new(component)
    local object = guicomponentui.GUIComponentUI.new(component, nil)
    setmetatable(object, GUIProgressBarUI)
    return object
end

-- Every row is filled left to right; the label sits on the middle row
-- in the text colour over whichever part of the bar is under it.
function GUIProgressBarUI:paint()
    local c = self.component
    if not c or not c.term then return end
    local old = term.redirect(c.term)
    local w, h = term.getSize()
    local filled = math.floor(c:getFraction() * w + 0.5)
    local fill = guicomponentui.blitColor(c:isWarning() and c.warnColor or c.fillColor)
    local empty = guicomponentui.blitColor(c.emptyColor)
    local bg = string.rep(fill, filled) .. string.rep(empty, w - filled)
    -- When warning, the label over the empty part is in the warn colour
    -- too, so a nearly empty bar still shows red.
    local text = guicomponentui.blitColor(c.textColor)
    local fg = string.rep(text, filled) .. string.rep(c:isWarning() and guicomponentui.blitColor(c.warnColor) or text, w - filled)
    local labelRow = math.floor((h + 1) / 2)
    for y = 1, h do
        local text = string.rep(" ", w)
        if y == labelRow then text = guicomponentui.fitText(c:getText(), w, "center") end
        term.setCursorPos(1, y)
        term.blit(text, fg, bg)
    end
    term.redirect(old)
end
