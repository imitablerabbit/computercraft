GUIRootContainer = guicomponent.GUIComponent:new()

function GUIRootContainer:new(t)
    local object = guicomponent.GUIComponent:new(t)
    self.__index = self
    setmetatable(object, self)

    -- testing mouse click 
    local pe = function(e)
        print("event: "..e.type)
    end
    object:addMouseClickListener(pe)

    return object
end

