GUITabsUI = {}
GUITabsUI.__index = GUITabsUI
setmetatable(GUITabsUI, {__index = guicomponentui.GUIComponentUI})

function GUITabsUI.new(component)
    local object = guicomponentui.GUIComponentUI.new(component, nil)
    setmetatable(object, GUITabsUI)
    return object
end

-- Only the strip: the selected component paints the content area.
function GUITabsUI:paint()
    local c = self.component
    if not c or not c.term then return end
    if not c:getSelectedComponent() then guicomponentui.GUIComponentUI.paint(self) end
    local old = term.redirect(c.term)
    local w = math.max(1, c.w - (c.reserve or 0)) -- the reserved end is left to whatever sits there
    local blit = guicomponentui.blitColor
    local text, fg, bg = {}, {}, {}
    local used = 0
    for i, slot in ipairs(c:stripLayout()) do
        local tab = c.tabs[slot.index]
        local chosen = slot.index == c.selected
        local title = tostring(tab.title)
        local label
        if #title + 2 <= slot.w then
            label = guicomponentui.fitText(" " .. title, slot.w)
        else
            label = guicomponentui.fitText(title, slot.w)
        end
        if used + #label > w then label = label:sub(1, math.max(0, w - used)) end
        text[#text + 1] = label
        fg[#fg + 1] = string.rep(blit(chosen and c.selectedTextColor or c.tabTextColor), #label)
        bg[#bg + 1] = string.rep(blit(chosen and c.selectedColor or c.stripColor), #label)
        used = used + #label
    end
    if used < w then
        text[#text + 1] = string.rep(" ", w - used)
        fg[#fg + 1] = string.rep(blit(c.tabTextColor), w - used)
        bg[#bg + 1] = string.rep(blit(c.stripColor), w - used)
    end
    term.setCursorPos(1, 1)
    term.blit(table.concat(text), table.concat(fg), table.concat(bg))
    term.redirect(old)
end
