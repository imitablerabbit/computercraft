# Navigation and building

## Getting around: goto and where

`goto` walks a turtle to a position, finding its own way around
whatever is in the way, and `where` says where it thinks it is. Both
use `apis/nav.lua`, which keeps track of the turtle's position and
heading through every move it makes and remembers the blocks it has
seen.

```
goto <x> <y> <z> [dig] [heading]
goto home [dig]
goto sethome
where
where set <x> <y> <z> <north|east|south|west>
where gps
where reset
```

Coordinates are Minecraft's own (x east, y up, z south, as on the F3
screen) once nav is calibrated. With a wireless modem and four gps
hosts in range `goto` calibrates by itself the first time: it asks gps
where it is, moves one block, asks again to learn which way it faces,
and moves back. Without gps, coordinates count from where nav started
tracking: that block is 0 0 0 and the way the turtle faced is north,
so forward is -z, right is +x and up is +y. `where set` gives the real
coordinates by hand instead, read off F3 (the block the turtle is in
and the way it faces).

`goto` plans a route with A* over the blocks it knows, treating blocks
it has never seen as probably free. When a move is blocked it records
what was there, looks above and below too, and plans again, so in an
unknown place it feels its way along. With `dig` it digs through
rather than going round when that is shorter, but it never digs chests,
barrels, furnaces, computers, turtles or other ComputerCraft blocks.
Another turtle in the way is waited for for a few seconds before it
goes round. Before leaving it checks the fuel covers the planned trip
and refuses rather than run dry on the way. A heading at the end
(`goto 100 64 -20 north`) turns the turtle that way on arrival.
`goto sethome` remembers where the turtle is and which way it faces,
and `goto home` goes back there.

`where` prints the position and heading, whether they are Minecraft
coordinates, the home and how many blocks the map knows. Go to is in
the turtle control job list, with text fields for the coordinates and
a Dig switch.

Only moves made through nav are tracked. The other jobs (quarry,
strip mine, logger and so on) move the turtle themselves, so afterwards
nav's position is off: `where gps` puts it right when nav is
calibrated, or set it with `where set`. Nav saves the position before
and after every move, so a turtle rebooted in the middle of a move
(the chunk unloading, the server stopping) works out on its next use
whether the move happened: it asks gps when calibrated, and otherwise
compares the fuel level with the one saved before the move, since a
move costs exactly one fuel. A turn costs no fuel and cannot be
checked that way, so after an interrupted turn `where` says the
heading is unsure and `goto` recalibrates with gps first.

The state is kept in `/.nav_state` and the map in `/.nav_map`, at most
4000 blocks (the ones furthest away are forgotten first).

### The nav API

For programs that move turtles around:

- `nav.position()` gives `x, y, z, heading`; `nav.status()` a table
  with those, `calibrated`, `sure`, `headingSure`, `home` and the
  number of map `cells`.
- `nav.forward()`, `back()`, `up()`, `down()`, `turnLeft()`,
  `turnRight()` and `nav.face(heading)` move and turn like the turtle
  functions and keep track. `nav.inspect()`, `detect()` and `dig()`
  (and their Up and Down forms) do the same and record the block.
- `nav.goTo(x, y, z, opts)` returns `true` or `false, reason`. `opts`:
  `dig`, `protect` (more block names or patterns never to dig),
  `blocked` (a function of x, y, z that is true for blocks to keep out
  of, such as a building in progress), `heading` (face it at the end),
  `force` (skip the fuel check), `maxReplans` (default 64) and
  `maxNodes` (search size, default 20000).
- `nav.setHome([x, y, z, heading])`, `nav.getHome()`,
  `nav.goHome(opts)` and `nav.distance([x, y, z])` (to home without
  arguments).
- `nav.locate()` asks gps and, when calibrated, corrects the position;
  `nav.calibrate(opts)` switches to Minecraft coordinates, carrying the
  map and home over; `nav.setPosition(x, y, z, heading [, frame])` and
  `nav.reset()` set it by hand.
- `nav.findPath(start, goal, cellAt, opts)` is the A* search on its
  own, with no turtle calls: it gives the list of steps (forward, up,
  down, turnLeft, turnRight with where the turtle is after each). A
  turn costs as much as a move, a block never seen costs one more and
  digging through a known block three more.
- `nav.relative(origin, right, up, forward)` gives the block that far
  from a position and heading as a turtle there sees it.

## Building: build, scan and blueprints

`build` puts up a structure from a blueprint file, and `scan` writes a
blueprint of a structure that is already there, so a building can be
copied.

```
build <blueprint> [chest] [clear] [check]     chest defaults to behind
scan <file> <width> <length> <height>
```

A blueprint is a text file that can be written by hand: a palette
giving each character a block, then the layers from the bottom up,
each drawn as seen from above with the back row first:

```
--[[
name Hut
# = minecraft:cobblestone
= = minecraft:oak_planks
g = minecraft:glass
. = air
layer 1
#####
#...#
#...#
#...#
##.##
layer 2
...
]]
```

Palette lines are one character, ` = ` and a block name, or `air` for
a block that should be empty (`.` is air unless the palette says
otherwise). A space is "don't care": whatever is there is left alone.
Lines starting with `--` are comments, `name` gives the blueprint a
name, and each `layer` line starts the next layer up. The `--[[` and
`]]` around it make the file a Lua comment, so blueprints can be named
`.lua` and the installers, which only copy `.lua` files, bring them
along: `blueprints/hut.lua` (a 5x5 cobblestone hut with a door gap,
two windows and a plank roof) and `blueprints/watchtower.lua` (a 5x5
tower 8 high with log corners, windows, a platform and battlements)
are installed with everything else, and `build hut` finds them by name
in `/blueprints`.

The turtle starts on the block in front of the footprint's front left
corner, level with the bottom layer (standing on the ground the
building goes on), facing in:

```
          back
      . . . . .      each layer as drawn in the file:
      . . . . .      the first row is the back,
      . . . . .      the last row the front
      # . . . .
      T              the turtle, facing up the page
    left    right
```

Before starting, `build` prints the materials and how many of each the
turtle and the chest have, and what is missing; with `check` it
refuses to start until nothing is. It takes what it needs from the
chest (`behind`, `left`, `right`, `below`, `above`, or `none` to use
only what it carries), then flies one block above each layer in a
snake, placing every block below it. When an item runs out it goes
back to the chest for more, and when the chest has none either it
raises an alert listing what is missing and waits, looking again when
items are put in the turtle or every 20 seconds. Keep the chest for
the materials: anything else is taken out and put back, and a chest
whose first 16 stacks are all things the build does not need is never
got past. Blocks already in place are counted as done. Anything else
in the way, and anything in `.` cells, is dug out only with `clear`;
without it those cells are left and counted as blocked in the summary
at the end. It never flies through the layers it has built, never digs
chests or computers, and never burns its materials as fuel; when fuel
gets short it goes back to the start and asks for more. At the end it
puts unused materials back in the chest and stands where it started.
Progress (blocks done of the total, and the layer) shows in turtle
control, where Build is a job with the blueprint name (hut and
watchtower offered, or type one), the chest side and a Clear switch.
Blocks that face a way (stairs, doors, torches) go down however
placeDown puts them.

`scan` starts from the same corner and writes a `width x length x
height` box to a blueprint, `/blueprints/<file>.lua` when the name has
no folder or extension. A turtle can only look at the blocks next to
it and scan never digs, so it explores the air in and around the box
(one block past its sides, back and top) and looks at every block it
can reach from there. That sees every block of a building that touches
air the turtle can get to, inside or out; blocks it never saw (inside
a thick wall, or a sealed room) are written as don't care, and the air
it found as `.`. Palette characters follow the block names in order,
with readable defaults (`#` cobblestone, `=` planks, `o` logs, `g`
glass). It returns to the start at the end, and stops early, saving
what it has, if fuel gets short of the way back. `build` on the file
then puts up a copy, from the same kind of start, anywhere.

The format is read and written by `apis/blueprint.lua`
(`blueprint.load`, `save`, `parse`, `serialize`, `at`, `set`,
`materials` and `missing`).

In the simulator, the Build scenario has a turtle with a stocked chest
in front of an empty plot (and two blocks in the way, to try `clear`),
Scan and copy has a hut to scan and a second plot it walks to and
builds the copy on, and Maze has a covered stone brick maze for `goto
0 1 -8`, with the GPS demo's four hosts around it so `goto` calibrates
first.
