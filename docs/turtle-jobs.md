# Turtle jobs: tunnel, rail, bridge, farm and lava fuel

## Tunnel

`tunnel` bores a tunnel straight ahead, 1 to 5 blocks wide and 2 to 5
high, and brings what it digs back to a chest. Put the turtle on the
tunnel's floor level just in front of where it should start, looking
along it, with a chest beside it and some torches, a stack of
cobblestone and coal in it:

```
tunnel [length] [width] [height] [torchGap] [chest] [return] [plug]
                                       defaults 32 3 3 8 behind true true
```

The tunnel is centred on the turtle (an even width has its extra
column on the right) and goes up from the turtle's level; the start
block is not dug, so the chest can be on any side (`left`, `right`,
`behind`, `below` or `above`). The turtle clears each slice column by
column. On the way it fills holes in the floor with cobblestone or
dirt it dug so the tunnel can be walked, digs out sand and gravel
hanging over the ceiling until nothing more falls, and with `plug`
on puts a block over any lava or water it uncovers in the walls,
floor, ceiling or the end, and turns liquid inside the tunnel into a
block before digging it. Every `torchGap` slices (0 for none) a torch
goes on the floor of an outer column, or for a one wide tunnel at the
top where it hangs on the wall, so the turtle never has to get past
one.

When the inventory fills up, or fuel runs short of the way home, it
walks back down the middle of the tunnel, empties itself into the
chest (keeping its torches, the biggest stack of cobblestone and its
coal) and goes back to where it left off. Low on fuel it burns coal
it dug first, and otherwise waits at the chest with a fuel alert until
it has enough for the round trip. A missing or full chest raises an
alert and it waits until it can empty itself. With `return` (the
default) it comes back to the chest at the end; otherwise it stays at
the far end. Bedrock or anything else it cannot dig stops it; it then
comes home and says where. The engine is `apis/tunnel.lua`.

## Rail

`rail` lays a straight, level rail line. Put the turtle on the block
where the line starts, looking along it, with rails, some cobblestone
(or any building block) and coal:

```
rail [length] [poweredGap] [torchGap]       defaults 64 0 0
```

The turtle rises one block and flies along at head height, placing
rail below itself. It digs whatever is in the rail's space or in its
own way, so the line has two blocks of headroom (sand and gravel that
fall in are dug until they stop), keeps any rail already there, and
where the rail will not go down because there is nothing under it (a
gap, a ravine, water) it drops in, puts a block underneath and tries
again. Every `poweredGap` blocks it lays a powered rail with a
redstone torch beside it at rail level, left side first, when it has
both; without them it lays a plain rail there and says so once. Every
`torchGap` blocks a torch goes beside the line, right side first. 0
turns either off. When the rails or blocks run out it raises a
`rails` or `blocks` alert and waits, carrying on as soon as more are
put into it. It stops above the last rail. The engine is
`apis/rail.lua`.

## Bridge

`bridge` builds a one block wide walkway across a gap of air, water
or lava. Put the turtle on the near edge looking across, with
building blocks and a little fuel:

```
bridge [length] [walls] [untilGround] [block]     defaults 32 none 0 any
```

It walks forward and puts a block under itself wherever there is
nothing solid, for up to `length` blocks, digging through anything in
its way. `walls` adds a side one block high on both sides of the part
over the gap: `rails` uses fences or walls (any `*_fence` or `*_wall`
it carries), `walls` the same blocks as the floor, `none` leaves it
open. `block` is the floor item, or `any` for whatever building block
it carries: no sand or gravel, which would fall, and none of the
things that are worth keeping or need something under them (torches,
chests, rails, ores and so on, `inventory.NotBuilding`). Planks and
fences it carries are never burnt for fuel. With `untilGround` above
0 it stops once it has crossed the gap and had solid ground under it
for that many blocks in a row, so it can be sent across a gap of
unknown width. Out of blocks or fences it raises an alert and waits
for more. The engine is `apis/bridge.lua`.

## Farm

`farm` looks after a field of farmland that a player has tilled. Put
the turtle over a corner of the field, one block above the crops,
looking along it, with a chest beside it, and give it the seeds,
carrots or potatoes to plant and some coal:

```
farm [width] [length] [crop] [sleep] [passes] [chest]
                                    defaults 9 9 wheat 300 0 behind
```

Width is to the turtle's right and length straight ahead. Each pass
it flies over the field in a snake and looks down at every crop.
Ripe ones (wheat, carrots and potatoes at age 7, beetroot at 3) are
dug and the same crop is planted again from what it carries; empty
farmland is sown with `crop` (`wheat`, `carrots`, `potatoes`,
`beetroots`, or `none` to leave it); young crops and anything else
are left alone. Then it flies back to the corner, empties the harvest
into the chest keeping one stack of each seed (carrots and potatoes
are their own seeds) and its coal, sleeps `sleep` seconds and goes
again, `passes` times or forever with 0. A full inventory sends it to
the chest in the middle of a pass. When it has nothing to plant a
crop with it raises a `seeds` alert and leaves the block bare to be
sown on a later pass. The chest can be `left`, `behind` or `above`
(`right` only for a field one block wide, since the turtle flies over
the rest). With a hoe equipped it also tries to till dirt it finds
under an empty block and says so when it starts; in the game the hoe
reaches the dirt two blocks down through the empty crop space, but
the simulator only tills straight ahead, so there those blocks just
count as "not farmland". The engine is `apis/farm.lua`.

## Lava fuel

`lavafuel` refuels the turtle from a lava lake with buckets. Put it at
the edge of the lava looking toward it, carrying empty buckets, and
for depot mode with a chest beside it:

```
lavafuel [targetFuel] [range] [mode] [chest] [width]
                                    defaults 5000 16 refuel behind 1
```

It searches `range` blocks straight ahead and `width` across (centred
on it; 1 is a single line) at its own level and the one below,
flying over the area in a snake and digging through anything in the
way. Every lava source it sees ahead of it or below it (a still one:
`turtle.inspect` shows `state.level` 0, flowing lava cannot be picked
up) is scooped with an empty bucket. In `refuel` mode each lava
bucket is burnt at once for 1000 fuel, and the turtle comes home as
soon as it has `targetFuel`. In `depot` mode it tops itself up to
`targetFuel` first, then fills every empty bucket, comes home, puts
the lava buckets in the chest for other turtles to refuel from and
takes back the empty buckets they left there (from the chest's first
stacks; anything else it takes out is put back). It never goes
further than its fuel can bring it back, burning a lava bucket it
carries rather than stopping short, and a target above the turtle's
fuel limit is refused. Without buckets it raises a `buckets` alert and
waits for some. The engine is `apis/lavafuel.lua`.

## Shared pieces

`apis/tracker.lua` is the careful mover these jobs share: it keeps the
turtle's position relative to its start, digs through what is in the
way and waits for sand and gravel to land before digging again,
attacks mobs standing in the way, gives up with the reason on bedrock,
and checks there is fuel for the way home (`t:hasFuelFor(n)`),
burning what it may and waiting with a fuel alert otherwise.
`apis/inventory.lua` gained `waitFor(check, kind, message)`, which
raises an alert and waits until the check passes, looking again when
items are put in, when space is pressed and every ten seconds;
`count(item)`, `findWhere(pred)`, `selectWhere(pred)`, and
`isBuildingBlock(name)` and `selectBuildingBlock(item)` for picking a
plain block to build with.

All five are in the turtle control job list with forms for their
options. The simulator has a scenario for each (Tunnel, Rail, Bridge,
Farm job, Lava fuel) with checks, and the built-in Farm and Lava
scenarios work with `farm 9 9` and `lavafuel 5000 3 refuel behind 3`.
The simulator has no powered rails, redstone torches or fences, so
those parts of `rail` and `bridge` are only covered by the unit tests;
liquids there do not flow, so plugging is only tested on still lava
and water.
