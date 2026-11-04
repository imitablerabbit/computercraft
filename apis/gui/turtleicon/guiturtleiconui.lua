GUITurtleIconUI = {}
GUITurtleIconUI.__index = GUITurtleIconUI
setmetatable(GUITurtleIconUI, {__index = guicomponentui.GUIComponentUI})

-- The picture. Each character is a key into the palette below; a space is
-- the tile background. The pickaxe (p, h) is only shown while busy.
local picture = {
    "  bbbbb   ",
    " bBBBBBb p",
    " bBeBeBb h",
    " bBBBBBb h",
    "  d d d   ",
}
local pictureWidth = #picture[1]
local pictureHeight = #picture

-- Body colour and state text for each state.
local states = {
    idle    = { body = colors.lime,   eye = colors.white, text = "IDLE" },
    busy    = { body = colors.orange, eye = colors.white, text = "WORKING" },
    error   = { body = colors.red,    eye = colors.black, text = "ERROR" },
    offline = { body = colors.gray,   eye = colors.black, text = "OFFLINE" },
}
local spinner = { "|", "/", "-", "\\" }

-- Convert a colors.* value to the hex digit used by term.blit.
local function blitChar(color)
    local n = math.floor(math.log(color) / math.log(2) + 0.5)
    return string.format("%x", n)
end

function GUITurtleIconUI.new(component)
    local object = guicomponentui.GUIComponentUI.new(component, nil)
    setmetatable(object, GUITurtleIconUI)
    return object
end

-- Draw the picture with its top left corner at x, y.
function GUITurtleIconUI:paintPicture(x, y, state)
    local look = states[state] or states.offline
    local bg = self.component.backgroundColor
    local palette = {
        [" "] = bg,
        b = colors.gray,
        B = look.body,
        e = look.eye,
        d = colors.black,
        p = colors.lightGray,
        h = colors.brown,
    }
    local showTool = state == "busy"
    for row, line in ipairs(picture) do
        local text, fg, back = "", "", ""
        for col = 1, #line do
            local key = line:sub(col, col)
            if (key == "p" or key == "h") and not showTool then key = " " end
            local ch = " "
            if key == "e" and state == "error" then ch = "x" end
            text = text .. ch
            fg = fg .. blitChar(colors.white)
            back = back .. blitChar(palette[key] or bg)
        end
        term.setCursorPos(x, y + row - 1)
        term.blit(text, fg, back)
    end
end

-- Write text centred on row y, clipped to the inside of the border.
function GUITurtleIconUI:writeCentered(y, text, color, w)
    local inner = w - 2
    if #text > inner then text = text:sub(1, inner) end
    local x = math.floor((w - #text) / 2) + 1
    term.setCursorPos(x, y)
    term.setTextColor(color)
    term.setBackgroundColor(self.component.backgroundColor)
    term.write(text)
end

function GUITurtleIconUI:paint()
    guicomponentui.GUIComponentUI.paint(self)
    if not self.component or not self.component.term then return end
    local c = term.redirect(self.component.term)
    local w, h = term.getSize()
    local info = self.component.info or {}
    local state = self.component:getState()
    local look = states[state] or states.offline
    local label = info.label or ("#" .. tostring(info.id or "?"))

    local stateText = look.text
    if state == "busy" then
        local frame = self.component.frame % #spinner + 1
        local job = (info.job or look.text):upper():sub(1, w - 4) -- room for the spinner
        stateText = job .. " " .. spinner[frame]
    end

    if h >= guiturtleicon.GUITurtleIcon.MinHeight and w >= guiturtleicon.GUITurtleIcon.MinWidth then
        local px = math.floor((w - pictureWidth) / 2) + 1
        self:paintPicture(px, 2, state)
        self:writeCentered(2 + pictureHeight, label, self.component.textColor, w)
        self:writeCentered(3 + pictureHeight, stateText, look.body, w)
    else
        -- Too small for the picture: label on one line, state on the next.
        local y = math.max(2, math.floor(h / 2))
        self:writeCentered(y, label, self.component.textColor, w)
        if y + 1 < h then
            self:writeCentered(y + 1, stateText, look.body, w)
        end
    end
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    term.redirect(c)
end
