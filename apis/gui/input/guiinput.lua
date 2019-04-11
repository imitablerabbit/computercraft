GUIInput = {}
GUIInput.__index = GUIInput
setmetatable(GUIInput, {__index = guitext.GUIText})

function GUIInput.new(text)
    local object = guitext.GUIText.new(text)
    object.buttonListeners = {}
    
    object.cursorPos = 0
    object.cursorTextColor = colors.black
    object.cursorBackgroundColor = colors.white
    
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
            self:moveCursor(-1)
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
        elseif self.isPrintable(k) then -- normal printable charaters.
            s = s:sub(1, cPos+1) .. self.toPrintable(k, false) .. s:sub(cPos+2)
            self:setText(s) -- Need to apply text so cursor can move
            self:moveCursor(1)
        end
    end
    self:setText(s)
end

-- Delete the char located at 'pos' in the string 's'.
function GUIInput.deleteChar(s, pos)
    return s:sub(1, pos-1) .. s:sub(pos+1)
end

function GUIInput:moveCursor(delta)
    self.cursorPos = self.cursorPos + delta
    if self.cursorPos < 0 then self.cursorPos = 0 end
    if self.cursorPos > self.text:len() then self.cursorPos = self.text:len() end
    return self.cursorPos
end

-- Return whether or not the passed in keycode represents a
-- printable charater.
function GUIInput.isPrintable(keycode)
    if keycode >= 2 and keycode <= 13 then return true end
    if keycode >= 16 and keycode <= 27 then return true end
    if keycode >= 30 and keycode <= 40 then return true end
    if keycode >= 44 and keycode <= 53 then return true end
    if keycode == 57 then return true end
    return false
end

function GUIInput.toPrintable(keycode, shift)
    local lower = {
        [2]="1", [3]="2", [4]="3", [5]="4", [6]="5", [7]="6", [8]="7", [9]="8", [10]="9", [11]="0", [12]="-", [13]="=",
        [16]="q", [17]="w", [18]="e", [19]="r", [20]="t", [21]="y", [22]="u", [23]="i", [24]="o", [25]="p", [26]="[", [27]="]",
        [30]="a", [31]="s", [32]="d", [33]="f", [34]="g", [35]="h", [36]="j", [37]="k", [38]="l", [39]=";", [40]="'",
        [44]="z", [45]="x", [46]="c", [47]="v", [48]="b", [49]="n", [50]="m", [51]=",", [52]=".", [53]="/",
        [57]=" ",
    }
    local upper = {
        [2]="1", [3]="2", [4]="3", [5]="4", [6]="5", [7]="6", [8]="7", [9]="8", [10]="9", [11]="0", [12]="_", [13]="+",
        [16]="Q", [17]="W", [18]="E", [19]="R", [20]="T", [21]="Y", [22]="U", [23]="I", [24]="O", [25]="P", [26]="{", [27]="}",
        [30]="A", [31]="S", [32]="D", [33]="F", [34]="G", [35]="H", [36]="J", [37]="K", [38]="L", [39]=":", [40]="\"",
        [44]="Z", [45]="X", [46]="C", [47]="V", [48]="B", [49]="N", [50]="M", [51]="<", [52]=">", [53]="?",
        [57]=" ",
    }
    
    if not shift then
        return lower[keycode]
    else 
        return upper[keycode]
    end
    return nil
end
