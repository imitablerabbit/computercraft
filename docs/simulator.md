# Simulator: peripherals, redstone, farming and GPS

The browser simulator (see the README) covers more of the game than
turtles and monitors. This page describes those parts.


Computers now see the blocks around them the way the game does. A chest,
disk drive, energy cell, tank or another computer next to a computer or
turtle is a peripheral on that side (`left`, `back`, `top` ...), and
placing or digging one fires `peripheral` and `peripheral_detach`. A
computer faces north unless its definition gives a `heading` (0 north, 1
east, 2 south, 3 west, like turtles), so for one facing north `front` is
the block to the north and `right` the one to the east. A side taken by
a modem or monitor from the definition shows that instead of the block.

A wired modem (`{ type: 'modem', wired: true, network: 'storage' }` in a
definition) reaches every block put down with the same `network` in its
meta, under the game's names: `minecraft:chest_0`, `drive_1`,
`thermal:energy_cell_0`, and `computer_<id>` or `turtle_<id>` for
computers whose own wired modem is on that network. They show up in
`peripheral.getNames()` after the modem's side, and the modem has
`getNamesRemote`, `isPresentRemote`, `getTypeRemote`, `hasTypeRemote`,
`getMethodsRemote`, `callRemote` and `getNameLocal`. Chests are
CC: Tweaked's generic `inventory` (`size`, `list`, `getItemDetail`,
`getItemLimit`, `pushItems`, `pullItems`), so `peripheral.getType` gives
`minecraft:chest` and `inventory` and `peripheral.find("inventory")`
finds them. As in the game, `pushItems` reaches other inventories on the
same network, or other ones beside the computer, and a turtle's name on
the network works as a target. Energy cells give `getEnergy` and
`getEnergyCapacity`, tanks `tanks()`, and both drift slowly up and down.
Modems carry `transmit` and `modem_message` between computers with the
channel open, with the distance between them; rednet works as before.

Redstone goes both ways. Levers, buttons (one second), pressure plates,
daylight sensors and blocks of redstone power what touches them and any
wire running from them, losing a level per block of wire. Computers and
turtles read that with `redstone.getInput` and `getAnalogInput` and get a
`redstone` event when it changes, and their own outputs light redstone
lamps, open iron doors and fire reconstructors on the block at that side
or along wire. Bundled cable carries `setBundledOutput` colours between
the computers it touches. The Click control's Use option flips levers,
presses buttons and steps on plates; a scenario can do the same on a
timeline.

Crops (wheat, carrots, potatoes) grow on farmland a step every 5
simulated seconds up to age 7, which `turtle.inspectDown` shows as
`state.age`. Digging one gives what the game gives (a mature wheat gives
wheat and 1 to 4 seeds, mature carrots and potatoes 1 to 4, anything
younger one seed back), and seeds placed down onto farmland from above
plant a new crop. A turtle with a diamond hoe equipped (`turtle.equipLeft`)
tills dirt or grass in front of it into farmland. An empty bucket placed
at a lava or water source picks it up, and `turtle.refuel` on a lava
bucket gives 1000 fuel and leaves the bucket. Rails need a solid block
under them; cobblestone, stone, planks, glass, stone bricks and torches
all place with the game's names, and `turtle.inspect` reports them as the
game does (grass is `minecraft:grass_block`).

`gps` works as in CraftOS: `gps host <x> <y> <z>` answers on channel
65534 until stopped, and `gps.locate` or `gps locate` on a computer with
a wireless modem finds its Minecraft coordinates once four hosts answer.
Our y north is the game's -z and our z up the game's y, so a block at
(x, y, z) here is at (x, z, -y) in game terms.

A turtle can build its own: placing a computer item puts down a computer
that is off, has an empty disk and faces the turtle; a wireless modem
placed into the gap in front of a computer sticks to it on that side; a
disk drive is a block, and dropping a floppy into it mounts the floppy at
`disk/` for every computer beside it (`disk.isPresent`, `getMountPath`,
`hasData` ...). A computer wrapped as a peripheral can be `turnOn`,
`shutdown`, `reboot`, and asked `getID`, `isOn` and `getLabel`; when it
starts it runs `startup.lua` from its own disk or else
`disk/startup.lua`. Digging a computer gives the item back (with its id,
label and files if it has a label) and any modem stuck to it.

New scenarios, each with a short note in the top bar:

- **Storage network**: a computer with a wired modem, six chests of
  assorted items, an output chest and a monitor on one network. Try
  `pushItems` from one chest to `minecraft:chest_6`.
- **Redstone**: a computer with a lever, lamp, iron door, button and wire
  around it, bundled cable to a second computer, and a timeline that
  flips the lever, presses the button and steps on the plate.
- **Farm**: a 9x9 field of mixed crops around a water block, with a
  turtle with seeds over the corner and a chest behind it.
- **Lava**: a lava pool and a turtle with 16 buckets and almost no fuel.
- **GPS**: four gps hosts at different heights and a turtle; type
  `gps locate` in the turtle's shell.
- **GPS deploy**: a turtle with 4 computers, 4 wireless modems, a disk
  drive and a floppy, on empty ground.
- **Machines**: a computer beside an energy cell, networked to a tank and
  another cell.

A scenario can script a player with a `timeline`: entries like
`{ at: 10, action: 'toggle', pos: { x, y, z } }` (a lever, or holding a
pressure plate down), `press` (a button, or a quick step on a plate),
`step` with `seconds`, `give` with `turtle`, `item` and `count`, `place`
and `remove` a block, `type` a line into a `computer`, and `turnOn`,
`shutdown` or `reboot` a computer.
