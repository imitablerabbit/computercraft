--[[
Layout managers place a container's children for it. Give a container
one with setLayout and add children with a preferred size (from
setPreferredBounds; only the size matters) and optionally a flex
share (setFlex) and whether to stretch across (setStretch).

GUIBoxLayout stacks the children along one axis, "vertical" or
"horizontal". Fixed children keep their preferred size on that axis,
children with flex share whatever is left in proportion, and across
the axis every child fills the container unless stretch is off.

GUIGridLayout puts the children in equal cells of rows x columns,
filling each row left to right.

Both take a gap between children and a padding inside the container,
and leave room for the container's border when it has one.
--]]

local function visibleChildren(container)
    local list = {}
    for i, c in ipairs(container.children or {}) do
        if c.visible ~= false then list[#list + 1] = c end
    end
    return list
end

-- The area inside the border and padding: x, y, w, h.
local function innerArea(container, padding)
    local inset = (container:hasBorder() and 1 or 0) + padding
    return 1 + inset, 1 + inset, math.max(1, container.w - 2 * inset), math.max(1, container.h - 2 * inset)
end

GUIBoxLayout = {}
GUIBoxLayout.__index = GUIBoxLayout

function GUIBoxLayout.new(axis, gap, padding)
    local object = { axis = axis or "vertical", gap = gap or 0, padding = padding or 0 }
    setmetatable(object, GUIBoxLayout)
    return object
end

function GUIBoxLayout:apply(container)
    local children = visibleChildren(container)
    if #children == 0 then return end
    local x0, y0, W, H = innerArea(container, self.padding)
    local vertical = self.axis == "vertical"
    local main = vertical and H or W
    local cross = vertical and W or H
    local fixed, flexTotal = 0, 0
    for i, c in ipairs(children) do
        local pw, ph = c:getPreferredSize()
        if (c.flex or 0) > 0 then
            flexTotal = flexTotal + c.flex
        else
            fixed = fixed + (vertical and ph or pw)
        end
    end
    local spare = math.max(0, main - fixed - self.gap * (#children - 1))
    local pos = 0
    local given = 0
    local flexSeen = 0
    for i, c in ipairs(children) do
        local pw, ph = c:getPreferredSize()
        local size
        if (c.flex or 0) > 0 then
            flexSeen = flexSeen + c.flex
            local upTo = math.floor(spare * flexSeen / flexTotal)
            size = upTo - given
            given = upTo
        else
            size = vertical and ph or pw
        end
        size = math.max(1, size)
        local crossSize = cross
        if c.stretch == false then crossSize = math.min(cross, vertical and pw or ph) end
        if vertical then
            c:setBounds(x0, y0 + pos, crossSize, size)
        else
            c:setBounds(x0 + pos, y0, size, crossSize)
        end
        pos = pos + size + self.gap
    end
end

-- The size the container needs to show every child at its preferred
-- size: w, h.
function GUIBoxLayout:preferredSize(container)
    local children = visibleChildren(container)
    local inset = 2 * ((container:hasBorder() and 1 or 0) + self.padding)
    local main, cross = 0, 0
    for i, c in ipairs(children) do
        local pw, ph = c:getPreferredSize()
        if self.axis == "vertical" then
            main = main + ph
            cross = math.max(cross, pw)
        else
            main = main + pw
            cross = math.max(cross, ph)
        end
    end
    main = main + self.gap * math.max(0, #children - 1)
    if self.axis == "vertical" then return cross + inset, main + inset end
    return main + inset, cross + inset
end

GUIGridLayout = {}
GUIGridLayout.__index = GUIGridLayout

-- rows or columns may be nil to be worked out from the other.
function GUIGridLayout.new(rows, columns, gap, padding)
    local object = { rows = rows, columns = columns, gap = gap or 0, padding = padding or 0 }
    setmetatable(object, GUIGridLayout)
    return object
end

function GUIGridLayout:shape(count)
    local rows, columns = self.rows, self.columns
    if not columns and not rows then columns = count; rows = 1 end
    if not columns then columns = math.ceil(count / rows) end
    if not rows then rows = math.ceil(count / columns) end
    return math.max(1, rows), math.max(1, columns)
end

function GUIGridLayout:apply(container)
    local children = visibleChildren(container)
    if #children == 0 then return end
    local x0, y0, W, H = innerArea(container, self.padding)
    local rows, columns = self:shape(#children)
    local cellW = math.max(1, math.floor((W - self.gap * (columns - 1)) / columns))
    local cellH = math.max(1, math.floor((H - self.gap * (rows - 1)) / rows))
    for i, c in ipairs(children) do
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        c:setBounds(x0 + col * (cellW + self.gap), y0 + row * (cellH + self.gap), cellW, cellH)
    end
end

function GUIGridLayout:preferredSize(container)
    local children = visibleChildren(container)
    local inset = 2 * ((container:hasBorder() and 1 or 0) + self.padding)
    local rows, columns = self:shape(#children)
    local cellW, cellH = 1, 1
    for i, c in ipairs(children) do
        local pw, ph = c:getPreferredSize()
        cellW = math.max(cellW, pw)
        cellH = math.max(cellH, ph)
    end
    return columns * cellW + self.gap * (columns - 1) + inset, rows * cellH + self.gap * (rows - 1) + inset
end
