GUIInventoryGridUI = {}
GUIInventoryGridUI.__index = GUIInventoryGridUI
setmetatable(GUIInventoryGridUI, {__index = guicomponentui.GUIComponentUI})

function GUIInventoryGridUI.new(component)
    local object = guicomponentui.GUIComponentUI.new(component, nil)
    setmetatable(object, GUIInventoryGridUI)
    return object
end

-- Convert a colors.* value to the hex digit used by term.blit.
local function blitChar(color)
    local n = math.floor(math.log(color) / math.log(2) + 0.5)
    return string.format("%x", n)
end

local function padRight(s, n)
    s = tostring(s)
    if #s > n then return string.sub(s, 1, n) end
    return s .. string.rep(" ", n - #s)
end

-- Cell geometry: four columns with a one character gap, rows stacked
-- without gaps so that 4x3 cells fit a turtle's 13 rows. compact is
-- true when the cells would be too small and a list is drawn instead.
function GUIInventoryGridUI:layout()
    local columns = self.component.Columns
    local w, h = self.component.w, self.component.h
    local rows = math.ceil((turtleinv.MaxSlot - turtleinv.MinSlot + 1) / columns)
    local cellW = math.floor((w - (columns - 1)) / columns)
    local cellH = math.floor(h / rows)
    local left = math.floor((w - (cellW * columns + columns - 1)) / 2)
    local compact = cellW < 6 or cellH < 2
    return cellW, cellH, left, rows, compact
end

-- The slots shown in compact mode, one per line, filled ones first.
function GUIInventoryGridUI:compactSlots()
    local slots = {}
    for slot = turtleinv.MinSlot, turtleinv.MaxSlot do
        if self.component.items[slot] then table.insert(slots, slot) end
    end
    return slots
end

-- The slot under a point in component coordinates, or nil for a gap.
function GUIInventoryGridUI:cellAt(x, y)
    local columns = self.component.Columns
    local cellW, cellH, left, rows, compact = self:layout()
    if compact then
        return self:compactSlots()[y]
    end
    local col = math.floor((x - 1 - left) / (cellW + 1))
    local row = math.floor((y - 1) / cellH)
    if col < 0 or col >= columns or row < 0 or row >= rows then return nil end
    local within = (x - 1 - left) - col * (cellW + 1)
    if within >= cellW then return nil end
    local slot = row * columns + col + turtleinv.MinSlot
    if slot > turtleinv.MaxSlot then return nil end
    return slot
end

-- The icon text and colours for an item: F for fuel, B for a block.
local function icons(item)
    local text, fg, bg = "", "", ""
    if item and item.fuel then
        text, fg, bg = text .. "F", fg .. blitChar(colors.black), bg .. blitChar(colors.orange)
    end
    if item and item.block then
        text, fg, bg = text .. "B", fg .. blitChar(colors.black), bg .. blitChar(colors.lime)
    end
    return text, fg, bg
end

function GUIInventoryGridUI:paint()
    local c = self.component
    if not c or not c.term then return end
    local old = term.redirect(c.term)
    local w, h = term.getSize()
    term.setBackgroundColor(c.backgroundColor)
    term.clear()
    local cellW, cellH, left, rows, compact = self:layout()
    if compact then
        self:paintList(w, h)
    else
        self:paintCells(cellW, cellH, left)
    end
    term.redirect(old)
end

-- One line per filled slot for monitors too small for the grid.
function GUIInventoryGridUI:paintList(w, h)
    local c = self.component
    local slots = self:compactSlots()
    if #slots == 0 then
        term.setCursorPos(1, 1)
        term.setTextColor(colors.lightGray)
        term.write("empty")
    end
    for i, slot in ipairs(slots) do
        if i > h then break end
        local item = c.items[slot]
        local bg = (slot == c.cursor) and colors.blue or c.backgroundColor
        local num = tostring(slot) .. ((slot == c.selected) and "*" or " ")
        local count = "x" .. tostring(item.count)
        local iconText, iconFg, iconBg = icons(item)
        local nameW = w - #num - 1 - #count - 1 - #iconText
        local text = num .. " " .. padRight(turtleinv.shortName(item), nameW) .. " " .. count .. iconText
        local fg = string.rep(blitChar(slot == c.selected and colors.yellow or colors.white), #num + 1)
            .. string.rep(blitChar(colors.white), nameW + 1) .. string.rep(blitChar(colors.lightGray), #count) .. iconFg
        local bgs = string.rep(blitChar(bg), #text - #iconText) .. iconBg
        term.setCursorPos(1, i)
        term.blit(text, fg, bgs)
    end
end

function GUIInventoryGridUI:paintCells(cellW, cellH, left)
    local c = self.component
    local columns = c.Columns
    for slot = turtleinv.MinSlot, turtleinv.MaxSlot do
        local index = slot - turtleinv.MinSlot
        local col, row = index % columns, math.floor(index / columns)
        local x = left + col * (cellW + 1) + 1
        local y = row * cellH + 1
        local item = c.items[slot]
        local bg = c.backgroundColor
        if slot == c.cursor then
            bg = colors.blue
        elseif item then
            bg = colors.gray
        end
        local bgHex = blitChar(bg)
        local function line(dy, text, fg, bgs)
            term.setCursorPos(x, y + dy)
            text = padRight(text, cellW)
            term.blit(text, fg or string.rep(blitChar(colors.white), cellW), bgs or string.rep(bgHex, cellW))
        end
        -- Row 1: slot number (yellow with * when it is the turtle's
        -- selected slot) and the icons at the right.
        local num = tostring(slot)
        if slot == c.selected then num = num .. "*" end
        local iconText, iconFg, iconBg = icons(item)
        local gap = math.max(0, cellW - #num - #iconText)
        local numFg = blitChar(slot == c.selected and colors.yellow or (item and colors.white or colors.lightGray))
        line(0, num .. string.rep(" ", gap) .. iconText,
            string.rep(numFg, #num) .. string.rep(blitChar(colors.white), gap) .. iconFg,
            string.rep(bgHex, #num + gap) .. iconBg)
        if item then
            local name = turtleinv.shortName(item)
            local count = "x" .. tostring(item.count)
            if cellH >= 3 then
                line(1, name)
                for dy = 2, cellH - 2 do line(dy, "") end
                line(cellH - 1, string.rep(" ", math.max(0, cellW - #count)) .. count,
                    string.rep(blitChar(colors.lightGray), cellW))
            else
                line(1, padRight(name, math.max(1, cellW - #count - 1)) .. " " .. count)
            end
        else
            for dy = 1, cellH - 1 do line(dy, "") end
        end
    end
end
