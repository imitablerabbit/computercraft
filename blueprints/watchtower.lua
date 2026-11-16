--[[
-- A 5x5 watchtower, 8 high: cobblestone walls with oak log corners,
-- a door gap at the front, glass windows on every side, a plank
-- platform with a hatch hole and battlements on top. Build it with:
-- build watchtower
-- The turtle starts in front of the front row's left end, level with
-- the bottom layer, facing in (see the blueprint API for the format).
name Watchtower
# = minecraft:cobblestone
o = minecraft:oak_log
= = minecraft:oak_planks
g = minecraft:glass
. = air
layer 1
o###o
#...#
#...#
#...#
o#.#o
layer 2
o###o
#...#
#...#
#...#
o#.#o
layer 3
o###o
#...#
#...#
#...#
o###o
layer 4 windows
o#g#o
#...#
g...g
#...#
o#g#o
layer 5
o###o
#...#
#...#
#...#
o###o
layer 6 platform
=====
=====
==.==
=====
=====
layer 7 battlements
o#.#o
#...#
.....
#...#
o#.#o
layer 8
o...o
.....
.....
.....
o...o
]]
