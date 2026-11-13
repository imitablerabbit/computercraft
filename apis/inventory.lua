--[[
Inventory is an api that helps to manage a turtles
inventory.
--]]

--[[
Global Module variables
--]]

Min = 1
Max = 16

-- Item names used to search the inventory
ItemTorch = "minecraft:torch"
ItemSapling = "minecraft:sapling"
ItemRubberSapling = "ic2:sapling"

-- Items the turtle never burns as fuel (item names, or slot numbers).
-- Kept in FuelBlacklistFile so it survives reboots; turtle control
-- edits it through the agent.
FuelBlacklist = {}
FuelBlacklistFile = "fuel_blacklist"

-- Where a chest can sit relative to the turtle's position and heading.
-- Programs that empty themselves take one of these as an argument.
ChestSides = { "left", "right", "behind", "below", "above" }
DefaultChestSide = "left"

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
      table.insert(found, i)
    end
  end
  return found
end

-- Select the first slot that contains the item type
-- specified.
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
  if not blacklist then blacklist = FuelBlacklist end
  local s = turtle.getSelectedSlot()
  for slot = Min, Max do
    local skip = false
    for i, b in pairs(blacklist) do
      if type(b) == "string" then
        local data = turtle.getItemDetail(slot)
        if data and data.name == b then
          skip = true
        end
      elseif type(b) == "number" then
        if b == slot then
          skip = true
        end
      end
    end
    if not skip then
      turtle.select(slot)
      turtle.refuel()
    end
  end
  turtle.select(s)
end

-- Fuel blacklist housekeeping.

function loadFuelBlacklist()
  if fs.exists(FuelBlacklistFile) then
    local f = fs.open(FuelBlacklistFile, "r")
    if f then
      local list = textutils.unserialize(f.readAll() or "")
      f.close()
      if type(list) == "table" then FuelBlacklist = list end
    end
  end
  return FuelBlacklist
end

function saveFuelBlacklist()
  local f = fs.open(FuelBlacklistFile, "w")
  if not f then return false end
  f.write(textutils.serialize(FuelBlacklist))
  f.close()
  return true
end

function isFuelBlacklisted(name)
  for i, b in ipairs(FuelBlacklist) do
    if b == name then return true end
  end
  return false
end

-- Never burn this item. Returns false when it is already listed.
function addFuelBlacklist(name)
  if type(name) ~= "string" or name == "" or isFuelBlacklisted(name) then return false end
  table.insert(FuelBlacklist, name)
  saveFuelBlacklist()
  return true
end

-- Allow burning this item again. Returns false when it was not listed.
function removeFuelBlacklist(name)
  for i, b in ipairs(FuelBlacklist) do
    if b == name then
      table.remove(FuelBlacklist, i)
      saveFuelBlacklist()
      return true
    end
  end
  return false
end

loadFuelBlacklist()

-- Sleeps until fuel is put into the turtle. Adding items fires a
-- turtle_inventory event, so the turtle refuels and carries on by
-- itself; pressing space does the same. Raises a "fuel" alert while
-- waiting so turtle control shows the turtle needs help.
function waitForFuel(blacklist)
  print("waiting for fuel...")
  print("add fuel to the turtle (or add it and press space)")
  alert.raise("fuel", "out of fuel, add fuel to the turtle")
  while true do
    local event, key = os.pullEvent()
    if (event == "key" and key == keys.space) or event == "turtle_inventory" then
      refuelAll(blacklist)
      local fuel = turtle.getFuelLevel()
      if fuel == "unlimited" or fuel > 0 then break end
    end
  end
  alert.clear("fuel")
  print("fuel level is now " .. tostring(turtle.getFuelLevel()))
end

-- Completely empty the turtle inventory. If there is a
-- chest in front of it the turtle will only empty its items
-- if there is enough room in the chest to store them.
-- `ignore` contains a list of slots to ignore. These slots will
-- not be emptied. `drop` is the turtle function used to drop
-- (turtle.drop by default, or dropUp / dropDown).
function empty(ignore, drop)
  if not ignore then ignore = {} end
  if not drop then drop = turtle.drop end
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
        if not drop() then
          droppedAll = false
        end
      end
    end
  end
  turtle.select(s)
  return droppedAll
end

-- Is this one of ChestSides?
function isChestSide(side)
  for i, s in ipairs(ChestSides) do
    if s == side then return true end
  end
  return false
end

-- Turn to face a chest side. Returns the detect and drop functions
-- for that side, a function that turns back the way we were, and the
-- suck function for taking items out of the chest.
function faceChestSide(side)
  if side == "left" then
    turtle.turnLeft()
    return turtle.detect, turtle.drop, turtle.turnRight, turtle.suck
  elseif side == "right" then
    turtle.turnRight()
    return turtle.detect, turtle.drop, turtle.turnLeft, turtle.suck
  elseif side == "behind" then
    turtle.turnLeft()
    turtle.turnLeft()
    return turtle.detect, turtle.drop, function() turtle.turnRight(); turtle.turnRight() end, turtle.suck
  elseif side == "below" then
    return turtle.detectDown, turtle.dropDown, function() end, turtle.suckDown
  elseif side == "above" then
    return turtle.detectUp, turtle.dropUp, function() end, turtle.suckUp
  end
  error("unknown chest side " .. tostring(side))
end

-- Empty the inventory into the chest on a side of the turtle and turn
-- back. `ignore` lists slots to keep. Returns true when everything was
-- dropped, otherwise false and the reason (no chest there, or full).
function dumpTo(side, ignore)
  side = side or DefaultChestSide
  if not isChestSide(side) then return false, "unknown chest side " .. tostring(side) end
  local detect, drop, back = faceChestSide(side)
  local ok, reason = true, nil
  if not detect() then
    ok, reason = false, "no chest " .. side
  elseif not empty(ignore, drop) then
    ok, reason = false, "the chest " .. side .. " is full"
  end
  back()
  return ok, reason
end

-- Search for and place a torch from the turtles inventory
function placeTorch()
  currentSlot = turtle.getSelectedSlot()
  -- Change to the torch slot
  if not inventory.select(ItemTorch) then
    alert.raise("torches", "no torches left")
    return false
  end
  alert.clear("torches")
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