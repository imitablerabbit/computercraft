-- Dig the block in front until there is nothing left.
function dig()
  local limit = 10
  local attempts = 0
  while turtle.detect() do
    if attempts > limit then -- If there is something there but cant dig it
      return false
    end
    if not turtle.dig() then
      attempts = attempts + 1
    end
  end
  return true
end

-- Dig the block above until there is nothing left.
function digUp()
  local limit = 10
  local attempts = 0
  while turtle.detectUp() do
    if attempts > limit then
      return false
    end
    if not turtle.digUp() then
      attempts = attempts + 1
    end
  end
  return true
end

-- Dig the block above until there is nothing left.
function digDown()
  local limit = 10
  local attempts = 0
  while turtle.detectDown() do
    if attempts > limit then
      return false
    end
    if not turtle.digDown() then
      attempts = attempts + 1
    end
  end
  return true
end

-- Mine a single 1x2 block infront of the turtle. If shouldReturn
-- is true then the turtle will return to its original position.
-- This function will consume 1 fuel when shouldReturn is false 
-- and 2 fuel when it is true.
function mineOnce()
  if not dig() then 
    return false
  end
  if not move.forward() then
    return false
  end
  if not digUp() then
    move.back() -- last restort to go back, try and keep it consistent
    return false
  end
  return true
end

-- Mine a single line in front of the turtle. This assumes
-- that the turtle already has fuel and that there are torches
-- in the inventory.
function mineLine(length, torch, tDistance)
  if not length then length = 64 end
  if not torch then torch = false end
  if not tDistance then tDistance = 10 end
  local distance = 0
  local lastTorch = 0
  local completed = true
  while distance < length do
    if mineOnce() then
      distance = distance + 1
      lastTorch = lastTorch + 1
    else
      break
    end
    if torch and lastTorch > tDistance then
      if not move.back() then
        break
      end
      distance = distance - 1
      if inventory.placeTorch() then
        lastTorch = 0
      end
      if not move.forward() then
        break
      end
      distance = distance + 1
    end
  end
  return distance
end

-- Mine out a new strip mine starting position. Returns
-- the actual distance travelled by the turtle.
function newMine(sep)
  if not sep then sep = 3 end
  turtle.turnRight()
  local distance = 0
  for i = 1, sep do
    if not mineOnce() then
      break
    end
    distance = distance + 1
  end
  turtle.turnLeft()
  return distance
end

-- Start stripmining multiple lines. 
function stripMine(n, sep, length, torch, tDistance)
  if not n then n = 5 end
  local dx = 0
  for i = 1, n do
    local actualSep = newMine(sep)
    dx = dx + actualSep
    if actualSep ~= sep then
      break
    end
    local dy = mineLine(length, torch, tDistance)
    move.back(dy)
    move.left(dx) -- Go back to chest
    turtle.turnLeft()
    local torchSlots = inventory.find("minecraft:torch")
    inventory.empty(torchSlots) -- blacklisted from empty
    turtle.turnRight()
    move.right(dx)
  end
  move.left(dx)
end

-- Returns the fuel level required to complete a full mineLine.
function getRequiredMineLineFuelLevels(length, torch, tDistance)
  if not length then length = mineLength end
  if not torch then torch = placeTorches end
  if not tDistance then tDistance = torchDistance end
  local torchFuel = math.ceil(2 * (length / tDistance))
  local required = (length * 2) + torchFuel
  return required
end

-- Returns the fuel level required to complete a new mine.
function getRequiredNewMineFuelLevels(sep)
  return sep -- We only move forward `sep` times when creating a new mine
end