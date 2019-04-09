GUIInput = {}
GUIInput.__index = GUIInput
setmetatable(GUIInput, {__index = guicomponent.GUIComponent})

-- TODO: Change this to use GUIText as the base class. This stops
-- the need to duplicate the text functions and attributes.

function GUIInput.new(text)
    local object = guicomponent.GUIComponent.new()
    object.buttonListeners = {}
    
    object.text = text
    object.textAlign = "left"
    object.textVerticalAlign = "middle"  
    object.cursorPos = 0
    
    object.model = guiinputmodel.GUIInputModel.new()
    object.activeColor = colors.lightGray
    object:setBorder(true)
    object.ui = guiinputui.GUIInputUI.new(object, object.model)
    setmetatable(object, GUIInput)
    local kl = function(e)
        object:keyPressHandler(e)
    end
    object:addKeyPressListener(kl)
    local ml = function(e)
        object:mouseClickHandler(e)
    end
    object:addMouseClickListener(ml)
    return object
end

-- Check if the mouse click is within the bounds
-- of the absolute input position. If the mouse is
-- clicked within bounds then make the input active
-- otherwise we should just disable the model.
function GUIInput:mouseClickHandler(e)
    if e.x >= self.ax and e.x < self.ax + self.w and
       e.y >= self.ay and e.y < self.ay + self.h then
        if not self.model:isActive() then
            self.model:setActive(true)
            self:repaint()
        end
    else
        if self.model:isActive() then
            self.model:setActive(false)
            self:repaint()
        end
    end
end

-- If the model is active we should be appending the
-- text with the new text on the key event. Backspaces
-- and delete keys should remove the appropriate
-- characters in the text string.
-- TODO: This should eventually be moved to a more
-- appropriate text util location so multiple components
-- can use text editor functionality.
function GUIInput:keyPressHandler(e)
    local s = self.text
    local cPos = self.cursorPos
    if self.model:isActive() then
        local k = e.keycode
        if k == keys.backspace then -- backspace
            s = self.deleteChar(s, cPos)
        elseif k == keys.delete then -- delete
            local tempCPos = cPos + 1
            if tempCPos > s:len() then tempCPos = s:len() end
            s = self.deleteChar(s, tempCPos)
        elseif k == keys.left then -- left arrow
            self:moveCursor(-1)
        elseif k == keys.right then -- right arrow
            self:moveCursor(1)
        elseif k == keys.escape then -- escape
            self.model:setActive(false)        
        elseif isPrintable(k) then -- normal printable charaters.
            s = s .. k
        end
    end
    self.setText(s)
end

-- Delete the char located at 'pos' in the string 's'.
function GUIInput.deleteChar(s, pos)
    return s:sub(1, pos-1) .. s.sub(pos+1)
end

function GUIInput:moveCursor(delta)
    self.cursorPos = self.cursorPos + delta
    return self.cursorPos
end

-- Return whether or not the passed in keycode represents a
-- printable charater.
function GUIInput.isPrintable(keycode)
    return true
end

function GUIInput:setText(t)
    self.text = t
    self:repaint()
end

function GUIInput:getText()
    return self.text
end

-- left, center, right
function GUIInput:setTextAlign(a)
    self.textAlign = a
end

function GUIInput:getTextAlign()
    return self.textAlign
end

-- top, middle, bottom
function GUIInput:setTextVerticalAlign(a)
    self.textVerticalAlign = a
end

function GUIInput:getTextVerticalAlign()
    return self.textVerticalAlign
end