--[[
GUIComponentUI is used to render the components inside
their bounds.
--]]

GUIComponentUI = {}
GUIComponentUI.__index = GUIComponentUI

function GUIComponentUI.new(component, model)
    local object = {
        component = component,
        model = model,
    }
    setmetatable(object, GUIComponentUI)
    return object
end

function GUIComponentUI:paint()
    if not self.component then
        return
    end
    if not self.component.term then
        return
    end
    
    local c = term.redirect(self.component.term)
    term.clear()
    w, h = term.getSize()
    paintutils.drawFilledBox(1, 1, w + 1, h + 1, self.component.backgroundColor)
    if self.component:hasBorder() then
        paintutils.drawBox(1, 1, w, h, self.component.borderColor)
    end
    term.redirect(c)
end

function GUIComponentUI:setComponent(c)
    self.component = c
end

function GUIComponentUI:setModel(m)
    self.model = m
end

-- The blit character for a colour ("0" to "f").
function blitColor(c)
    if colors.toBlit then return colors.toBlit(c) end
    return string.format("%x", math.floor(math.log(c) / math.log(2) + 0.5))
end

-- text cut or padded to exactly width characters, placed left, center
-- or right.
function fitText(text, width, align)
    text = tostring(text or "")
    if width <= 0 then return "" end
    if #text >= width then return text:sub(1, width) end
    local spare = width - #text
    if align == "center" then
        local left = math.floor(spare / 2)
        return string.rep(" ", left) .. text .. string.rep(" ", spare - left)
    elseif align == "right" then
        return string.rep(" ", spare) .. text
    end
    return text .. string.rep(" ", spare)
end
