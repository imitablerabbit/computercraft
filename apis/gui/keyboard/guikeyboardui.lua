GUIKeyboardUI = {}
GUIKeyboardUI.__index = GUIKeyboardUI
setmetatable(GUIKeyboardUI, {__index = guicomponentui.GUIComponentUI})

function GUIKeyboardUI.new(component)
    local object = guicomponentui.GUIComponentUI.new(component, nil)
    setmetatable(object, GUIKeyboardUI)
    return object
end

-- Fill a box and write text centred in it.
local function key(x, y, w, h, text, bg, fg)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    for row = y, y + h - 1 do
        term.setCursorPos(x, row)
        term.write(string.rep(" ", w))
    end
    text = text:sub(1, w)
    term.setCursorPos(x + math.floor((w - #text) / 2), y + math.floor((h - 1) / 2))
    term.write(text)
end

-- The box, the title, the text with a cursor, the hint and the keys.
function GUIKeyboardUI:paint()
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

    -- the end of the text when it is too long, then a cursor block
    local fieldW = math.max(1, w - 2)
    local shown = c.text
    if #shown > fieldW - 1 then shown = shown:sub(#shown - fieldW + 2) end
    term.setCursorPos(2, 2)
    term.setBackgroundColor(c.fieldColor)
    term.setTextColor(c.fieldTextColor)
    term.write(shown .. "_" .. string.rep(" ", math.max(0, fieldW - #shown - 1)))

    local hint = c:hintText()
    if hint and c.head >= 4 then
        term.setCursorPos(2, 3)
        term.setBackgroundColor(c.backgroundColor)
        term.setTextColor(c.mutedColor)
        term.write(guicomponentui.fitText(hint, fieldW))
    end

    for i, k in ipairs(c.keys) do
        local bg, fg = c.keyColor, c.keyTextColor
        if k.action == "done" then bg, fg = c.doneColor, c.doneTextColor
        elseif k.action == "cancel" then bg, fg = c.cancelColor, c.cancelTextColor
        elseif k.action == "shift" and c.shift then bg, fg = c.pressColor, c.keyTextColor end
        if c.lit == i then bg = c.pressColor end
        key(k.x, k.y, k.w, k.h, c:labelOf(k), bg, fg)
    end
    term.redirect(old)
end
