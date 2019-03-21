local GUIRootContainer = GUIComponent:new{}

function GUIRootContainer:new()
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

