-- Dig the block in front until there is nothing left.
function dig()
  local limit = 10
  while turtle.detect() do
    if attempts > limit then
      error("failed to dig "..limit.." times when block is present")
    end
    if not turtle.dig() then
      attempts = attempts + 1
    end
  end
end

-- Dig the block above until there is nothing left.
function digUp()
  local limit = 10
  while turtle.detectUp() do
    if attempts > limit then
      error("failed to dig up "..limit.." times when block is present")
    end
    if not turtle.digUp() then
      attempts = attempts + 1
    end
  end
end

-- Mine a single 1x2 block infront of the turtle. If shouldReturn
-- is true then the turtle will return to its original position.
-- This function will consume 1 fuel when shouldReturn is false 
-- and 2 fuel when it is true.
function mineOnce()
  if not shouldReturn then shouldReturn = false end
  dig()
  if not move.forward() then
    print("error: unable to move forward after digging")
    return false
  end
  digUp()
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
  -- Mine the line in front and place torches
  while distance < length do
    if mineOnce() then
      distance = distance + 1
      lastTorch = lastTorch + 1
    else
      print("warn: unable to complete a full mine")
      break
    end
    if torch and lastTorch > tDistance then
      print("info: placing torch")
      move.back()
      if placeTorch() then
        lastTorch = 0
      else
        print("warn: failed to place torch")
      end
      move.forward()
    end
  end
  move.back(distance)
  return true
end

-- Mine out a new strip mine starting position.
function newMine(sep)
  if not sep then sep = 3 end
  turtle.turnRight()
  for i = 1, sep do
    mineOnce()
  end
  turtle.turnLeft()
end

-- Start stripmining multiple lines. 
function stripMine(n, sep, length, torch, tDistance)
  if not n then n = 5 end
  local xd = 0
  for i = 1, n do
    newMine(sep)
    xd = xd + sep
    mineLine(length, torch, tDistance)
    move.move(-xd, 0) -- Go back to chest
    turtle.turnLeft()
    local torchSlots = inventory.find("minecraft:torch")
    inventory.empty(torchSlots) -- blacklisted from empty
    turtle.turnRight()
    move.move(xd, 0)
  end
  move(-xd, 0) -- Go back to chest
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