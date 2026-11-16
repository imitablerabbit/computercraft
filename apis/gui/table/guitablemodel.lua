--[[
GUITableModel holds what a GUITable shows: the columns, the rows, which
column the rows are sorted by and which row is selected. Rows keep the
index they were added with whatever the sort order, so a selection
stays on the same row when the table is sorted again.
--]]

GUITableModel = {}
GUITableModel.__index = GUITableModel
setmetatable(GUITableModel, {__index = guimodel.GUIModel})

function GUITableModel.new(columns)
    local object = guimodel.GUIModel.new()
    object.columns = columns or {}
    object.rows = {}
    object.sortColumn = nil
    object.descending = false
    object.selected = nil
    object.order = nil -- cached sorted list of row indexes
    setmetatable(object, GUITableModel)
    return object
end

function GUITableModel:setColumns(columns)
    self.columns = columns or {}
    self.order = nil
end

function GUITableModel:getColumns()
    return self.columns
end

-- rows: list of rows, each a list of values in column order. A row may
-- also carry color (text) and background fields.
function GUITableModel:setRows(rows)
    self.rows = rows or {}
    if self.selected and not self.rows[self.selected] then self.selected = nil end
    self.order = nil
end

function GUITableModel:addRow(row)
    table.insert(self.rows, row)
    self.order = nil
    return #self.rows
end

function GUITableModel:getRow(index)
    return self.rows[index]
end

function GUITableModel:getRowCount()
    return #self.rows
end

-- The value a row has in a column: row[column.key] when the column
-- names a key, otherwise row[position].
function GUITableModel:value(row, col)
    local column = self.columns[col]
    if column and column.key ~= nil then return row[column.key] end
    return row[col]
end

-- Sort by a column (nil for the order the rows were added).
function GUITableModel:sortBy(col, descending)
    self.sortColumn = col
    self.descending = descending and true or false
    self.order = nil
end

-- What a header touch does: sort by the column, or flip the direction
-- when it already is.
function GUITableModel:toggleSort(col)
    if self.sortColumn == col then
        self:sortBy(col, not self.descending)
    else
        self:sortBy(col, false)
    end
end

function GUITableModel:getSort()
    return self.sortColumn, self.descending
end

local function compareValues(a, b)
    local na, nb = tonumber(a), tonumber(b)
    if na and nb then
        if na == nb then return nil end
        return na < nb
    end
    if na and not nb then return true end -- numbers before text
    if nb and not na then return false end
    local sa, sb = string.lower(tostring(a or "")), string.lower(tostring(b or ""))
    if sa == sb then return nil end
    return sa < sb
end

-- The row indexes in the order they are shown.
function GUITableModel:getOrder()
    if self.order then return self.order end
    local order = {}
    for i = 1, #self.rows do order[i] = i end
    local col, desc = self.sortColumn, self.descending
    if col then
        table.sort(order, function(i, j)
            local less = compareValues(self:value(self.rows[i], col), self:value(self.rows[j], col))
            if less == nil then return i < j end -- ties keep the added order
            if desc then return not less end
            return less
        end)
    end
    self.order = order
    return order
end

function GUITableModel:select(index)
    self.selected = index
end

function GUITableModel:getSelected()
    return self.selected
end
