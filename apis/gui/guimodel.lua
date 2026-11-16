--[[
GUIModel is a representation of a model used to store and
handle the state of GUI objects. Models can have observers
attached to them.    
--]]
GUIModel = {}
GUIModel.__index = GUIModel

-- Constructor
function GUIModel.new()
    local object = {
        listeners = {}
    }
    setmetatable(object, GUIModel)
    return object
end

-- GUIModel Observers
function GUIModel:addEventListeners(l)
    table.insert(self.listeners, l)
end

function GUIModel:removeEventListeners(l)
    for i, l2 in pairs(self.listeners) do
        if l == l2 then
            table.remove(self.listeners, i)
        end
    end
end

function GUIModel:triggerEvent(e)
    if not e then error("missing GUIEvent") end
    if not e.type then error("missing event type") end
    for i, l in pairs(self.listeners) do
        l(e)
    end
end