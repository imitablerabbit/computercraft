--[[
Where prints where the nav API thinks the turtle is: its position, the
way it faces, whether the coordinates are Minecraft's own (calibrated
with gps or set by hand) or count from where tracking started, the
home and how many blocks the map remembers. It can also set the
position by hand, for example from the F3 screen (the block the turtle
is in, and the way it faces), locate it again with gps after a program
moved it with plain turtle moves, or forget everything.

Usage: where
       where set <x> <y> <z> <north|east|south|west>
       where gps
       where reset
--]]

local args = { ... }

local function show()
  local s = nav.status()
  print("at " .. s.x .. " " .. s.y .. " " .. s.z .. " facing " .. s.headingName)
  if s.calibrated then
    print("Minecraft coordinates (calibrated)")
  else
    print("counting from where tracking started")
    print("(not calibrated: goto or where gps)")
  end
  if not s.sure then print("position unsure: a move was interrupted") end
  if not s.headingSure then print("heading unsure: a turn was interrupted") end
  if s.home then
    print("home " .. s.home.x .. " " .. s.home.y .. " " .. s.home.z .. " facing " .. nav.headingName(s.home.heading)
      .. ", " .. nav.distance() .. " blocks away")
  else
    print("no home set")
  end
  print("map: " .. s.cells .. " blocks known")
end

if #args == 0 then
  show()
elseif args[1] == "set" and #args == 5 then
  local x, y, z, h = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]), nav.parseHeading(args[5])
  if not (x and y and z and h) then error("where set <x> <y> <z> <north|east|south|west>", 0) end
  nav.setPosition(x, y, z, h, "world")
  show()
elseif args[1] == "gps" and #args == 1 then
  if nav.status().calibrated then
    local x, err = nav.locate()
    if not x then error(err, 0) end
  else
    local ok, err = nav.calibrate()
    if not ok then error(err, 0) end
  end
  show()
elseif args[1] == "reset" and #args == 1 then
  nav.reset()
  show()
else
  print("Usage: where")
  print("       where set <x> <y> <z> <heading>")
  print("       where gps")
  print("       where reset")
end
