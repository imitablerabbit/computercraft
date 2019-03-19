local Window = {
}

function new()
  w = {}
  setmetatable(w, Window)
  Window.__index = Window
  return w
end

