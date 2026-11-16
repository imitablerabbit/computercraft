--[[
GUIScrollPane shows a window onto content taller than itself, with a
scrollbar down the right hand side when it is needed: arrows at the
top and bottom scroll one row, the track pages, and the thumb shows
where you are. The mouse wheel scrolls it on a computer screen.

setContent gives it the component to scroll, usually a container with
a GUIBoxLayout; its height comes from its preferred size (what its
layout needs) or the bounds it was given. Clicks and touches reach the
content only inside the pane, so rows scrolled out of sight cannot be
pressed.
--]]

GUIScrollPane = {}
GUIScrollPane.__index = GUIScrollPane
setmetatable(GUIScrollPane, {__index = guicomponent.GUIComponent})

function GUIScrollPane.new()
    local object = guicomponent.GUIComponent.new()
    object.content = nil
    object.scroll = 0
    object.barShown = false
    object.contentH = 0
    object.backgroundColor = colors.black
    object.barColor = colors.gray
    object.thumbColor = colors.lightGray
    object.arrowColor = colors.white
    object:setBorder(false)
    object.ui = guiscrollpaneui.GUIScrollPaneUI.new(object)
    setmetatable(object, GUIScrollPane)
    return object
end

function GUIScrollPane:setContent(c)
    if self.content then self:remove(self.content) end
    self.content = c
    self.scroll = 0
    guicomponent.GUIComponent.add(self, c)
    self:layoutContent()
end

function GUIScrollPane:getContent()
    return self.content
end

function GUIScrollPane:treeInit(p)
    guicomponent.GUIComponent.treeInit(self, p)
    self:layoutContent()
end

function GUIScrollPane:setBounds(x, y, w, h)
    guicomponent.GUIComponent.setBounds(self, x, y, w, h)
    self:layoutContent()
end

function GUIScrollPane:setPreferredBounds(x, y, w, h)
    guicomponent.GUIComponent.setPreferredBounds(self, x, y, w, h)
    self:layoutContent()
end

-- The viewport: the pane minus the scrollbar column when shown.
function GUIScrollPane:viewportSize()
    return self.w - (self.barShown and 1 or 0), self.h
end

function GUIScrollPane:maxScroll()
    return math.max(0, self.contentH - self.h)
end

-- Size the content and place it according to the scroll position.
function GUIScrollPane:layoutContent()
    local c = self.content
    if not c then return end
    local _, ph = c:getPreferredSize()
    self.contentH = math.max(ph or c.h, 1)
    self.barShown = self.contentH > self.h
    self.scroll = math.max(0, math.min(self.scroll, self:maxScroll()))
    local vw = self.w - (self.barShown and 1 or 0)
    c:setBounds(1, 1 - self.scroll, vw, math.max(self.contentH, self.h))
    self:repaint()
end

function GUIScrollPane:getScroll()
    return self.scroll
end

function GUIScrollPane:scrollTo(n)
    self.scroll = math.max(0, math.min(math.floor(n), self:maxScroll()))
    local c = self.content
    if c then c:setBounds(1, 1 - self.scroll, c.w, c.h) end
    self:repaint()
end

function GUIScrollPane:scrollBy(n)
    self:scrollTo(self.scroll + n)
end

-- Rows of the track the thumb covers (within 2 .. h-1).
function GUIScrollPane:thumb()
    local track = self.h - 2
    if track < 1 or self.contentH <= self.h then return 2, 1 + track end
    local size = math.max(1, math.floor(track * self.h / self.contentH))
    local maxTop = track - size
    local top = math.floor(maxTop * self.scroll / self:maxScroll() + 0.5)
    return 2 + top, 2 + top + size - 1
end

-- Clicks and touches: the scrollbar scrolls, the viewport passes the
-- event to the content, anything else is ignored.
function GUIScrollPane:handlePointer(e, forward)
    local x, y = e.x - self.ax + 1, e.y - self.ay + 1
    if x < 1 or x > self.w or y < 1 or y > self.h then return end
    if self.barShown and x == self.w then
        if y == 1 then self:scrollBy(-1)
        elseif y == self.h then self:scrollBy(1)
        else
            local top, bottom = self:thumb()
            if y < top then self:scrollBy(-self.h) elseif y > bottom then self:scrollBy(self.h) end
        end
        return
    end
    forward()
end

function GUIScrollPane:triggerMouseClickEvent(e)
    self:handlePointer(e, function()
        for i, l in pairs(self.mouseClickListeners) do l(e) end
        if self.content then self.content:triggerMouseClickEvent(e) end
    end)
end

function GUIScrollPane:triggerMonitorTouchEvent(e)
    self:handlePointer(e, function()
        for i, l in pairs(self.monitorTouchListeners) do l(e) end
        if self.content then self.content:triggerMonitorTouchEvent(e) end
    end)
end

function GUIScrollPane:triggerMouseScrollEvent(e)
    local x, y = e.x - self.ax + 1, e.y - self.ay + 1
    if x < 1 or x > self.w or y < 1 or y > self.h then return end
    self:scrollBy(e.direction)
end
