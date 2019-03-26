GUIText = {}
GUIText.__index = GUIText
setmetatable(GUIText, {__index = guicomponent.GUIComponent})

function GUIText.new(text)
    local object = {
        text = text,
        textAlign = "left",
        textVerticalAlign = "middle",
    }
    setmetatable(object, GUIText)
    object.ui = guitextui.GUITextUI.new(object)
    return object
end

function GUIText:setText(t)
    self.text = t
    self:repaint()
end

function GUIText:getText()
    return self.text
end

-- left, center, right
function GUIText:setTextAlign(a)
    self.textAlign = a
end

function GUIText:getTextAlign()
    return self.textAlign
end

-- top, middle, bottom
function GUIText:setTextVerticalAlign(a)
    self.textVerticalAlign = a
end

function GUIText:getTextVerticalAlign()
    return self.textVerticalAlign
end