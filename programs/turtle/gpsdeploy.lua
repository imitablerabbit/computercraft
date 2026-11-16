--[[
GPS deploy builds a gps constellation from one turtle: four host
computers high in the air, each with a wireless modem, running
`gps host` with its own coordinates, so that any computer with a
wireless modem in range can `gps locate`.

The turtle carries 4 computers, 4 wireless modems, a disk drive, a
floppy disk and fuel. It is told where it is in Minecraft coordinates
and which way it faces (F3 shows both), or works it out with gps when
a constellation is already in range. It climbs straight up to the
height (by default as high as it can, up to y=250; it stops under
anything in the way) and puts the hosts at the corners of a
tetrahedron eight blocks across: three on one level and the fourth
four blocks lower, because gps needs four hosts that are not all in
one plane to find a single position.

For each host it places the computer, backs off one block and places
the modem into the gap so it sticks to the computer, puts the disk
drive on top of the computer with the floppy in it, and writes an
installer to the floppy. Then it turns the computer on; the computer
runs the installer from the floppy, which writes the computer's own
startup file (`gps host x y z`) and labels the computer "GPS x,y,z"
(labelled computers keep their files when broken and picked up). Once
the turtle sees the label it takes the floppy and the drive back. When
all four run it comes back down to where it started and checks the
result with gps locate.

A computer that is picked up again keeps its startup file, but a
gpsdeploy floppy next to it wins, so the same computers can be used
for a new constellation.

The turtle remembers the last constellation it built in gpsdeploy.dat.
`gpsdeploy remove`, run from the same starting block facing the same
way, flies the same route and digs the four hosts and their modems
back up (it needs five empty slots).

Usage: gpsdeploy <x> <y> <z> <north|east|south|west> [height]
       gpsdeploy gps [height]
       gpsdeploy remove

height is the y to climb to; 0 or none means as high as possible.
The facing may also be gps, which ignores x, y and z.
--]]

local MaxHeight = 250  -- default top: high enough for a wide range
local MinClimb = 8     -- the lowest host must clear the start
local Overhead = 200   -- fuel for everything but the climb, with spare
local Spread = 4       -- blocks from the middle to each host
local BootWait = 15    -- seconds to wait for a host to label itself
local RecordFile = "gpsdeploy.dat" -- the last constellation built

local args = {...}

local function usage()
  print("Usage: gpsdeploy <x> <y> <z> <north|east|south|west> [height]")
  print("       gpsdeploy gps [height]")
  print("       gpsdeploy remove")
end

if not turtle then
  print("gpsdeploy needs a turtle")
  return
end

--[[
Arguments and where the turtle is
--]]

-- Minecraft directions: x east, z south.
local Facings = { north = 0, east = 1, south = 2, west = 3 }
local FacingNames = { [0] = "north", "east", "south", "west" }
local FacingVectors = { [0] = { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } } -- x, z

local useGps, startX, startY, startZ, facing, height
local removing, record = false, nil
if args[1] == "remove" then
  removing = true
  local h = fs.open(RecordFile, "r")
  if h then
    record = textutils.unserialize(h.readAll() or "")
    h.close()
  end
  if type(record) ~= "table" or not tonumber(record.travel) or not Facings[tostring(record.facing)] then
    error("no constellation recorded in " .. RecordFile .. " to remove", 0)
  end
  startX, startY, startZ = record.x, record.y, record.z
  facing = Facings[record.facing]
elseif args[1] == "gps" then
  useGps = true
  height = args[2]
elseif #args >= 4 then
  if args[4] == "gps" then
    useGps = true
  else
    startX, startY, startZ = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    facing = Facings[string.lower(args[4])]
    if not (startX and startY and startZ) then
      usage()
      error("x, y and z must be numbers", 0)
    end
    if not facing then
      usage()
      error("facing must be north, east, south or west", 0)
    end
  end
  height = args[5]
else
  usage()
  return
end
if height ~= nil then
  local n = tonumber(height)
  if not n or n < 0 then
    usage()
    error("height must be a number (0 for as high as possible)", 0)
  end
  height = n > 0 and math.floor(n) or nil
end

local function locate()
  local x, y, z = gps.locate(3)
  if not x then return nil end
  return math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5)
end

-- Work out position and facing with gps: locate, step forward (or
-- turn until a step is free), locate again, step back.
local function locateWithGps()
  local x, y, z = locate()
  if not x then error("no gps answer: give x y z and facing instead", 0) end
  for turn = 0, 3 do
    if turtle.forward() then
      local x2, _, z2 = locate()
      turtle.back()
      for i = 1, turn do turtle.turnLeft() end
      if not x2 then error("lost gps after one step: give x y z and facing instead", 0) end
      local dx, dz = x2 - x, z2 - z
      for f = 0, 3 do
        if FacingVectors[f][1] == dx and FacingVectors[f][2] == dz then
          return x, y, z, (f - turn) % 4
        end
      end
      error("gps gave a strange step: give x y z and facing instead", 0)
    end
    turtle.turnRight()
  end
  error("boxed in, cannot step to find the facing", 0)
end

--[[
Items
--]]

local function isComputer(name)
  return name == "computercraft:computer_normal" or name == "computercraft:computer_advanced"
end
local function isModem(name)
  return name == "computercraft:wireless_modem_normal" or name == "computercraft:wireless_modem_advanced"
end
local function isDrive(name) return name == "computercraft:disk_drive" end
local function isDisk(name) return name == "computercraft:disk" end

local function countItems(pred)
  local n = 0
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d and pred(d.name) then n = n + d.count end
  end
  return n
end

local function selectItem(pred, what)
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d and pred(d.name) then
      turtle.select(slot)
      return true
    end
  end
  error("no " .. what .. " left in the turtle", 0)
end

local missing = {}
if removing then
  local free = 0
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then free = free + 1 end
  end
  if free < 5 then missing[#missing + 1] = "5 empty slots" end
else
  if countItems(isComputer) < 4 then missing[#missing + 1] = "4 computers" end
  if countItems(isModem) < 4 then missing[#missing + 1] = "4 wireless modems" end
  if countItems(isDrive) < 1 then missing[#missing + 1] = "a disk drive" end
  if countItems(isDisk) < 1 then missing[#missing + 1] = "a floppy disk" end
end
if #missing > 0 then
  error("the turtle needs " .. table.concat(missing, ", "), 0)
end

if useGps then
  print("Finding the position with gps...")
  startX, startY, startZ, facing = locateWithGps()
end
print(string.format("Start %d,%d,%d facing %s", startX, startY, startZ, FacingNames[facing]))
if removing then
  -- Refuse to fly the route from the wrong place when gps can tell.
  local x, y, z = nil, nil, nil
  if peripheral.find("modem") then x, y, z = locate() end
  if x and (x ~= startX or y ~= startY or z ~= startZ) then
    error(string.format("the turtle is at %d,%d,%d; the constellation was built from %d,%d,%d", x, y, z, startX, startY, startZ), 0)
  end
  height = startY + record.travel
end

-- How far to climb.
local top = height or MaxHeight
local climb = top - startY
if height and climb < MinClimb then
  error("height " .. height .. " is less than " .. MinClimb .. " above the turtle (y=" .. startY .. ")", 0)
end
local fuel = turtle.getFuelLevel()
if fuel ~= "unlimited" then
  if fuel < 2 * climb + Overhead then inventory.refuelAll() end
  fuel = turtle.getFuelLevel()
  local afford = math.floor((fuel - Overhead) / 2)
  if afford < climb then
    if height or afford < MinClimb then
      error(string.format("not enough fuel: %d needed to reach y=%d and come back, have %d",
        2 * climb + Overhead, top, fuel), 0)
    end
    climb = afford
    print("Fuel allows climbing to y=" .. (startY + climb))
  end
end

--[[
Moving, with the position kept relative to the start: f forward (the
start facing), r to the right, u up, h the heading (0 the start
facing, 1 right, 2 back, 3 left).
--]]

local pos = { f = 0, r = 0, u = 0, h = 0 }
local Steps = { [0] = { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } } -- f, r

local function where()
  return string.format("%d,%d,%d", pos.f, pos.r, pos.u)
end

-- Try a move a few times: a mob or a falling block may be passing.
local function try(fn)
  for i = 1, 5 do
    if turtle[fn]() then return true end
    sleep(0.5)
  end
  return false
end

local function forward()
  if not try("forward") then return false end
  local s = Steps[pos.h]
  pos.f, pos.r = pos.f + s[1], pos.r + s[2]
  return true
end
local function back()
  if not try("back") then return false end
  local s = Steps[pos.h]
  pos.f, pos.r = pos.f - s[1], pos.r - s[2]
  return true
end
local function up()
  if not try("up") then return false end
  pos.u = pos.u + 1
  return true
end
local function down()
  if not try("down") then return false end
  pos.u = pos.u - 1
  return true
end
local function right() turtle.turnRight(); pos.h = (pos.h + 1) % 4 end
local function left() turtle.turnLeft(); pos.h = (pos.h + 3) % 4 end
local function face(h)
  h = h % 4
  if (h - pos.h) % 4 == 3 then left() end
  while pos.h ~= h do right() end
end

local function must(ok, what)
  if not ok then error(what .. " (at " .. where() .. " from the start)", 0) end
end

-- Straight to a level, then along f, then along r, then to u. Travel
-- happens on the top level, which is clear apart from the turtle.
local function goTo(f, r, u, travel)
  while pos.u < travel do must(up(), "blocked going up") end
  while pos.u > travel do must(down(), "blocked going down") end
  if pos.f ~= f then
    face(pos.f < f and 0 or 2)
    while pos.f ~= f do must(forward(), "blocked in the air") end
  end
  if pos.r ~= r then
    face(pos.r < r and 1 or 3)
    while pos.r ~= r do must(forward(), "blocked in the air") end
  end
  while pos.u < u do must(up(), "blocked going up") end
  while pos.u > u do must(down(), "blocked going down") end
end

-- Minecraft coordinates of a position relative to the start.
local function world(f, r, u)
  local fv, rv = FacingVectors[facing], FacingVectors[(facing + 1) % 4]
  return startX + f * fv[1] + r * rv[1], startY + u, startZ + f * fv[2] + r * rv[2]
end

--[[
Building one host
--]]

-- What the floppy runs on the new computer: write the computer's own
-- startup, label it (the turtle waits for the label) and start hosting.
local function installer(x, y, z, label)
  local host = table.concat({
    "-- A gps host placed by gpsdeploy. A gpsdeploy floppy in a drive",
    "-- next to this computer wins, so it can be set up again elsewhere.",
    "if fs.exists(\"disk/gpsdeploy.txt\") and fs.exists(\"disk/startup.lua\") then",
    "  shell.run(\"disk/startup.lua\")",
    "  return",
    "end",
    string.format("shell.run(\"gps\", \"host\", \"%d\", \"%d\", \"%d\")", x, y, z),
  }, "\n")
  return table.concat({
    "-- Written by gpsdeploy: makes this computer the gps host at " .. x .. "," .. y .. "," .. z .. ".",
    "local h = fs.open(\"startup.lua\", \"w\")",
    "h.write(" .. string.format("%q", host) .. ")",
    "h.close()",
    "os.setComputerLabel(" .. string.format("%q", label) .. ")",
    "print(\"Installed: gps host " .. x .. " " .. y .. " " .. z .. "\")",
    "fs.delete(\"disk/gpsdeploy.txt\") -- only the first boot installs",
    "shell.run(\"startup.lua\")",
  }, "\n")
end

local function writeFile(path, text)
  local h = fs.open(path, "w")
  if not h then error("cannot write " .. path, 0) end
  h.write(text)
  h.close()
end

-- Wait for the computer in front to label itself.
local function waitForLabel(label)
  local deadline = os.clock() + BootWait
  while os.clock() < deadline do
    local ok, current = pcall(peripheral.call, "front", "getLabel")
    if ok and current == label then return true end
    sleep(0.5)
  end
  return false
end

-- Build the host whose computer goes one block ahead of (f, r, u),
-- standing there facing the start direction. Leaves the turtle above
-- that spot, with the drive and floppy back in its inventory.
local function buildHost(f, r, u)
  local x, y, z = world(f + 1, r, u)
  local label = string.format("GPS %d,%d,%d", x, y, z)
  print("Host at " .. x .. "," .. y .. "," .. z)
  face(0)
  selectItem(isComputer, "computer")
  must(turtle.place(), "could not place a computer")
  must(back(), "could not back away from the computer")
  selectItem(isModem, "wireless modem")
  must(turtle.place(), "could not place the modem")
  must(up(), "blocked going up")
  must(forward(), "blocked over the modem")
  selectItem(isDrive, "disk drive")
  must(turtle.place(), "could not place the disk drive")
  driveOut = true
  selectItem(isDisk, "floppy disk")
  must(turtle.drop(), "could not put the floppy in the drive")
  sleep(0.2)
  local mount = disk.getMountPath("front")
  must(mount, "the floppy did not mount")
  -- The marker lets an already used, labelled computer run the
  -- installer instead of its old startup; the first boot removes it.
  writeFile(fs.combine(mount, "startup.lua"), installer(x, y, z, label))
  writeFile(fs.combine(mount, "gpsdeploy.txt"), label)

  -- Round to the side of the computer to switch it on.
  right()
  must(forward(), "blocked beside the drive")
  must(down(), "blocked beside the modem")
  left()
  must(forward(), "blocked beside the computer")
  left()
  must(peripheral.getType("front") == "computer", "the computer is not where it should be")
  peripheral.call("front", "turnOn")
  if not waitForLabel(label) then
    peripheral.call("front", "reboot")
    must(waitForLabel(label), "the computer did not run the installer from the floppy")
  end

  -- Back over the modem to take the floppy and the drive.
  right()
  must(back(), "blocked beside the computer")
  must(up(), "blocked beside the modem")
  left()
  must(forward(), "blocked beside the drive")
  right()
  must(turtle.suck(), "could not take the floppy back")
  must(turtle.dig(), "could not take the disk drive back")
  driveOut = false
  return x, y, z
end

--[[
The deploy
--]]

local hostsDone = 0
local placed = {}
local travelLevel = nil -- the top level, once the climb is done
local driveOut = false   -- the drive and floppy are placed at a host

local function report(text)
  progress.report(hostsDone, 4, text)
end

-- Back to the start: up to the top level (the hosts are below it),
-- over to the climbing column and down it.
local function goHome()
  local travel = math.max(pos.u, travelLevel or 0)
  goTo(0, 0, travel, travel)
  goTo(0, 0, 0, pos.u)
  face(0)
end

-- Hosts at the corners of a tetrahedron around the climbing column:
-- ahead, right, behind and (lower) left, below the top level travel.
-- Each entry is where the turtle stands; the computer goes one block
-- ahead of it.
local function sitesFor(travel)
  local level = travel - 1 -- the level of three of the hosts
  return {
    { Spread - 1, 0, level },
    { -1, Spread, level },
    { -Spread - 1, 0, level },
    { -1, -Spread, level - Spread },
  }
end

local function saveRecord()
  local h = fs.open(RecordFile, "w")
  if not h then return end
  h.write(textutils.serialize({ x = startX, y = startY, z = startZ, facing = FacingNames[facing],
    travel = travelLevel, hosts = placed }))
  h.close()
end

-- Dig up the hosts of the recorded constellation: from behind each
-- modem, dig it, step in and dig the computer.
local function removeHosts(travel)
  for i, site in ipairs(sitesFor(travel)) do
    report("host " .. i .. " of 4")
    local x, y, z = world(site[1] + 1, site[2], site[3])
    print("Removing host at " .. x .. "," .. y .. "," .. z)
    goTo(site[1] - 1, site[2], site[3], travel)
    face(0)
    if turtle.detect() then must(turtle.dig(), "could not dig the modem") end
    must(forward(), "blocked where the modem was")
    if turtle.detect() then must(turtle.dig(), "could not dig the computer") end
    hostsDone = i
  end
end

local function run()
  -- Climb. Without a height, stop under whatever is above.
  report("climbing")
  while pos.u < climb do
    if not up() then
      if height then must(false, "blocked climbing to y=" .. top) end
      break
    end
  end
  if pos.u < MinClimb then
    must(false, "only " .. pos.u .. " blocks of room above the start")
  end
  local travel = pos.u   -- the top level, where the turtle moves about
  travelLevel = travel
  if removing then
    removeHosts(travel)
    report("coming down")
    goHome()
    return
  end
  print("Building at y=" .. (startY + travel - 1))

  for i, site in ipairs(sitesFor(travel)) do
    report("host " .. i .. " of 4")
    goTo(site[1], site[2], site[3], travel)
    local x, y, z = buildHost(site[1], site[2], site[3])
    placed[#placed + 1] = { x, y, z }
    hostsDone = i
  end

  report("coming down")
  goHome()
end

local ok, err = pcall(run)
if not ok then
  err = tostring(err)
  if driveOut then err = err .. "; the disk drive and floppy are still at the last host" end
  alert.raise("gps", "gpsdeploy stopped: " .. err)
  -- Come back down the way it went up, so it is not left in the air.
  local back = pcall(goHome)
  if not back then
    error("gpsdeploy: " .. tostring(err) .. "; could not get back, the turtle is at " .. where() .. " from the start", 0)
  end
  alert.clear("gps")
  error("gpsdeploy: " .. tostring(err) .. " (back at the start, " .. #placed .. " hosts placed)", 0)
end

if removing then
  fs.delete(RecordFile)
  print("done: removed 4 hosts")
  return
end
saveRecord()

for i, p in ipairs(placed) do
  print(string.format("host %d: %d,%d,%d", i, p[1], p[2], p[3]))
end
-- Give the hosts a moment, then see whether gps agrees with the start.
sleep(1)
local x, y, z = locate()
if not x then
  print("done: 4 hosts placed, but no gps answer here (out of range or no modem on this turtle)")
elseif x == startX and y == startY and z == startZ then
  print(string.format("done: gps locate gives %d,%d,%d, which matches", x, y, z))
else
  print(string.format("done: gps locate gives %d,%d,%d, expected %d,%d,%d", x, y, z, startX, startY, startZ))
end
