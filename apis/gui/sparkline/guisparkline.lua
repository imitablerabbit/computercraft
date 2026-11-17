--[[
GUISparkline is a tiny chart of the last few values of something that
changes over time: fuel at each status message, items in a chest, the
energy in a cell. push(value) adds a sample at the right and the oldest
falls off the left once there are capacity samples (by default one per
column).

Each column is one sample, filled up from the bottom in thirds of a
character using the block characters, scaled so the lowest and highest
samples shown span the box (or a fixed range from setRange). With
setShowRange(true) the highest and lowest values are written down the
left side when there is room.
--]]

GUISparkline = {}
GUISparkline.__index = GUISparkline
setmetatable(GUISparkline, {__index = guicomponent.GUIComponent})

function GUISparkline.new(capacity)
    local object = guicomponent.GUIComponent.new()
    object.samples = {}
    object.capacity = capacity
    object.min = nil
    object.max = nil
    object.showRange = false
    object.prefW, object.prefH = 20, 3
    object:setBorder(false)
    object.ui = guisparklineui.GUISparklineUI.new(object)
    setmetatable(object, GUISparkline)
    object:themed("backgroundColor", "background")
    object:themed("textColor", "muted")
    object:themed("fillColor", "accent")
    object:themed("emptyColor", "background")
    return object
end

-- How many samples are kept: the given capacity, or the width.
function GUISparkline:getCapacity()
    return self.capacity or math.max(1, self.w)
end

function GUISparkline:setCapacity(n)
    self.capacity = n
    self:trim()
    self:repaint()
end

function GUISparkline:trim()
    local cap = math.max(1, self:getCapacity())
    while #self.samples > cap do table.remove(self.samples, 1) end
end

-- Add a sample on the right.
function GUISparkline:push(value)
    value = tonumber(value)
    if value == nil then return end
    table.insert(self.samples, value)
    self:trim()
    self:repaint()
end

-- Replace every sample (oldest first).
function GUISparkline:setSamples(list)
    self.samples = {}
    for i, v in ipairs(list or {}) do
        if tonumber(v) then table.insert(self.samples, tonumber(v)) end
    end
    self:trim()
    self:repaint()
end

function GUISparkline:getSamples()
    return self.samples
end

function GUISparkline:clear()
    self.samples = {}
    self:repaint()
end

-- A fixed scale; nil for either end scales to the samples.
function GUISparkline:setRange(min, max)
    self.min, self.max = min, max
    self:repaint()
end

-- The scale in use: lowest and highest values.
function GUISparkline:getRange()
    local lo, hi = self.min, self.max
    if lo == nil or hi == nil then
        local slo, shi
        for i, v in ipairs(self.samples) do
            slo = (slo == nil or v < slo) and v or slo
            shi = (shi == nil or v > shi) and v or shi
        end
        lo = lo or slo or 0
        hi = hi or shi or 0
    end
    return lo, hi
end

function GUISparkline:setShowRange(show)
    self.showRange = show and true or false
    self:repaint()
end

function GUISparkline:setFillColor(c) self.fillColor = c end
function GUISparkline:setEmptyColor(c) self.emptyColor = c end

-- Short numbers for the range labels.
function GUISparkline.shortNumber(v)
    local a = math.abs(v)
    if a >= 1000000 then return string.format("%.1fM", v / 1000000) end
    if a >= 100000 then return string.format("%dk", math.floor(v / 1000)) end
    if a >= 10000 then return string.format("%.1fk", v / 1000) end
    if v == math.floor(v) then return tostring(math.floor(v)) end
    return string.format("%.1f", v)
end
