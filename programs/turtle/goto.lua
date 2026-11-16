--[[
Goto walks the turtle to a position with the nav API, finding its way
around whatever is in the way (and digging through it when told to).
Coordinates are Minecraft's (x east, y up, z south) once nav is
calibrated; when it is not and gps answers, goto calibrates first,
otherwise they count from where nav started tracking (see `where`).
`goto home` goes back to the home set with `goto sethome`, facing the
way the turtle faced then. Blocked moves are replanned, another turtle
in the way is waited for, and goto refuses to leave without the fuel
for the trip.

A heading after the coordinates (north, east, south, west) turns the
turtle that way at the end, for example to leave it where build or scan
should start.

Usage: goto <x> <y> <z> [dig] [heading]
       goto home [dig]
       goto sethome
--]]

local args = { ... }
local function usage()
  print("Usage: goto <x> <y> <z> [dig] [heading]")
  print("       goto home [dig]")
  print("       goto sethome")
end

local function isDig(a)
  return a == "dig" or a == "true"
end

-- Calibrate with gps when nav is not calibrated and gps answers.
local function maybeCalibrate(dig)
  if nav.status().calibrated then return end
  if not peripheral.find("modem", function(_, m) return m.isWireless and m.isWireless() end) then return end
  print("calibrating with gps...")
  local ok, x, y, z, h = nav.calibrate({ dig = dig })
  if ok then
    print("at " .. x .. " " .. y .. " " .. z .. " facing " .. nav.headingName(h))
  else
    print("no gps, using coordinates from where tracking started")
  end
end

if args[1] == "sethome" and #args == 1 then
  nav.setHome()
  local x, y, z, h = nav.position()
  print("home set to " .. x .. " " .. y .. " " .. z .. " facing " .. nav.headingName(h))
  return
end

local ok, err
if args[1] == "home" and #args <= 2 and (args[2] == nil or isDig(args[2]) or args[2] == "false") then
  local home = nav.getHome()
  if not home then error("no home set: run goto sethome there first", 0) end
  local dig = isDig(args[2])
  maybeCalibrate(dig)
  print("going home to " .. home.x .. " " .. home.y .. " " .. home.z)
  ok, err = nav.goHome({ dig = dig })
else
  local x, y, z = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
  local dig, heading = false, nil
  for i = 4, #args do
    if isDig(args[i]) then dig = true
    elseif args[i] == "false" then dig = false
    elseif nav.parseHeading(args[i]) and not tonumber(args[i]) then heading = nav.parseHeading(args[i])
    else x = nil end
  end
  if not (x and y and z) or #args > 5 then
    usage()
    return
  end
  maybeCalibrate(dig)
  print("going to " .. x .. " " .. y .. " " .. z .. (dig and ", digging" or ""))
  ok, err = nav.goTo(x, y, z, { dig = dig, heading = heading })
end

local x, y, z, h = nav.position()
if ok then
  print("arrived at " .. x .. " " .. y .. " " .. z .. " facing " .. nav.headingName(h))
else
  error("stopped at " .. x .. " " .. y .. " " .. z .. ": " .. tostring(err), 0)
end
