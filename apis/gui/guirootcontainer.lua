local GUIRootContainer = GUIComponent:new{}

function GUIRootContainer:new(t)
    t = t or term.current()
    width, height = t:getSize()
    w = window.create(t, self.x, self.y, width, height)

    local object = {
        term = w,
        w = width,
        h = height,
    }
    self.__index = self
    setmetatable(object, self)

    -- testing mouse click 
    local pe = function(e)
        print("event: "..e.type)
    end
    object:addMouseClickListener(pe)

    return object
end

function GUIRootContainer:setPrefferedBounds(x, y, w, h)
    self.term:reposition(x, y, w, h)
end