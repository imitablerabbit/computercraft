GUISparklineUI = {}
GUISparklineUI.__index = GUISparklineUI
setmetatable(GUISparklineUI, {__index = guicomponentui.GUIComponentUI})

function GUISparklineUI.new(component)
    local object = guicomponentui.GUIComponentUI.new(component, nil)
    setmetatable(object, GUISparklineUI)
    return object
end

-- A cell filled n thirds from the bottom: text, foreground, background.
-- The block characters only light their top four sixths in the
-- foreground colour, so a bottom filled cell is drawn inverted: the top
-- part in the empty colour on a filled background.
local function cell(n, fill, empty)
    if n <= 0 then return " ", empty, empty end
    if n == 1 then return string.char(143), empty, fill end -- top two thirds empty
    if n == 2 then return string.char(131), empty, fill end -- top third empty
    return " ", fill, fill
end

function GUISparklineUI:paint()
    local c = self.component
    if not c or not c.term then return end
    local old = term.redirect(c.term)
    local w, h = term.getSize()
    local blit = guicomponentui.blitColor
    local fill, empty = blit(c.fillColor), blit(c.emptyColor)
    local bgc = blit(c.backgroundColor)
    term.setBackgroundColor(c.backgroundColor)
    term.clear()
    local lo, hi = c:getRange()

    -- The range down the left, when asked for and there is room.
    local x0 = 1
    if c.showRange and #c.samples > 0 then
        local top, bottom = guisparkline.GUISparkline.shortNumber(hi), guisparkline.GUISparkline.shortNumber(lo)
        local gutter = math.max(#top, #bottom) + 1
        if w - gutter >= 4 then
            local fg = blit(c.textColor)
            term.setCursorPos(1, 1)
            term.blit(guicomponentui.fitText(top, gutter), string.rep(fg, gutter), string.rep(bgc, gutter))
            if h > 1 then
                term.setCursorPos(1, h)
                term.blit(guicomponentui.fitText(bottom, gutter), string.rep(fg, gutter), string.rep(bgc, gutter))
            end
            x0 = gutter + 1
        end
    end

    -- One column per sample, the newest on the right.
    local cols = w - x0 + 1
    local units = h * 3
    local n = #c.samples
    local rows = {}
    for y = 1, h do rows[y] = { t = {}, f = {}, b = {} } end
    for col = 1, cols do
        local i = n - (cols - col)
        local v = c.samples[i]
        local level = 0
        if v ~= nil then
            if hi > lo then
                level = math.floor((math.max(lo, math.min(hi, v)) - lo) / (hi - lo) * (units - 1) + 0.5) + 1
            else
                level = math.max(1, math.floor(units / 2)) -- a flat line half way up
            end
        end
        for y = 1, h do
            local fromBottom = h - y
            local t, f, b = cell(level - fromBottom * 3, fill, empty)
            if v == nil then t, f, b = " ", bgc, bgc end
            rows[y].t[col], rows[y].f[col], rows[y].b[col] = t, f, b
        end
    end
    for y = 1, h do
        term.setCursorPos(x0, y)
        term.blit(table.concat(rows[y].t), table.concat(rows[y].f), table.concat(rows[y].b))
    end
    term.redirect(old)
end
