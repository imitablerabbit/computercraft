--[[
Inventory is an api that helps to manage a turtles
inventory.
--]]

--[[
Global Module variables
--]]

Min = 1
Max = 16

ItemTorch = "minecraft:torch"
ItemSapling = "minecraft:sapling"

--[[
Inventory API
--]]

-- Find the inventory slot that contains the item name.
-- A minecraft item name is in the format of modname:item_name,
-- e.g. minecraft:wool, minecraft:coal, computercraft:turtle_advanced.
-- If in doubt put the item in a turtle inventory and use the
-- turtle.getItemDetail() function. This function will return a
-- table of all the slots the item was found in.
function find(item)
  if not item then error("item name expected") end
  local found = {}
  for i = Min, Max do
    local data = turtle.getItemDetail(i)
    if data and data.name == item then
      table.insert(found, data)
    end
  end
  return found
end

function select(item)
  local slots = find(item)
  if not slots then return false end
  for k, v in pairs(slots) do
    if turtle.select(v) then return true end
  end
  return false
end

-- Does the turtle have any free space in its inventory?
-- This function will loop over all of the slots and check
-- if there is at least 1 completely empty slot. If there is
-- an empty slot then there is room to pick up a new item.
function anyFreeSpace()
  for i = Min, Max do
    if turtle.getItemCount(i) == 0 then
      return true
    end
  end
  return false
end

-- Refuel the turtle with all fuel found in the inventory.
function refuelAll(blacklist)
  if not blacklist then blacklist = {} end
  local s = turtle.getSelectedSlot()
  for slot = Min, Max do
    local skip = false
    for i, ignoreSlot in pairs(blacklist) do
      if ignoreSlot == slot then
        skip = true
      end
    end
    if not skip then
      turtle.select(slot)
      turtle.refuel()
    end
  end
  turtle.select(s)
end

-- Sleeps until the user adds some fuel into the turtle
-- and presses a button. The turtle will immediately
-- refuel with all of the fuel placed inside it.
function waitForFuel()
  print("waiting for fuel...")
  os.pullEvent("key")
  refuelAll()
end

-- Completely empty the turtle inventory. If there is a
-- chest in front of it the turtle will only empty its items
-- if there is enough room in the chest to store them.
-- `ignore` contains a list of slots to ignore. These slots will
-- not be emptied.
function empty(ignore)
  if not ignore then ignore = {} end
  local s = turtle.getSelectedSlot()
  local droppedAll = true
  for slot = Min, Max do
    local skip = false
    for i, ignoreSlot in pairs(ignore) do
      if ignoreSlot == slot then
        skip = true
      end
    end
    if not skip then
      turtle.select(slot)
      if turtle.getItemCount() > 0 then
        if not turtle.drop() then
          droppedAll = false
        end
      end
    end
  end
  turtle.select(s)
  return droppedAll
end

function placeTorch()
  currentSlot = turtle.getSelectedSlot()
  -- Change to the torch slot
  if not inventory.select(ItemTorch) then
    return false
  end
  -- Place the torch on the block above the turtle
  if not turtle.placeUp() then
    print("warn: unable to place torch")
    turtle.select(currentSlot)
    return false
  end
  -- Change back to previous slot
  if not turtle.select(currentSlot) then
    print("error: unable to select slot "..currentSlot)
    return false
  end
  return true
end