--[[
GUIDialog is a modal box shown in the middle of the screen over
everything else: a title bar, a message and a row of buttons. While it
is open it captures every click, touch, key and typed character, so
nothing underneath can be pressed, and it is drawn again on top
whenever something underneath repaints. Pressing one of its buttons
closes it and then runs that button's function. On a keyboard, enter
presses the last button and escape the first.

  local d = guidialog.GUIDialog.new("Stop", "Stop the quarry?", {
    { text = "Cancel" },
    { text = "Stop", color = colors.red, onPress = function() ... end },
  })
  d:show(anyComponentOnTheScreen)

confirm and alert build the usual two dialogs in one call:

  guidialog.confirm(root, "Drop", "Drop 12 coal?", onYes, onNo,
                    { yes = "Drop", no = "Cancel", danger = true })
  guidialog.alert(root, "Done", "The quarry is finished.", onOk)

The message is wrapped to fit; "\n" starts a new line.
--]]

GUIDialog = {}
GUIDialog.__index = GUIDialog
setmetatable(GUIDialog, {__index = guicomponent.GUIComponent})

-- buttons: list of { text, color (optional), role (optional theme role
-- for the colour), onPress (optional) }.
function GUIDialog.new(title, message, buttons)
    local object = guicomponent.GUIComponent.new()
    object.title = title or ""
    object.message = message or ""
    object.buttonSpecs = buttons or { { text = "OK" } }
    object.lines = {}
    object.open = false
    object.capturesKeys = true
    object.host = nil
    object:setBorder(false)
    object.ui = guidialogui.GUIDialogUI.new(object)
    setmetatable(object, GUIDialog)
    object:themed("backgroundColor", "surface")
    object:themed("textColor", "text")
    object:themed("titleColor", "accent")
    object:themed("titleTextColor", "accentText")
    object:addKeyPressListener(function(e) object:keyHandler(e) end)
    return object
end

-- Wrap text to width: a list of lines. "\n" breaks a line.
function GUIDialog.wrap(text, width)
    local lines = {}
    if type(text) == "table" then
        for i, l in ipairs(text) do
            for j, w in ipairs(GUIDialog.wrap(l, width)) do lines[#lines + 1] = w end
        end
        return lines
    end
    width = math.max(1, width)
    for para in (tostring(text) .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in para:gmatch("%S+") do
            while #word > width do
                if line ~= "" then lines[#lines + 1] = line; line = "" end
                lines[#lines + 1] = word:sub(1, width)
                word = word:sub(width + 1)
            end
            if line == "" then line = word
            elseif #line + 1 + #word <= width then line = line .. " " .. word
            else lines[#lines + 1] = line; line = word end
        end
        lines[#lines + 1] = line
    end
    return lines
end

-- The top level component (the root container) the dialog covers.
local function topOf(c)
    while c.parent and c.parent.term do c = c.parent end
    return c
end

-- Work out the size from the screen and lay out the buttons.
function GUIDialog:build(top)
    local maxW = math.max(10, top.w - 2)
    local natural = #self.title + 4
    local buttonsW = 0
    for i, b in ipairs(self.buttonSpecs) do
        buttonsW = buttonsW + math.max(6, #b.text + 4) + (i > 1 and 2 or 0)
    end
    natural = math.max(natural, buttonsW + 4, 20)
    local longest = 0
    for i, l in ipairs(GUIDialog.wrap(self.message, maxW - 4)) do longest = math.max(longest, #l) end
    local w = math.min(maxW, math.max(natural, longest + 4))
    local lines = GUIDialog.wrap(self.message, w - 4)
    local bh = (top.h >= #lines + 9) and 3 or 1
    local fixed = 1 + 1 + 1 + bh + 1 -- title, gap, gap, buttons, margin
    while #lines > 0 and fixed + #lines > top.h do table.remove(lines) end
    local h = math.min(top.h, fixed + #lines)
    self.lines = lines
    self.buttonH = bh
    local x = math.floor((top.w - w) / 2) + 1
    local y = math.floor((top.h - h) / 2) + 1
    guicomponent.GUIComponent.setPreferredBounds(self, x, y, w, h)

    -- Buttons centred along the bottom, cut to fit when they do not.
    self:removeAll()
    local n = #self.buttonSpecs
    local widths, total = {}, 0
    for i, b in ipairs(self.buttonSpecs) do
        widths[i] = math.max(6, #b.text + 4)
        total = total + widths[i]
    end
    local gap = 2
    if total + gap * (n - 1) > w - 2 then
        gap = 1
        local each = math.floor((w - 2 - gap * (n - 1)) / n)
        for i = 1, n do widths[i] = math.max(1, each) end
        total = each * n
    end
    local bx = math.floor((w - (total + gap * (n - 1))) / 2) + 1
    local by = h - bh
    for i, spec in ipairs(self.buttonSpecs) do
        local b = guibutton.GUIButton.new(spec.text)
        b:setBorder(false)
        b:themed("backgroundColor", spec.role or ((i == n) and "button" or "background"))
        b:themed("textColor", (spec.role == "danger") and "dangerText" or ((i == n) and "buttonText" or "text"))
        b:themed("pressColor", "buttonPress")
        if spec.color then b:setBackgroundColor(spec.color) end
        if spec.textColor then b:setTextColor(spec.textColor) end
        b:setPreferredBounds(bx, by, widths[i], bh)
        b:addButtonListener(function() self:press(i) end)
        guicomponent.GUIComponent.add(self, b)
        bx = bx + widths[i] + gap
    end
end

-- Open the dialog over the screen that component is on.
function GUIDialog:show(component)
    if self.open then return end
    local top = topOf(component)
    self.host = top
    self:build(top)
    -- Added by hand so a layout on the top component leaves it alone.
    table.insert(top.children, self)
    self:treeInit(top)
    self:setStarted(top.started)
    self.open = true
    self.previousCapture = guicomponent.getCapture()
    guicomponent.setCapture(self)
    guicomponent.addOverlay(self)
    self:repaint()
end

-- Take the dialog away and redraw what it covered.
function GUIDialog:close()
    if not self.open then return end
    self.open = false
    guicomponent.removeOverlay(self)
    if guicomponent.getCapture() == self then guicomponent.setCapture(self.previousCapture) end
    self.previousCapture = nil
    local top = self.host
    self.host = nil
    if top then
        for i = #top.children, 1, -1 do
            if top.children[i] == self then table.remove(top.children, i) end
        end
        top:repaint()
    end
    self:setStarted(false)
end

function GUIDialog:isOpen()
    return self.open
end

-- Press button i: close, then run its function.
function GUIDialog:press(i)
    local spec = self.buttonSpecs[i]
    if not self.open or not spec then return end
    self:close()
    if spec.onPress then spec.onPress() end
end

function GUIDialog:keyHandler(e)
    if not self.open then return end
    if e.keycode == keys.enter then self:press(#self.buttonSpecs)
    elseif e.keycode == keys.escape then self:press(1) end
end

function GUIDialog:setTitle(t) self.title = t end
function GUIDialog:setMessage(m) self.message = m end

-- A question with two answers: no (left) and yes (right). opts: yes and
-- no button texts, danger = true to draw yes in red. Returns the dialog.
function confirm(component, title, message, onYes, onNo, opts)
    opts = opts or {}
    local d = GUIDialog.new(title, message, {
        { text = opts.no or "No", onPress = onNo },
        { text = opts.yes or "Yes", role = opts.danger and "danger" or nil, onPress = onYes },
    })
    d:show(component)
    return d
end

-- A message with one OK button. Returns the dialog.
function alert(component, title, message, onOk, okText)
    local d = GUIDialog.new(title, message, { { text = okText or "OK", onPress = onOk } })
    d:show(component)
    return d
end
