--[[
GUIInventoryGrid shows a turtle's 16 slots as a 4x4 grid of cells with
the item name, count and icons for fuel (orange F) and placeable
blocks (green B). The items come from turtleinv.scan or from an
inventory message, so the same component works on the turtle and on
the turtle control monitor. Clicking or touching a cell triggers the
select listeners; a keyboard cursor can be moved with moveCursor.
--]]

GUIInventoryGrid = {}
GUIInventoryGrid.__index = GUIInventoryGrid
setmetatable(GUIInventoryGrid, {__index = guicomponent.GUIComponent})

GUIInventoryGrid.Columns = 4

function GUIInventoryGrid.new(items, selected)
    local object = guicomponent.GUIComponent.new()
    object.items = items or {}
    object.selected = selected
    object.cursor = nil
    object.selectListeners = {}
    object.backgroundColor = colors.black
    object.textColor = colors.white
    object:setBorder(false)
    object.ui = guiinventorygridui.GUIInventoryGridUI.new(object)
    setmetatable(object, GUIInventoryGrid)
    local l = function(e)
        object:clickHandler(e)
    end
    object:addMouseClickListener(l)
    object:addMonitorTouchListener(l)
    return object
end

function GUIInventoryGrid:clickHandler(e)
    local x, y = e.x - self.ax + 1, e.y - self.ay + 1
    if x < 1 or y < 1 or x > self.w or y > self.h then return end
    local slot = self.ui:cellAt(x, y)
    if slot then
        self.cursor = slot
        self:select(slot)
    end
end

-- Fire the select listeners for a slot (empty slots included).
function GUIInventoryGrid:select(slot)
    local event = guievent.GUIEvent.new("slot_select")
    event.slot = slot
    event.item = self.items[slot]
    for i, l in pairs(self.selectListeners) do
        l(event)
    end
end

function GUIInventoryGrid:addSelectListener(l)
    table.insert(self.selectListeners, l)
end

function GUIInventoryGrid:removeSelectListener(l)
    for i, l2 in pairs(self.selectListeners) do
        if l == l2 then
            table.remove(self.selectListeners, i)
        end
    end
end

-- Replace the items (slot -> item) and the turtle's selected slot.
function GUIInventoryGrid:setItems(items, selected)
    self.items = items or {}
    self.selected = selected
    self:repaint()
end

function GUIInventoryGrid:getItems()
    return self.items
end

-- The keyboard cursor; nil hides it.
function GUIInventoryGrid:setCursor(slot)
    self.cursor = slot
    self:repaint()
end

function GUIInventoryGrid:getCursor()
    return self.cursor
end

-- Move the cursor by columns and rows, staying inside the grid.
function GUIInventoryGrid:moveCursor(dx, dy)
    local slot = (self.cursor or turtleinv.MinSlot) + dx + dy * GUIInventoryGrid.Columns
    slot = math.max(turtleinv.MinSlot, math.min(turtleinv.MaxSlot, slot))
    self:setCursor(slot)
end
