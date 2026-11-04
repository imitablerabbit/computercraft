GUIScrollPaneUI = {}
GUIScrollPaneUI.__index = GUIScrollPaneUI
setmetatable(GUIScrollPaneUI, {__index = guicomponentui.GUIComponentUI})

function GUIScrollPaneUI.new(component)
    local object = guicomponentui.GUIComponentUI.new(component, nil)
    setmetatable(object, GUIScrollPaneUI)
    return object
end

function GUIScrollPaneUI:paint()
    local c = self.component
    if not c or not c.term then return end
    local old = term.redirect(c.term)
    local w, h = term.getSize()
    term.setBackgroundColor(c.backgroundColor)
    term.clear()
    if c.barShown and w >= 1 then
        local top, bottom = c:thumb()
        for y = 1, h do
            term.setCursorPos(w, y)
            if y == 1 then
                term.setBackgroundColor(c.barColor)
                term.setTextColor(c.arrowColor)
                term.write("\30")
            elseif y == h then
                term.setBackgroundColor(c.barColor)
                term.setTextColor(c.arrowColor)
                term.write("\31")
            else
                term.setBackgroundColor((y >= top and y <= bottom) and c.thumbColor or c.barColor)
                term.write(" ")
            end
        end
    end
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    term.redirect(old)
end
