GUIDropdownUI = {}
GUIDropdownUI.__index = GUIDropdownUI
setmetatable(GUIDropdownUI, {__index = guicomponentui.GUIComponentUI})

function GUIDropdownUI.new(component)
    local object = guicomponentui.GUIComponentUI.new(component, nil)
    setmetatable(object, GUIDropdownUI)
    return object
end

local function fit(text, width)
    text = tostring(text)
    if #text > width then return text:sub(1, width) end
    return text .. string.rep(" ", width - #text)
end

function GUIDropdownUI:paint()
    local c = self.component
    if not c or not c.term then return end
    local old = term.redirect(c.term)
    local w = c.w
    local function line(y, text, fg, bg)
        term.setCursorPos(1, y)
        term.setBackgroundColor(bg)
        term.setTextColor(fg)
        term.write(fit(text, w))
    end
    -- The closed box: the value and an arrow at the right.
    local headerY = (c.open and c.upward) and (c.visible + 1) or 1
    local arrow = c.open and "\30" or "\31"
    local header = fit(c:getValue() or "", math.max(0, w - 2)) .. " " .. arrow
    for i = 1, c.closedH do
        line(headerY + i - 1, i == math.ceil(c.closedH / 2) and header or "", c.textColor, c.backgroundColor)
    end
    if c.open then
        local listStart = c.upward and 1 or (c.closedH + 1)
        for i, r in ipairs(c:listRows()) do
            local y = listStart + i - 1
            if r.kind == "up" then
                line(y, string.rep(" ", math.floor((w - 1) / 2)) .. "\30", c.textColor, c.listColor)
            elseif r.kind == "down" then
                line(y, string.rep(" ", math.floor((w - 1) / 2)) .. "\31", c.textColor, c.listColor)
            else
                local chosen = r.index == c.selected
                line(y, " " .. c.options[r.index], chosen and colors.black or c.textColor, chosen and c.highlightColor or c.listColor)
            end
        end
    end
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    term.redirect(old)
end
