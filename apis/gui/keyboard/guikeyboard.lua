--[[
GUIKeyboard is an on-screen keyboard for touch monitors, which have no
keyboard of their own. It opens over the whole screen like a dialog: a
title, the text being typed, an optional hint line under it, and keys
for digits, letters and a few symbols, with Aa (capitals), Space, Del,
Clear, Cancel and Done along the bottom. While it is open it captures
every touch, click, key and typed character, so a real keyboard works
too: typing adds to the text, backspace deletes, enter is Done and
escape is Cancel.

  guikeyboard.open(root, "Search items", "", function(text)
    print("search for " .. text)
  end, { hint = function(text) return #find(text) .. " match" end })

The keys are as large as the screen allows: three lines high on a big
monitor, one line on a small one. A GUIInput touched on a monitor opens
one by itself (see GUIInput:setKeyboard).

opts: hint (function(text) returning a line to show under the text),
onChange (function(text) after every key), onCancel, maxLength.
--]]

GUIKeyboard = {}
GUIKeyboard.__index = GUIKeyboard
setmetatable(GUIKeyboard, {__index = guicomponent.GUIComponent})

-- The character keys, ten to a row.
Rows = {
    { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
    { "q", "w", "e", "r", "t", "y", "u", "i", "o", "p" },
    { "a", "s", "d", "f", "g", "h", "j", "k", "l", "_" },
    { "z", "x", "c", "v", "b", "n", "m", ":", ".", "-" },
}

-- The bottom row: label, short label, action, share of the width.
Actions = {
    { "Aa", "A", "shift", 2 },
    { "Space", "Spc", "space", 4 },
    { "Del", "<", "back", 3 },
    { "Clear", "Clr", "clear", 3 },
    { "Cancel", "X", "cancel", 4 },
    { "Done", "OK", "done", 4 },
}

function GUIKeyboard.new(title, text, opts)
    opts = opts or {}
    local object = guicomponent.GUIComponent.new()
    object.title = title or ""
    object.text = tostring(text or "")
    object.opts = opts
    object.keys = {}
    object.shift = false
    object.lit = nil        -- index of the key drawn pressed
    object.litTicks = 0
    object.open = false
    object.capturesKeys = true
    object.host = nil
    object:setBorder(false)
    object.ui = guikeyboardui.GUIKeyboardUI.new(object)
    setmetatable(object, GUIKeyboard)
    object:themed("backgroundColor", "surface")
    object:themed("textColor", "text")
    object:themed("titleColor", "accent")
    object:themed("titleTextColor", "accentText")
    object:themed("keyColor", "button")
    object:themed("keyTextColor", "buttonText")
    object:themed("pressColor", "buttonPress")
    object:themed("fieldColor", "field")
    object:themed("fieldTextColor", "fieldText")
    object:themed("mutedColor", "muted")
    object:themed("doneColor", "ok")
    object:themed("doneTextColor", "highlightText")
    object:themed("cancelColor", "danger")
    object:themed("cancelTextColor", "dangerText")
    local touch = function(e) object:touchHandler(e) end
    object:addMouseClickListener(touch)
    object:addMonitorTouchListener(touch)
    object:addKeyPressListener(function(e) object:keyHandler(e) end)
    object:addCharListener(function(e) object:charHandler(e) end)
    return object
end

-- The top level component (the root container) the keyboard covers.
local function topOf(c)
    while c.parent and c.parent.term do c = c.parent end
    return c
end

-- Work out the key sizes from the screen and place every key. Keys
-- are { x, y, w, h, label, char or action } relative to the keyboard.
function GUIKeyboard:build(top)
    local W, H = top.w, top.h
    local gap = 1
    local kw = math.floor((W - 2 - 9) / 10)
    if kw < 2 then
        gap = 0
        kw = math.floor((W - 2) / 10)
    end
    kw = math.max(1, math.min(kw, 5))
    local gridW = kw * 10 + gap * 9
    local w = math.min(W, math.max(gridW + 2, #self.title + 4))

    -- title, text, (hint), blank, five rows of keys, bottom margin
    local head = 3 + (self.opts.hint and 1 or 0)
    local kh, vgap = 1, 0
    for _, choice in ipairs({ { 3, 1 }, { 2, 1 }, { 1, 1 }, { 1, 0 } }) do
        if head + 5 * choice[1] + 4 * choice[2] + 1 <= H then
            kh, vgap = choice[1], choice[2]
            break
        end
    end
    local h = math.min(H, head + 5 * kh + 4 * vgap + 1)
    if h < head + 5 * kh + 4 * vgap + 1 then head = math.max(2, h - 5 * kh) end
    self.head = head

    local x0 = math.floor((w - gridW) / 2) + 1
    local keys = {}
    local y = head + 1
    for _, row in ipairs(Rows) do
        local x = x0
        for _, ch in ipairs(row) do
            keys[#keys + 1] = { x = x, y = y, w = kw, h = kh, char = ch }
            x = x + kw + gap
        end
        y = y + kh + vgap
    end
    -- the bottom row shares the same width out by each key's share
    local shares = 0
    for _, a in ipairs(Actions) do shares = shares + a[4] end
    local room = gridW - gap * (#Actions - 1)
    local x, used = x0, 0
    for i, a in ipairs(Actions) do
        local aw
        if i == #Actions then aw = room - used
        else aw = math.max(1, math.floor(room * a[4] / shares + 0.5)) end
        used = used + aw
        local label = (#a[1] <= aw) and a[1] or a[2]
        keys[#keys + 1] = { x = x, y = y, w = aw, h = kh, label = label, action = a[3] }
        x = x + aw + gap
    end
    self.keys = keys

    local bx = math.floor((W - w) / 2) + 1
    local by = math.floor((H - h) / 2) + 1
    guicomponent.GUIComponent.setPreferredBounds(self, bx, by, w, h)
end

-- What a key shows: its label, or its character (capital with shift).
function GUIKeyboard:labelOf(key)
    if key.label then return key.label end
    return self.shift and key.char:upper() or key.char
end

-- Open the keyboard over the screen that component is on. The event
-- that opened it (a touch on an input, or on a button whose onPress
-- opens it) is ignored, so it does not also press the key that happens
-- to be under it: openingEvent when it is given, and any touch in the
-- same moment otherwise.
function GUIKeyboard:show(component, openingEvent)
    if self.open then return end
    local top = topOf(component)
    self.host = top
    self.ignore = openingEvent
    self.shownAt = os.clock()
    self:build(top)
    -- Added by hand so a layout on the top component leaves it alone.
    table.insert(top.children, self)
    self:treeInit(top)
    self:setStarted(top.started)
    self.open = true
    self.previousCapture = guicomponent.getCapture(top)
    guicomponent.setCapture(self)
    guicomponent.addOverlay(self)
    self:repaint()
end

-- Take the keyboard away and redraw what it covered.
function GUIKeyboard:close()
    if not self.open then return end
    self.open = false
    guicomponent.removeOverlay(self)
    if guicomponent.getCapture(self) == self then guicomponent.setCapture(self.previousCapture, self) end
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

function GUIKeyboard:isOpen()
    return self.open
end

function GUIKeyboard:getText()
    return self.text
end

function GUIKeyboard:setText(text)
    self.text = tostring(text or "")
    self:repaint()
end

-- The hint line for the current text, or nil.
function GUIKeyboard:hintText()
    local hint = self.opts.hint
    if not hint then return nil end
    local ok, s = pcall(hint, self.text)
    return ok and s and tostring(s) or nil
end

function GUIKeyboard:changed()
    if self.opts.onChange then self.opts.onChange(self.text) end
    self:repaint()
end

-- Add typed text, up to maxLength.
function GUIKeyboard:type(s)
    local max = self.opts.maxLength
    if max and #self.text + #s > max then s = s:sub(1, math.max(0, max - #self.text)) end
    if s == "" then return end
    self.text = self.text .. s
    self:changed()
end

-- Do what a key does: type its character, or its action.
function GUIKeyboard:press(key)
    if not self.open or not key then return end
    if key.char then
        self:type(self.shift and key.char:upper() or key.char)
    elseif key.action == "space" then
        self:type(" ")
    elseif key.action == "back" then
        self.text = self.text:sub(1, -2)
        self:changed()
    elseif key.action == "clear" then
        self.text = ""
        self:changed()
    elseif key.action == "shift" then
        self.shift = not self.shift
        self:repaint()
    elseif key.action == "done" then
        self:close()
        if self.opts.onDone then self.opts.onDone(self.text) end
    elseif key.action == "cancel" then
        self:close()
        if self.opts.onCancel then self.opts.onCancel() end
    end
end

-- The key at a point relative to the keyboard, with its index.
function GUIKeyboard:keyAt(x, y)
    for i, k in ipairs(self.keys) do
        if x >= k.x and x < k.x + k.w and y >= k.y and y < k.y + k.h then return k, i end
    end
    return nil
end

function GUIKeyboard:touchHandler(e)
    if not self.open then return end
    if e == self.ignore or os.clock() == self.shownAt then return end
    local key, i = self:keyAt(e.x - self.ax + 1, e.y - self.ay + 1)
    if not key then return end
    self.lit, self.litTicks = i, 3
    self:press(key)
end

-- Draw a pressed key normally again after a moment.
function GUIKeyboard:update()
    guicomponent.GUIComponent.update(self)
    if self.lit then
        self.litTicks = self.litTicks - 1
        if self.litTicks <= 0 then
            self.lit = nil
            if self.open then self:repaint() end
        end
    end
end

function GUIKeyboard:keyHandler(e)
    if not self.open then return end
    if e.keycode == keys.enter then self:press({ action = "done" })
    elseif e.keycode == keys.escape then self:press({ action = "cancel" })
    elseif e.keycode == keys.backspace then self:press({ action = "back" }) end
end

function GUIKeyboard:charHandler(e)
    if not self.open then return end
    self:type(e.char)
end

-- Open a keyboard over component's screen to edit text; onDone gets
-- the new text. Returns the keyboard.
function open(component, title, text, onDone, opts)
    opts = opts or {}
    opts.onDone = onDone or opts.onDone
    local k = GUIKeyboard.new(title, text, opts)
    k:show(component, opts.openingEvent)
    return k
end
