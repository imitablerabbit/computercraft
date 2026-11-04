--[[
GUICheckbox is a box that is ticked or not, with a label beside it:
"[x] Torches" or "[ ] Torches". Clicking or touching anywhere on the
component toggles it and tells the change listeners, which get an
event with the new checked value.
--]]

GUICheckbox = {}
GUICheckbox.__index = GUICheckbox
setmetatable(GUICheckbox, {__index = guicomponent.GUIComponent})

function GUICheckbox.new(text, checked)
    local object = guicomponent.GUIComponent.new()
    object.text = text or ""
    object.checked = checked and true or false
    object.changeListeners = {}
    object.backgroundColor = colors.black
    object.textColor = colors.white
    object.checkedColor = colors.lime
    object.uncheckedColor = colors.lightGray
    object:setBorder(false)
    object.ui = guicheckboxui.GUICheckboxUI.new(object)
    setmetatable(object, GUICheckbox)
    local l = function(e)
        object:clickHandler(e)
    end
    object:addMouseClickListener(l)
    object:addMonitorTouchListener(l)
    return object
end

function GUICheckbox:clickHandler(e)
    if e.x >= self.ax and e.x < self.ax + self.w and
       e.y >= self.ay and e.y < self.ay + self.h then
        self:setChecked(not self.checked, true)
    end
end

-- Set the state; with notify the change listeners are told.
function GUICheckbox:setChecked(checked, notify)
    self.checked = checked and true or false
    self:repaint()
    if notify then
        local event = guievent.GUIEvent.new("checkbox_change")
        event.checked = self.checked
        for i, l in pairs(self.changeListeners) do
            l(event)
        end
    end
end

function GUICheckbox:isChecked()
    return self.checked
end

function GUICheckbox:setText(t)
    self.text = t
    self:repaint()
end

function GUICheckbox:getText()
    return self.text
end

function GUICheckbox:addChangeListener(l)
    table.insert(self.changeListeners, l)
end

function GUICheckbox:removeChangeListener(l)
    for i, l2 in pairs(self.changeListeners) do
        if l == l2 then
            table.remove(self.changeListeners, i)
        end
    end
end

function GUICheckbox:setCheckedColor(c)
    self.checkedColor = c
end

function GUICheckbox:setUncheckedColor(c)
    self.uncheckedColor = c
end
