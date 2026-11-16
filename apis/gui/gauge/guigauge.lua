--[[
GUIGauge is a compact level meter for things like stored energy or a
tank: a value between a min and a max shown as a filled column (or row)
with the number underneath (or beside it) and an optional short label.

Vertical (the default), the label is on the top row, the number on the
bottom row and the meter fills upward in between. Horizontal, it is
one row: the label, the meter, then the number. Below the warn
threshold (setWarnBelow) the fill turns the warn colour. setFormat
changes how the number is written, e.g. to add a unit.
--]]

GUIGauge = {}
GUIGauge.__index = GUIGauge
setmetatable(GUIGauge, {__index = guicomponent.GUIComponent})

function GUIGauge.new(min, max, value)
    local object = guicomponent.GUIComponent.new()
    object.min = tonumber(min) or 0
    object.max = tonumber(max) or 100
    object.value = tonumber(value) or object.min
    object.orientation = "vertical"
    object.label = nil
    object.warnBelow = nil
    object.format = nil
    object.prefW, object.prefH = 5, 8
    object:setBorder(false)
    object.ui = guigaugeui.GUIGaugeUI.new(object)
    setmetatable(object, GUIGauge)
    object:themed("backgroundColor", "background")
    object:themed("textColor", "text")
    object:themed("labelColor", "muted")
    object:themed("fillColor", "fill")
    object:themed("emptyColor", "track")
    object:themed("warnColor", "danger")
    return object
end

function GUIGauge:setValue(v)
    self.value = tonumber(v) or self.min
    self:repaint()
end

function GUIGauge:getValue()
    return self.value
end

function GUIGauge:setRange(min, max)
    self.min, self.max = tonumber(min) or 0, tonumber(max) or 100
    self:repaint()
end

function GUIGauge:getRange()
    return self.min, self.max
end

-- "vertical" or "horizontal". The preferred size follows unless one
-- was given with setPreferredBounds.
function GUIGauge:setOrientation(o)
    self.orientation = (o == "horizontal") and "horizontal" or "vertical"
    if not self.prefSet then
        if self.orientation == "horizontal" then self.prefW, self.prefH = 20, 1 else self.prefW, self.prefH = 5, 8 end
    end
    self:repaint()
end

function GUIGauge:setLabel(text)
    self.label = text
    self:repaint()
end

function GUIGauge:setWarnBelow(value, color)
    self.warnBelow = value
    if color then self.warnColor = color end
    self:repaint()
end

-- fn(value) returns the readout text.
function GUIGauge:setFormat(fn)
    self.format = fn
    self:repaint()
end

function GUIGauge:setFillColor(c) self.fillColor = c end
function GUIGauge:setEmptyColor(c) self.emptyColor = c end
function GUIGauge:setLabelColor(c) self.labelColor = c end

-- How full, 0 to 1.
function GUIGauge:getFraction()
    if self.max <= self.min then return 0 end
    return math.max(0, math.min(1, (self.value - self.min) / (self.max - self.min)))
end

function GUIGauge:isWarning()
    return self.warnBelow ~= nil and self.value < self.warnBelow
end

-- The readout: the formatted value, shortened with k and M when large.
function GUIGauge:getReadout()
    if self.format then return tostring(self.format(self.value)) end
    local v = self.value
    local a = math.abs(v)
    if a >= 1000000 then return string.format("%.1fM", v / 1000000) end
    if a >= 10000 then return string.format("%dk", math.floor(v / 1000)) end
    if v == math.floor(v) then return tostring(math.floor(v)) end
    return string.format("%.1f", v)
end
