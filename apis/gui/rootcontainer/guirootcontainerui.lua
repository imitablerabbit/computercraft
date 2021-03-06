GUIRootContainerUI = {}
GUIRootContainerUI.__index = GUIRootContainerUI
setmetatable(GUIRootContainerUI, {__index = guicomponentui.GUIComponentUI})

function GUIRootContainerUI.new(component)
    local object = guicomponentui.GUIComponentUI.new(component, nil)
    setmetatable(object, GUIRootContainerUI)
    return object
end

function GUIRootContainerUI:paint()
    guicomponentui.GUIComponentUI.paint(self)
    if not self.component then
        return
    end
    if not self.component.term then
        return
    end
    local t = term.redirect(self.component.term)
    local w, h = term.getSize()
    if self.component:hasDecorations() then
        paintutils.drawLine(1, 1, w, 1, self.component.borderColor)
        if self.component.closeButton then
            self.component.closeButton:repaint()
        end
        term.setCursorPos(1, 1)
        term.setTextColor(self.component.textColor)
        term.write(self.component.title)
    end
    term.redirect(t)
end
