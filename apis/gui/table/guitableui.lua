GUITableUI = {}
GUITableUI.__index = GUITableUI
setmetatable(GUITableUI, {__index = guicomponentui.GUIComponentUI})

function GUITableUI.new(component)
    local object = guicomponentui.GUIComponentUI.new(component, nil)
    setmetatable(object, GUITableUI)
    return object
end

-- The header row, with an arrow on the sorted column.
function GUITableUI:paint()
    local c = self.component
    if not c or not c.term then return end
    local old = term.redirect(c.term)
    local w = c.w
    local fit = guicomponentui.fitText
    local line = {}
    for i = 1, w do line[i] = " " end
    local col, desc = c:getSort()
    for i, slot in ipairs(c:columnLayout(c:rowWidth())) do
        local column = c.model:getColumns()[i]
        if slot.w > 0 then
            local title = tostring(column.title or "")
            if col == i then
                title = fit(title, math.max(0, slot.w - 1), column.align) .. (desc and "\31" or "\30")
            else
                title = fit(title, slot.w, column.align)
            end
            for k = 1, #title do
                local x = slot.x + k - 1
                if x <= w then line[x] = title:sub(k, k) end
            end
        end
    end
    term.setCursorPos(1, 1)
    term.setBackgroundColor(c.headerColor)
    term.setTextColor(c.headerTextColor)
    term.write(table.concat(line))
    term.redirect(old)
end

GUITableBodyUI = {}
GUITableBodyUI.__index = GUITableBodyUI
setmetatable(GUITableBodyUI, {__index = guicomponentui.GUIComponentUI})

function GUITableBodyUI.new(component)
    local object = guicomponentui.GUIComponentUI.new(component, nil)
    setmetatable(object, GUITableBodyUI)
    return object
end

-- Every row; the scroll pane shows the part in view.
function GUITableBodyUI:paint()
    local body = self.component
    if not body or not body.term then return end
    local c = body.table
    local old = term.redirect(body.term)
    local w, h = term.getSize()
    local fit = guicomponentui.fitText
    term.setBackgroundColor(c.backgroundColor)
    term.clear()
    local model = c.model
    local order = model:getOrder()
    if #order == 0 and c.emptyText ~= "" then
        term.setCursorPos(1, 1)
        term.setTextColor(c.mutedColor)
        term.write(fit(c.emptyText, w))
    end
    local layout = c:columnLayout(w)
    local selected = model:getSelected()
    for pos, index in ipairs(order) do
        if pos > h then break end
        local row = model:getRow(index)
        local bg, fg = c.backgroundColor, row.color or c.textColor
        if c.striped and pos % 2 == 0 then bg = c.stripeColor end
        if row.background then bg = row.background end
        if index == selected then bg, fg = c.selectedColor, c.selectedTextColor end
        local line = {}
        for i = 1, w do line[i] = " " end
        for i, slot in ipairs(layout) do
            if slot.w > 0 then
                local v = model:value(row, i)
                local text = fit(v == nil and "" or tostring(v), slot.w, model:getColumns()[i].align)
                for k = 1, #text do
                    local x = slot.x + k - 1
                    if x <= w then line[x] = text:sub(k, k) end
                end
            end
        end
        term.setCursorPos(1, pos)
        term.setBackgroundColor(bg)
        term.setTextColor(fg)
        term.write(table.concat(line))
    end
    term.redirect(old)
end
