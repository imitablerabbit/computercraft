--[[
Tree cutting script. The turtle is placed at the far left
of the farm with a chest placed to the left and behind it.
Left chest contains saplings and the chest behind will contain
the logs.
--]]

local w, h = 10, 6
local sleepTime = 60

local args = {...}

if #args > 3 then
  error("Usage: logger width height sleeptime")
end
if args[1] then
  w = tonumber(args[1])
end
if args[2] then
  h = tonumber(args[2])
end
if args[3] then
  sleepTime = tonumber(args[3])
end

function isSapling()
  local exists, data = turtle.inspect()
  if not exists then return false end
  if data.name == inventory.ItemSapling then
    return true
  else
    return false
  end
end

function plantSapling()
  if not inventory.select(inventory.ItemSapling) then
    return false
  end
  if not turtle.place() then
    return false
  end
  return true
end

function fellTree()
  local dh = 0
  for i = 1, h do
    turtle.dig()
    turtle.digUp()
    move.up()
    dh = dh + 1
  end
  for i = 1, dh do
    move.down()
  end
end

while true do
  print("Starting...")
  for x = 1, w do
    if turtle.detect() and not isSapling() then
      print("tree detected")
      fellTree()
      print("planting sapling")
      if not plantSapling() then
        print("error: unable to plant sapling")
      end
    else
      plantSapling()
    end
    move.right()
  end
  move.left(w)
  print("Sleeping...")
  os.sleep(sleepTime)
end
  
  
