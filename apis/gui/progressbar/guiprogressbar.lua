--[[
GUIProgressBar is a horizontal bar that fills from the left as a value
goes from 0 to its max: a job's progress, a turtle's fuel. A label can
be drawn over the bar ("12/64 layer 2"), or the percentage with
setShowPercent. Below the warn threshold (setWarnBelow) the filled part
and the label over the empty part turn the warn colour, so low fuel
shows red.

The bar is one row high by default and as wide as it is given; taller
bars fill every row and put the label in the middle one.
--]]

GUIProgressBar = {}
GUIProgressBar.__index = GUIProgressBar
setmetatable(GUIProgressBar, {__index = guicomponent.GUIComponent})

function GUIProgressBar.new(value, max)
    local object = guicomponent.GUIComponent.new()
    object.value = tonumber(value) or 0
    object.max = tonumber(max) or 100
    object.label = nil
    object.showPercent = false
    object.warnBelow = nil
    object.prefW, object.prefH = 10, 1
    object:setBorder(false)
    object.ui = guiprogressbarui.GUIProgressBarUI.new(object)
    setmetatable(object, GUIProgressBar)
    object:themed("backgroundColor", "background")
    object:themed("textColor", "text")
    object:themed("fillColor", "fill")
    object:themed("emptyColor", "track")
    object:themed("warnColor", "danger")
    return object
end

function GUIProgressBar:setValue(v)
    self.value = tonumber(v) or 0
    self:repaint()
end

function GUIProgressBar:getValue()
    return self.value
end

function GUIProgressBar:setMax(m)
    self.max = tonumber(m) or 0
    self:repaint()
end

function GUIProgressBar:getMax()
    return self.max
end

-- Both at once, with one repaint.
function GUIProgressBar:setProgress(value, max, label)
    self.value = tonumber(value) or 0
    if max ~= nil then self.max = tonumber(max) or 0 end
    if label ~= nil then self.label = label end
    self:repaint()
end

-- How full the bar is, 0 to 1.
function GUIProgressBar:getFraction()
    if not self.max or self.max <= 0 then return 0 end
    return math.max(0, math.min(1, self.value / self.max))
end

-- Text drawn over the bar; nil for none (or the percentage).
function GUIProgressBar:setLabel(text)
    self.label = text
    self:repaint()
end

function GUIProgressBar:getLabel()
    return self.label
end

-- Show "42%" when there is no label.
function GUIProgressBar:setShowPercent(show)
    self.showPercent = show and true or false
    self:repaint()
end

-- Below this value (not fraction) the filled part is drawn in color
-- (default the theme's danger colour). nil turns it off.
function GUIProgressBar:setWarnBelow(value, color)
    self.warnBelow = value
    if color then self.warnColor = color end
    self:repaint()
end

function GUIProgressBar:isWarning()
    return self.warnBelow ~= nil and self.value < self.warnBelow
end

function GUIProgressBar:setFillColor(c) self.fillColor = c end
function GUIProgressBar:setEmptyColor(c) self.emptyColor = c end
function GUIProgressBar:setWarnColor(c) self.warnColor = c end

-- The text shown over the bar.
function GUIProgressBar:getText()
    if self.label then return tostring(self.label) end
    if self.showPercent then return math.floor(self:getFraction() * 100 + 0.5) .. "%" end
    return ""
end
