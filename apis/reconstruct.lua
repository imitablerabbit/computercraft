--[[
Reconstruct feeds blocks one at a time to a machine that changes the
block in front of the turtle when it gets a redstone pulse, then mines
the result. The first use is an Actually Additions atomic reconstructor
with a lens of the miner turning netherrack into nether quartz ore,
nether gold ore and, now and then, ancient debris; any machine that
turns the block in front of the turtle into something else when pulsed
works the same way, with any block it accepts.

Layout seen from above, the turtle T facing up the page:

      M .          M = the machine, aimed at the block space in front
    = T C          of the turtle; = redstone from the turtle's left
      I            face to the machine; I = input chest behind;
                   C = output chest on the right

The turtle takes one stack out of the input chest, then for every block
in it: places the block in front, pulses the redstone, waits a moment,
checks that the block changed (pulsing again if not) and digs it. When
the stack is used up it turns to the output chest, empties itself and
takes the next stack. It never moves, so it needs no fuel.

Every side can be changed. Chest sides are inventory.ChestSides, the
pulse side is a redstone side of the turtle (left, right, back, top,
bottom; behind, above and below are accepted too). The turtle faces
front while it pulses and places, so all sides are relative to how it
was placed.

Alerts: input (input chest missing or empty), chest (output chest
missing or full), place (the item cannot be placed), machine (blocks
keep not changing: no power, bad aim, wrong lens). The turtle waits and
tries again while an alert is up, so fixing the setup lets it carry on.
--]]

Defaults = { input = "behind", output = "right", pulse = "left", stacks = 0, delay = 0.5 }
PulseSides = { "left", "right", "back", "top", "bottom" }
PulseLength = 0.2 -- seconds the redstone output stays on
Retries = 2       -- extra pulses for a block that did not change
StallLimit = 4    -- unchanged blocks in a row before the machine alert
RetryWait = 10    -- seconds between tries while an alert is up
WorkSlot = 1      -- where the stack being worked on goes

local stats

-- Redstone sides use the game's names; chest sides use ours.
local toPulseSide = { behind = "back", above = "top", below = "bottom" }
local toChestSide = { back = "behind", top = "above", bottom = "below" }

function isPulseSide(side)
  for i, s in ipairs(PulseSides) do
    if s == side then return true end
  end
  return false
end

local function shortName(name)
  if type(name) ~= "string" then return tostring(name) end
  return (name:gsub("^minecraft:", ""))
end

--[[
Steps
--]]

local function pulse(side)
  redstone.setOutput(side, true)
  os.sleep(PulseLength)
  redstone.setOutput(side, false)
end

local function blockAhead()
  local ok, data = turtle.inspect()
  if ok and type(data) == "table" then return data.name end
  return nil
end

-- Raise an alert and give whoever fixes it time before trying again.
local function waitFor(kind, message)
  print(message)
  alert.raise(kind, message)
  os.sleep(RetryWait)
end

-- The first slot with something in it, or nil.
local function firstFilled()
  for slot = inventory.Min, inventory.Max do
    if turtle.getItemCount(slot) > 0 then return slot end
  end
  return nil
end

-- Empty everything but keepSlot into the output chest, waiting for a
-- chest to appear or be emptied when that fails.
local function dumpAll(outputSide, keepSlot)
  while true do
    local ok, reason = inventory.dumpTo(outputSide, keepSlot and { keepSlot } or nil)
    if ok then
      alert.clear("chest")
      stats.dumps = stats.dumps + 1
      return true
    end
    waitFor("chest", reason .. ", waiting")
  end
end

-- Pull one stack out of the input chest into the work slot. Waits for
-- the chest to be filled when it is empty. Returns the slot, item name
-- and count.
local function takeStack(inputSide)
  while true do
    turtle.select(WorkSlot)
    local detect, drop, back, suck = inventory.faceChestSide(inputSide)
    local there = detect()
    local got = there and suck()
    back()
    if got then
      alert.clear("input")
      local slot = (turtle.getItemCount(WorkSlot) > 0) and WorkSlot or firstFilled()
      local item = turtle.getItemDetail(slot)
      return slot, item.name, item.count
    elseif not there then
      waitFor("input", "no input chest " .. inputSide .. ", waiting")
    else
      waitFor("input", "the input chest " .. inputSide .. " is empty, waiting")
    end
  end
end

-- Is the stack being worked on still in its slot? Once the last block
-- is placed the slot is empty, and what the turtle digs next lands in
-- it, so the slot holding something is not enough.
local function stackLeft(slot, name)
  local item = turtle.getItemDetail(slot)
  return item ~= nil and item.name == name
end

-- Put a block from the slot in front of the turtle. Clears whatever is
-- there first and waits when the item will not go down at all.
local function placeBlock(slot, name)
  turtle.select(slot)
  local tries = 0
  while not turtle.place() do
    if not stackLeft(slot, name) then return false end
    if turtle.detect() then
      print("something is in front, digging it first")
      turtle.dig()
    else
      tries = tries + 1
      if tries >= 3 then
        waitFor("place", "cannot place " .. shortName(name) .. " in front, waiting")
        tries = 0
      end
    end
    turtle.select(slot)
  end
  alert.clear("place")
  return true
end

-- Pulse the machine until the block in front is something else. Gives
-- up after Retries extra pulses unless the machine looks stalled, in
-- which case it keeps trying with the alert up. Returns the new block
-- name (nil when it vanished) and whether it changed.
local function changeBlock(pulseSide, delay, before)
  for attempt = 0, Retries do
    pulse(pulseSide)
    os.sleep(delay)
    local after = blockAhead()
    if after ~= before then return after, true end
  end
  stats.stalled = stats.stalled + 1
  if stats.stalled < StallLimit then return before, false end
  while true do
    waitFor("machine", "the machine is not changing blocks (no power?), waiting")
    pulse(pulseSide)
    os.sleep(delay)
    local after = blockAhead()
    if after ~= before then
      alert.clear("machine")
      stats.stalled = 0
      return after, true
    end
  end
end

-- Dig the block in front, making room for what it drops first.
local function digBlock(outputSide, keepSlot)
  if not inventory.anyFreeSpace() then dumpAll(outputSide, keepSlot) end
  local tries = 0
  while turtle.detect() do
    if turtle.dig() then break end
    tries = tries + 1
    if tries >= 3 then
      waitFor("dig", "cannot dig the block in front, waiting")
      tries = 0
    end
  end
  alert.clear("dig")
end

-- "nether_quartz_ore 55, nether_gold_ore 8, ancient_debris 1"
local function tallyText(tally)
  local names = {}
  for name in pairs(tally) do table.insert(names, name) end
  table.sort(names, function(a, b)
    if tally[a] ~= tally[b] then return tally[a] > tally[b] end
    return a < b
  end)
  local parts = {}
  for i, name in ipairs(names) do parts[i] = shortName(name) .. " " .. tally[name] end
  return table.concat(parts, ", ")
end

--[[
The loop
--]]

-- Check the options and fill in defaults. Returns the options or nil
-- and a reason.
function checkOptions(opts)
  opts = opts or {}
  local o = {
    input = opts.input or Defaults.input,
    output = opts.output or Defaults.output,
    pulse = toPulseSide[opts.pulse or Defaults.pulse] or opts.pulse or Defaults.pulse,
    stacks = tonumber(opts.stacks or Defaults.stacks),
    delay = tonumber(opts.delay or Defaults.delay),
  }
  if not inventory.isChestSide(o.input) then return nil, "unknown input chest side " .. tostring(o.input) end
  if not inventory.isChestSide(o.output) then return nil, "unknown output chest side " .. tostring(o.output) end
  if not isPulseSide(o.pulse) then return nil, "unknown pulse side " .. tostring(o.pulse) end
  if o.input == o.output then return nil, "the input and output chests are both " .. o.input end
  local pulseChest = toChestSide[o.pulse] or o.pulse
  if pulseChest == o.input or pulseChest == o.output then
    return nil, "the pulse side " .. o.pulse .. " is where a chest is"
  end
  if not o.stacks or o.stacks < 0 then return nil, "stacks must be 0 (no limit) or more" end
  if not o.delay or o.delay < 0 then return nil, "delay must be 0 or more seconds" end
  return o
end

-- Run the loop. opts: input, output (inventory.ChestSides), pulse
-- (PulseSides), stacks (how many stacks to do, 0 for no limit) and
-- delay (seconds between the pulse and checking the block). Returns
-- true, or false and a reason when the options are wrong.
function run(opts)
  local o, err = checkOptions(opts)
  if not o then return false, err end
  stats = { stacks = 0, blocks = 0, changed = 0, stalled = 0, dumps = 0, results = {} }
  print(string.format("input %s, output %s, pulse %s, %s, %.1fs delay",
    o.input, o.output, o.pulse, (o.stacks > 0) and (o.stacks .. " stacks") or "until stopped", o.delay))

  -- Start with an empty inventory so the stack has the work slot.
  if firstFilled() then
    print("emptying what is carried first")
    dumpAll(o.output)
  end

  while o.stacks == 0 or stats.stacks < o.stacks do
    local slot, name, count = takeStack(o.input)
    print(string.format("stack %d: %d %s", stats.stacks + 1, count, shortName(name)))
    local tally, changed = {}, 0
    local stackText = (o.stacks > 0) and ("stack " .. (stats.stacks + 1) .. " of " .. o.stacks) or ("stack " .. (stats.stacks + 1))
    local done = 0
    progress.report(done, count, stackText)
    while stackLeft(slot, name) do
      if not placeBlock(slot, name) then break end
      local before = blockAhead()
      local after, did = changeBlock(o.pulse, o.delay, before)
      if did then
        stats.stalled = 0
        changed = changed + 1
        local result = after or "nothing"
        tally[result] = (tally[result] or 0) + 1
        stats.results[result] = (stats.results[result] or 0) + 1
      end
      digBlock(o.output, slot)
      stats.blocks = stats.blocks + 1
      done = done + 1
      progress.report(done, count, stackText)
    end
    stats.changed = stats.changed + changed
    stats.stacks = stats.stacks + 1
    print(string.format("stack %d done: %d changed of %d (%s)", stats.stacks, changed, count, tallyText(tally)))
    dumpAll(o.output)
  end
  print(string.format("done: %d stacks, %d blocks, %d changed (%s)", stats.stacks, stats.blocks, stats.changed, tallyText(stats.results)))
  return true
end

-- What the last run did (stacks, blocks, changed, dumps, results by name).
function lastStats() return stats end
