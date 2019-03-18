--[[
Move is a module that will handle movement
for the turtle in a way that it can auto refuel.
--]]

-- Global variables
ShouldWaitForFuel = true

-- Move the turtle up. This function will wait for
-- fuel if it needs to. Returns the number of spaces that it
-- was actually able to move by.
function up(n)
  if not n then n = 1 end
  if n < 1 then error("n cannot be less than 1") end
  for i = 1, n do
    checkFuel()
    if not turtle.up() then
      return i-1
    end
  end
  return n
end

-- Move the turtle down. This function will wait for
-- fuel if it needs to. Returns the number of spaces that it
-- was actually able to move by.
function down(n)
  if not n then n = 1 end
  if n < 1 then error("n cannot be less than 1") end
  for i = 1, n do
    checkFuel()
    if not turtle.down() then
      return i-1
    end
  end
  return n
end

-- Move the turtle forward. This function will wait for
-- fuel if it needs to. Returns the number of spaces that it
-- was actually able to move by.
function forward(n)
  if not n then n = 1 end
  if n < 1 then error("n cannot be less than 1") end
  for i = 1, n do
    checkFuel()
    if not turtle.forward() then
      return i-1
    end
  end
  return n
end

-- Move the turtle back. This function will wait for
-- fuel if it needs to. Returns the number of spaces that it
-- was actually able to move by.
function back(n)
  if not n then n = 1 end
  if n < 1 then error("n cannot be less than 1") end
  for i = 1, n do
    checkFuel()
    if not turtle.back() then
      return i-1
    end
  end
  return n
end

-- Move the turtle left. This function will wait for
-- fuel if it needs to. Returns the number of spaces that it
-- was actually able to move by.
function left(n)
  if not n then n = 1 end
  if n < 1 then error("n cannot be less than 1") end
  turtle.turnLeft()
  for i = 1, n do
    checkFuel()
    if not turtle.forward() then
      turtle.turnRight()
      return i-1
    end
  end
  turtle.turnRight()
  return n
end

-- Move the turtle right. This function will wait for
-- fuel if it needs to. Returns the number of spaces that it
-- was actually able to move by.
function right(n)
  if not n then n = 1 end
  if n < 1 then error("n cannot be less than 1") end
  turtle.turnRight()
  for i = 1, n do
    checkFuel()
    if not turtle.forward() then
      turtle.turnLeft()
      return i-1
    end
  end
  turtle.turnLeft()
  return n
end

-- Check the fuel level and wait until the user tells
-- us there is some fuel.
function checkFuel()
  if turtle.getFuelLevel() == 0 then 
    print("no fuel to complete move")
    if ShouldWaitForFuel then
      inventory.waitForFuel()
    end
  end
end

-- Moves the turtle x and y. x is a left and right movement and y
-- is a forward and back movement. Positive values are forward and
-- right. Negative values are back and left. This function will start
-- by moving the turtle forward, then back, then right, then left.
function move(x, y)
  if y > 0 then
    forward(y)
  elseif y < 0 then
    back(-y)
  end
  if x > 0 then
    right(x)
  elseif x < 0 then
    left(-x)
  end
end
  