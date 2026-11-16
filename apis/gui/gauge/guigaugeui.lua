GUIGaugeUI = {}
GUIGaugeUI.__index = GUIGaugeUI
setmetatable(GUIGaugeUI, {__index = guicomponentui.GUIComponentUI})

function GUIGaugeUI.new(component)
    local object = guicomponentui.GUIComponentUI.new(component, nil)
    setmetatable(object, GUIGaugeUI)
    return object
end

function GUIGaugeUI:paint()
    local c = self.component
    if not c or not c.term then return end
    local old = term.redirect(c.term)
    local w, h = term.getSize()
    local blit = guicomponentui.blitColor
    local fit = guicomponentui.fitText
    local fill = blit(c:isWarning() and c.warnColor or c.fillColor)
    local empty = blit(c.emptyColor)
    local bgc = blit(c.backgroundColor)
    local readout = c:getReadout()
    term.setBackgroundColor(c.backgroundColor)
    term.clear()
    if c.orientation == "horizontal" then
        -- label, meter, readout on the middle row
        local y = math.floor((h + 1) / 2)
        local label = c.label and (tostring(c.label) .. " ") or ""
        local right = " " .. readout
        local meterW = w - #label - #right
        if meterW < 3 then label = ""; meterW = w - #right end
        if meterW < 1 then right = ""; meterW = w end
        local filled = math.floor(c:getFraction() * meterW + 0.5)
        term.setCursorPos(1, y)
        term.blit(label, string.rep(blit(c.labelColor), #label), string.rep(bgc, #label))
        term.blit(string.rep(" ", meterW), string.rep(blit(c.textColor), meterW), string.rep(fill, filled) .. string.rep(empty, meterW - filled))
        term.blit(right, string.rep(blit(c.textColor), #right), string.rep(bgc, #right))
    else
        -- label on top, readout at the bottom, the meter between them
        local top, bottom = 1, h
        if c.label and h >= 3 then
            term.setCursorPos(1, 1)
            term.blit(fit(c.label, w, "center"), string.rep(blit(c.labelColor), w), string.rep(bgc, w))
            top = 2
        end
        if h - top + 1 >= 2 then
            term.setCursorPos(1, h)
            term.blit(fit(readout, w, "center"), string.rep(blit(c.textColor), w), string.rep(bgc, w))
            bottom = h - 1
        end
        local rows = bottom - top + 1
        local filled = math.floor(c:getFraction() * rows + 0.5)
        -- leave a column either side on wide gauges so it reads as a tube
        local x0, mw = 1, w
        if w >= 5 then x0, mw = 2, w - 2 end
        for i = 0, rows - 1 do
            local y = bottom - i
            term.setCursorPos(x0, y)
            local color = (i < filled) and fill or empty
            term.blit(string.rep(" ", mw), string.rep(blit(c.textColor), mw), string.rep(color, mw))
        end
    end
    term.redirect(old)
end
