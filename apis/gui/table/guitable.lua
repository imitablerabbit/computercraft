--[[
GUITable is a list view: a header row of column titles over rows of
values that scroll inside the table (a GUIScrollPane does the scrolling,
with a scrollbar when the rows do not fit).

Columns are { title, width } for a fixed width or { title, flex } to
share what is left, with optional align ("left", "right", "center") and
key (read row[key] instead of the value at the column's position).
Touching a column title sorts the rows by it, touching it again sorts
the other way; numbers sort as numbers. Touching a row selects it and
tells the select listeners (event index, row). A row can carry its own
colours in its color and background fields.

  local t = guitable.GUITable.new({
    { title = "Item", flex = 1 },
    { title = "Count", width = 6, align = "right" },
  })
  t:setRows({ { "coal", 12 }, { "torch", 40, color = colors.yellow } })
  t:addSelectListener(function(e) print(e.row[1]) end)
--]]

GUITable = {}
GUITable.__index = GUITable
setmetatable(GUITable, {__index = guicomponent.GUIComponent})

function GUITable.new(columns)
    local object = guicomponent.GUIComponent.new()
    object.model = guitablemodel.GUITableModel.new(columns)
    object.selectListeners = {}
    object.emptyText = ""
    object.striped = false
    object.prefW, object.prefH = 20, 6
    object:setBorder(false)
    object.ui = guitableui.GUITableUI.new(object)
    setmetatable(object, GUITable)
    object:themed("backgroundColor", "background")
    object:themed("textColor", "text")
    object:themed("headerColor", "header")
    object:themed("headerTextColor", "headerText")
    object:themed("stripeColor", "surface")
    object:themed("selectedColor", "highlight")
    object:themed("selectedTextColor", "highlightText")
    object:themed("mutedColor", "muted")

    -- The rows live in a body component inside a scroll pane under the
    -- header row.
    object.body = GUITableBody.new(object)
    object.pane = guiscrollpane.GUIScrollPane.new()
    object.pane:setPreferredBounds(1, 2, object.w, math.max(1, object.h - 1))
    object.pane:setContent(object.body)
    guicomponent.GUIComponent.add(object, object.pane)

    local l = function(e)
        object:headerClick(e)
    end
    object:addMouseClickListener(l)
    object:addMonitorTouchListener(l)
    return object
end

function GUITable:setBounds(x, y, w, h)
    guicomponent.GUIComponent.setBounds(self, x, y, w, h)
    self:placePane()
end

function GUITable:setPreferredBounds(x, y, w, h)
    guicomponent.GUIComponent.setPreferredBounds(self, x, y, w, h)
    self:placePane()
end

function GUITable:placePane()
    self.pane:setBounds(1, 2, self.w, math.max(1, self.h - 1))
    self:rowsChanged()
end

-- Tell the scroll pane how tall the rows are now and redraw.
function GUITable:rowsChanged()
    self.body.prefH = math.max(1, self.model:getRowCount())
    self.pane:layoutContent()
    self:repaint()
end

function GUITable:getModel()
    return self.model
end

function GUITable:setColumns(columns)
    self.model:setColumns(columns)
    self:repaint()
end

function GUITable:setRows(rows)
    self.model:setRows(rows)
    self:rowsChanged()
end

function GUITable:addRow(row)
    local index = self.model:addRow(row)
    self:rowsChanged()
    return index
end

function GUITable:clearRows()
    self:setRows({})
end

function GUITable:getRow(index)
    return self.model:getRow(index)
end

function GUITable:getRowCount()
    return self.model:getRowCount()
end

-- Sort by column col (nil: as added), ascending unless descending.
function GUITable:sortBy(col, descending)
    self.model:sortBy(col, descending)
    self:repaint()
end

function GUITable:getSort()
    return self.model:getSort()
end

-- Text shown when there are no rows.
function GUITable:setEmptyText(text)
    self.emptyText = text or ""
    self:repaint()
end

-- Alternate rows drawn in the stripe colour.
function GUITable:setStriped(striped)
    self.striped = striped and true or false
    self:repaint()
end

-- Select a row by the index it was added with; with notify the select
-- listeners are told. The table scrolls to show it.
function GUITable:select(index, notify)
    self.model:select(index)
    if index then
        local order = self.model:getOrder()
        for pos, i in ipairs(order) do
            if i == index then
                local top = self.pane:getScroll()
                local _, vh = self.pane:viewportSize()
                if pos <= top then self.pane:scrollTo(pos - 1)
                elseif pos > top + vh then self.pane:scrollTo(pos - vh) end
            end
        end
    end
    self:repaint()
    if notify and index then
        local event = guievent.GUIEvent.new("table_select")
        event.index = index
        event.row = self.model:getRow(index)
        for i, l in pairs(self.selectListeners) do
            l(event)
        end
    end
end

-- The selected row's index and the row, or nil.
function GUITable:getSelected()
    local index = self.model:getSelected()
    return index, index and self.model:getRow(index)
end

function GUITable:addSelectListener(l)
    table.insert(self.selectListeners, l)
end

function GUITable:removeSelectListener(l)
    for i, l2 in pairs(self.selectListeners) do
        if l == l2 then
            table.remove(self.selectListeners, i)
        end
    end
end

-- Column widths for the rows' width: fixed ones as given, flex ones
-- share the rest, one space between columns. Returns a list of
-- { x, w } (w may be 0 when a column does not fit).
function GUITable:columnLayout(width)
    local columns = self.model:getColumns()
    local fixed, flexTotal = 0, 0
    for i, c in ipairs(columns) do
        if (c.flex or 0) > 0 then flexTotal = flexTotal + c.flex
        else fixed = fixed + (c.width or #tostring(c.title or "") + 1) end
    end
    local spare = math.max(0, width - fixed - math.max(0, #columns - 1))
    local out, x, given, seen = {}, 1, 0, 0
    for i, c in ipairs(columns) do
        local w
        if (c.flex or 0) > 0 then
            seen = seen + c.flex
            local upTo = math.floor(spare * seen / flexTotal)
            w = upTo - given
            given = upTo
        else
            w = c.width or #tostring(c.title or "") + 1
        end
        w = math.max(0, math.min(w, width - x + 1))
        out[i] = { x = x, w = w }
        x = x + w + 1
    end
    return out
end

-- The width the rows are drawn in (the pane without its scrollbar).
function GUITable:rowWidth()
    local vw = self.pane:viewportSize()
    return vw
end

-- A touch on the header row sorts by that column.
function GUITable:headerClick(e)
    local x, y = e.x - self.ax + 1, e.y - self.ay + 1
    if y ~= 1 or x < 1 or x > self.w then return end
    for i, slot in ipairs(self:columnLayout(self:rowWidth())) do
        if slot.w > 0 and x >= slot.x and x <= slot.x + slot.w then
            self.model:toggleSort(i)
            self:repaint()
            return
        end
    end
end

-- A touch on a row (only inside the pane reaches here).
function GUITable:rowClick(pos)
    local index = self.model:getOrder()[pos]
    if index then self:select(index, true) end
end

--[[
GUITableBody draws the rows; it is as tall as there are rows and sits
in the table's scroll pane.
--]]

GUITableBody = {}
GUITableBody.__index = GUITableBody
setmetatable(GUITableBody, {__index = guicomponent.GUIComponent})

function GUITableBody.new(tableComponent)
    local object = guicomponent.GUIComponent.new()
    object.table = tableComponent
    object.prefW, object.prefH = 1, 1
    object:setBorder(false)
    object.ui = guitableui.GUITableBodyUI.new(object)
    setmetatable(object, GUITableBody)
    local l = function(e)
        local x, y = e.x - object.ax + 1, e.y - object.ay + 1
        if x >= 1 and x <= object.w and y >= 1 and y <= object.h then
            object.table:rowClick(y)
        end
    end
    object:addMouseClickListener(l)
    object:addMonitorTouchListener(l)
    return object
end
