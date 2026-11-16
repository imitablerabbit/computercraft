# Computercraft APIs and commands 

Various APIs and commands for the computers and turtles in the Computercraft Minecraft mod.

## Turtle control monitor

`turtlecontrol` is a touch dashboard for mining turtles. It runs on a
computer that has a wireless modem and an advanced monitor attached (touch
only works on advanced monitors), or, when there is no monitor, on the
computer's own screen with the mouse, which makes it usable on an advanced
pocket computer with a wireless modem (`turtlecontrol term` forces that).
On a narrow screen the main grid uses small text tiles, the move pad has
four columns, job parameters take two rows each, and the shell and text
screens also accept the computer's keyboard. The main screen shows an icon for every
turtle it can hear, coloured by what the turtle is doing: green when idle,
orange with a pickaxe while a job runs, red after a job fails and gray once
the turtle has gone quiet. Map (top right) shows the fleet from above,
see [Fleet map](docs/fleet.md#fleet-map).

Touch an icon to open that turtle's screen. At the top it shows the
turtle's state and job, a fuel bar and the last message. The fuel bar
counts 2000 fuel as full, so the bar is useful whatever the fuel limit,
and the real numbers are written over it. Below 200 fuel it turns red.
While a job reports how far along it is (see Job progress below), a
second bar shows that, for example `17/512 layer 1 of 8`. On wide screens
a small chart beside the icon shows the fuel level from recent status
messages, with the highest and lowest values at its left. Under that are
buttons for the jobs in `apis/turtlectl.lua` (strip mine, mine line,
quarry, flatten, logger, reconstruct, tunnel, rail, bridge, farm, lava
fuel, build, go to, GPS deploy, depot, refuel) and Stop.

On a wide screen (a monitor, or an advanced computer's own screen) the
turtle's other screens are tabs along the top: Jobs, Items, Move, Shell
and Fuel, with Back at the right end of the tab row. On a compact screen
(under 40 columns or 16 rows, such as a pocket computer or a small
monitor) the tab row would not fit, so the turtle screen keeps Items,
Fuel, Move, Shell, Stop and Back as buttons that each open a screen of
their own, as before. Mine line has a Return switch that walks the
turtle back to where it started once the line is done, so it can be run
again from the same spot.

Fuel lists the items the turtle never burns as fuel (`inventory.FuelBlacklist`,
kept in a `fuel_blacklist` file on the turtle so it survives reboots), in a
scrolling list with a Remove button each, Add carried item to pick one of the items it is carrying
through the same Discover list, and Add by name for the keyboard. There is no
whitelist: anything the game accepts as fuel and is not listed may be burnt.
The logger adds its sapling to the list when it starts.

Items shows the turtle's inventory as the same 4x4 grid as `inventorygui`
below, with the fuel and block icons, and asks the turtle for a fresh copy
every few seconds while it is open. Touching a slot opens its details with
Select, Refuel (one item) and Drop buttons that act on the turtle; the agent
refuses them while a job is running. During a job the fuel icon can only be
shown for items the turtle has already checked, because checking means
selecting the slot.

A job with parameters opens a form first: numbers have -10, -1, +1 and +10
buttons, switches are checkboxes, choices such as the chest side are
dropdowns that open a list on touch, and text values open an on screen
keyboard. A text value with suggestions, such as the logger's sapling, is a
dropdown too, listing the vanilla saplings with Discover... and Other...
at the end. Discover... asks the turtle what it is carrying and offers
those items in a second dropdown, saplings first, so the exact name never
has to be typed; Other... opens the keyboard, and a typed name then shows
at the top of the list. Start sends the job with those values, which are remembered per
turtle for next time. Each job's parameters, defaults and limits are the
`params` table of its catalogue entry in `apis/turtlectl.lua`, one entry per
program argument in order, so adding a program means adding one entry there.

Move is a pad of single steps and actions: forward, back, turn, up, down,
dig, place, suck and drop, each one touch. The result of the last action and
the fuel level are shown above the pad. Moves are refused while a job runs.

Shell is a remote command line. Type with the on screen keyboard (Shift
toggles upper case, `<` and `>` move the cursor so text can be inserted or
deleted in the middle of the line) and touch Run to run the line on the
turtle through its shell, as if typed at its own terminal. The same
keyboard edits text values on the job forms. The output streams back to the
monitor, capped at 200 lines per command, and the turtle shows as working
until the command finishes. Stop aborts it, which is also the way out of a
command that waits for keyboard input, since there is no way to type into a
running program.

Stop, Drop on an item's screen and Remove on the fuel rules ask first, in
a box in the middle of the screen with Cancel and the action in red.
Nothing underneath can be touched until one of them is pressed. On a
pocket computer, Enter presses the action and Escape cancels. Stop only
asks while a job is running. When the turtle is idle there is nothing to
stop, and the turtle answers "nothing running" as before.

Setup:

1. On each turtle, attach a wireless modem and run `turtleagent`. It
   broadcasts its status every 5 seconds, answers the monitor's requests and
   runs the job it is told to. Label the turtle first (`label set Digger`)
   so the dashboard shows a name instead of an ID.
2. On the monitor computer, run `turtlecontrol`. Optional arguments are the
   monitor side, the text scale (by default the largest that still gives at
   least 50x20 characters, which is 0.5 on monitors up to 4 blocks wide) and
   a registry file from
   `registrylistener`, whose turtles are shown as offline until heard from.

```
turtlecontrol [monitorSide|term] [textScale] [registryFile]
turtleagent [heartbeatSeconds]
```

Stop aborts the running job on the turtle, which is left wherever it got to.

When a turtle needs a hand its icon turns red and blinks NEEDS HELP with
what it needs (NEEDS FUEL, NEEDS CHEST, ...), and its screen shows the
message in red. The programs raise these through `apis/alert.lua`: running
out of fuel (the turtle then waits, and carries on by itself once fuel is
put in), no chest or a full chest to empty into, no torches left, no
saplings left, and for `reconstruct` an empty input chest or a machine
that stops working. `turtleagent` passes alerts to the controller and clears
them when the job ends, so any program can call `alert.raise(kind,
message)` and `alert.clear(kind)` to be shown the same way.

When the turtle has nav state (see [Navigation](docs/navigation.md)),
`turtleagent` also sends its position with every status. When it starts
on a turtle with a wireless modem and four gps hosts in range, it
calibrates nav once by moving one block and back to learn its heading,
and asks gps again after every job. Without gps it never moves by itself.
It also publishes its status and alerts on the event bus, so the pocket
`pager` sees them (see [Pager, alerts, event bus and
GPS](docs/network.md)).

### Job progress

Long jobs say how far along they are through `apis/progress.lua`, the
same way alerts work. `progress.report(done, total, text)` queues a
`turtle_progress` event. `turtleagent` keeps the latest one and sends it
to the controller with its status, as a `progress = { done, total, text
}` field (at most every 2 seconds, plus the 5 second heartbeat). The
turtle screen shows it as a progress bar. `progress.clear()` takes it
away, and the agent clears it when the job ends. Without the agent the
calls do nothing and print nothing, so a program can report every block.
`total` may be nil when the end is not known, and the bar then only shows
the text. Controllers from before this change ignore the field.

## More programs

Each of these has its own page under `docs/`:

- [Turtle jobs](docs/turtle-jobs.md): `tunnel` bores a lit, walkable
  tunnel; `rail` lays a railway; `bridge` builds a floor across a gap;
  `farm` harvests and replants a field of crops; `lavafuel` refuels from
  a lava lake or fills buckets for a fuel chest.
- [Navigation and building](docs/navigation.md): the `nav` API tracks a
  turtle's position, calibrates with gps and finds paths with A*;
  `goto` and `where` use it from the shell; `build` builds a structure
  from a blueprint file and `scan` records one into a blueprint.
- [Fleet](docs/fleet.md): `dispatcher` keeps a queue of jobs and hands
  them to idle turtles, sending each to its job site first; `depot`
  tells turtles where the nearest fuel and dump chests are, so
  quarries can empty themselves wherever they are; and the map in
  turtle control.
- [Pager, alerts, event bus and GPS](docs/network.md): `pager` lists
  every alert in the base on a pocket computer; the `bus` API is a
  publish and subscribe layer over rednet; `alert` and `turtlejob` raise
  alerts and start jobs from the shell; `gpsdeploy` builds a gps
  constellation from one turtle.
- [Base automation](docs/base-automation.md): `storage` runs a chest
  network with search, withdraw and deposit; `doors` drives lights and
  doors on schedules and sensors; `machines` watches energy, tanks and
  inventories and switches generators; `lift` dispatches an elevator or
  train between stops.
- [Testing](docs/testing.md): the `test` program and `testing` API for
  unit tests that run in game and in the simulator, the scenario file
  format, and scenario checks.

## Quarry and flatten

`quarry` digs a box straight down and `flatten` clears one straight up; both
bring what they dig back to a chest. Put the turtle on the near edge of the
area, looking along it, with a chest next to it:

```
quarry [width] [length] [depth] [chest] [start]     defaults 8 8 8 left left
flatten [width] [length] [height] [chest] [start]   defaults 8 8 4 left left
```

`start` says where on the near edge the turtle stands: `left` (width is
all to its right), `right` (width is all to its left) or `middle` (width
spread both ways; an even width puts the extra column on the right).
`chest` says where the chest is relative to the turtle's starting block
and heading: `left`, `right`, `behind`, `below` or `above`. A side that is
inside the area to clear is refused. A quarry is all below the turtle, so
only `below` is out; flatten clears the turtle's own layer, so with a left
start the chest cannot be on the right, with a right start not on the
left, and from the middle it goes behind or below. The same
chest argument ends `stripmine` (default left) and `logger` (default
behind). In the turtle control forms Start and Chest are dropdowns, and
the Chest list only offers the sides outside the box for the current
start and width. The turning, dropping and turning back is
`inventory.dumpTo(side, keepSlots)` in `apis/inventory.lua`, so any program
that empties itself can take the same option.

Length is straight ahead. For a quarry the first layer is the one under
the turtle, so it can stand on the ground; for flatten the first layer is
the turtle's own, so it can stand beside the hill. Each layer is cleared
in a snake pattern before moving to the next; from a middle start the
turtle first works along the near edge to the closer corner.
Whenever the inventory is full, and once the job is done, the turtle goes
back to its starting block, turns to the chest and empties itself, then
returns to where it left off. Without a chest on the left it keeps the
items. If it hits bedrock or something it cannot dig through it gives up,
goes home and empties itself, and reports why. When fuel runs lower than
the way home it burns fuel it has dug up (coal, logs, ...) rather than
stopping. Both are jobs in the turtle control job list with forms for the
three sizes; the engine is `apis/excavate.lua`.

The chest can also be `depot`, for quarry, flatten and strip mine. The
turtle then empties at the nearest dump chest a depot computer knows
about, straight from wherever it fills up, and comes back to carry on.
That needs gps and a running `depot`; see [Depot](docs/fleet.md#depot).

## Reconstruct

`reconstruct` works a block-changing machine: it feeds blocks from a chest
one at a time to something that changes the block in front of the turtle
when it gets a redstone pulse, digs the result and drops it into another
chest. The first use is an Actually Additions atomic reconstructor with a
lens of the miner, which turns netherrack into nether quartz ore, nether
gold ore and, rarely, ancient debris; anything that turns the block in
front of the turtle into another block on a pulse works the same way, with
whatever blocks it accepts.

```
      M .          M = the machine, aimed at the block space in front
    = T C          of the turtle; = redstone from the turtle's left
      I            face to the machine; I = input chest; C = output chest

reconstruct [input] [output] [pulse] [stacks] [delay]   defaults behind right left 0 0.5
```

The turtle takes one stack from the input chest, then for every block in
it places the block in front, pulses the redstone, waits `delay` seconds,
checks that the block changed (pulsing again a couple of times if not) and
digs it. When the stack is gone it empties itself into the output chest and
takes the next one; `stacks` limits how many, 0 runs until stopped. The
turtle never moves, so it needs no fuel. `input` and `output` are chest
sides as above (`left`, `right`, `behind`, `below`, `above`) and `pulse` is
the turtle side wired to the machine (`left`, `right`, `back`, `top`,
`bottom`); the turtle faces front while it works, so all of them are
relative to how it was placed. A side used twice is refused.

When the input chest is empty, the output chest is missing or full, the
item will not place, or the block stops changing (the machine out of power
or aimed wrong), the turtle raises an alert, waits ten seconds and tries
again, so fixing the setup lets it carry on. Unchanged blocks are dug back
into the stack and fed again. The job is in the turtle control list with a
form for the three sides and the stack count; the loop is
`apis/reconstruct.lua`, whose `run` takes the same options as a table.

## Turtle inventory viewer

`inventorygui` runs on a turtle and shows its 16 slots as a 4x4 grid on the
turtle's own screen, with the fuel level in the title bar. A filled slot
shows the item name and count, the selected slot is marked with a `*`, and
two icons say what the item is good for: an orange `F` means the turtle can
burn it as fuel, a green `B` means it looks like a block that can be placed.
The fuel check asks the turtle itself (`turtle.refuel(0)`, which burns
nothing). ComputerCraft does not say whether an item is placeable, so the
block icon is a guess from the item's creative tab and tags when the game
reports them (CC: Tweaked) and from its name otherwise; expect the odd miss
on modded items. The reading and classifying lives in `apis/turtleinv.lua`
and the grid in `apis/gui/inventorygrid/`, which `turtleagent` and
`turtlecontrol` use to show the same view remotely.

Press a slot (mouse on an advanced turtle, or arrow keys and Enter on a
plain one) to open its details: name, display name, count and stack size,
damage, the fuel and block verdicts and the item's tags. The buttons at the
bottom act on that slot: Select makes it the turtle's selected slot, Refuel
burns one item from it, Drop drops the stack in front of the turtle, and
Back returns to the grid (Backspace does the same, Q quits). The grid
follows inventory changes as they happen.

```
inventorygui
```

## GUI examples

`programs/gui/examples/` has small programs that show the GUI framework in
`apis/gui/`, meant to run on a computer's own screen with the mouse:

- `button` and `input`: the original counter and text field examples.
- `form`: a settings form built with layouts (a vertical box of rows, each
  a horizontal box of a fixed label and a flexible field) using a text
  input, checkboxes, a dropdown and a row of buttons in a grid.
- `files`: a file browser whose rows live in a scroll pane; Open enters a
  directory, Up leaves it, and the list scrolls with the bar, paging and
  the mouse wheel.
- `todo`: a to do list with an input, Add, a checkbox per task, Remove and
  Clear done, kept in `todo.dat`.
- `layout`: a playground where buttons switch a container between
  vertical, horizontal and grid layouts, change the gap, and make one box
  fixed or flexible.
- `widgets`: the newer components together, built with `guibuild`. A
  Meters tab has a job progress bar, a fuel bar that turns red below 20%,
  an energy gauge, a tank gauge and a sparkline fed by a timer. An Items
  tab has a table: touch a column title to sort by it, touch it again to
  reverse, and touch a row to select it. Remove asks before taking the
  selected row out, Alert shows a message box, Quit asks first, and Theme
  switches between the dark and light themes.

The framework itself is described in `apis/gui/readme.md`. Besides the
original components it has a progress bar, a gauge, a sparkline, tabs, a
modal dialog with `confirm` and `alert` helpers, and a sortable,
scrolling table. It also has dark and light themes (`guitheme`), a helper
that picks a monitor text scale and says whether a screen is compact
(`guitheme.fit`), and `guibuild`, which builds a whole screen from one
nested table; `form` is now written that way.

Type the name at a computer's prompt, or pick it as what a computer runs
when adding one in the browser simulator.

## Browser simulator

`sim/` is a simulator for everything in this repo that runs in a web browser,
so programs can be tried without the game. The computers run the real Lua
files (Lua in the page through Fengari) against a stand-in for CraftOS, in a
small voxel world drawn in 3D. Start `serve.py` as described under
"Installing from your own machine" below, then open

```
http://localhost:8080/sim
```

The page needs internet access once to fetch Fengari and three.js from a CDN.
What it shows:

- **World**: the blocks, chests and turtles in 3D. Turtles move and turn
  with the game's timing, digging removes blocks, sand and gravel fall, and
  placing puts blocks down. Drag to orbit, wheel to zoom, click a turtle to
  select it, and tick Follow to keep the camera on it. The Click control
  switches the mouse to placing blocks (pick the type, click a block face
  to put one against it, chests and saplings included), adding a turtle
  (label, fuel and what it runs), a computer (with a modem on top) or a
  monitor of a chosen size for one of the computers, or removing any of
  those, for setting up a test world by hand. Added devices boot at once
  and get a screen tab like the scenario's own. A monitor that touches a
  computer is attached to it on that side (right, left, top, ...), as in
  the game; one that touches none joins the computer chosen in On as a
  networked monitor. A program that only looks for monitors when it
  starts, such as `turtlecontrol`, needs a reboot after a monitor is
  added.
- **Screens**: a tab for every computer screen and every monitor, drawn like
  the game. Click a screen to focus it and type: keys arrive as `key` and
  `char` events, Ctrl+T terminates, Ctrl+R reboots, Ctrl+V pastes a line.
  Clicking a monitor tab sends `monitor_touch`, clicking a computer screen
  sends `mouse_click`, so `turtlecontrol`'s buttons work.
- **Turtle**: position, heading, fuel and the 16 slots of the selected
  turtle (fuel items marked F), plus every chest's contents. Give puts
  items into the turtle as a player would, which is how to answer a fuel
  alert; click a slot first to put them in that slot.
- **Log**: every `print`, every rednet message and every turtle action.

Scenarios in the top bar set up the world and what each computer runs at
boot: turtle control (a computer with a 3x2 monitor running `turtlecontrol`
and three turtles running `turtleagent`, one almost out of fuel), quarry, reconstruct (a chest of
netherrack, redstone and an atomic reconstructor that picks nether quartz ore,
nether gold ore or ancient debris by the mod's weights of 3000, 500 and 1), flatten, strip mine, the
inventory viewer, a blank turtle with a shell, and worlds for storage
networks, redstone, farming, lava, gps, gps deploy and machines (see
[Simulator](docs/simulator.md)). Text-file scenarios add one for each
new program: tunnel, rail, bridge, farm, lava fuel, build, scan, maze
(goto), pager, gps deploy, the four base programs, fleet and depot.
Each computer boots
`startup.lua` first, so all the APIs are loaded, then its scenario command,
then drops to a shell where any program can be typed, for example
`quarry 4 4 3`. Reset rebuilds the world; Speed runs time faster.
`?scenario=quarry&run=quarry%203%203%202` on the URL picks the scenario and
the command the first turtle runs.

The same simulation runs headless under node for scripted checks:

```
cd sim && npm install
node headless.mjs quarry "quarry 3 3 2" 90
```

That prints every screen, the turtles, the chests and the log after the
given number of simulated seconds.

What is simulated: `term`, `window`, `paintutils`, `colors`, `keys`, `os`
events and timers, `fs` over the repo's files (writes stay in the page,
and floppies mount at `disk/`), `shell` with `ls`, `cd`, `cat`, `label`,
`programs`, `refuel` and `gps`, `peripheral` with monitors, modems
(wireless and wired, with channels), chests and other inventories, disk
drives, computers, energy cells and tanks, `rednet` between the
computers, `gps`, `vector`, `disk`, `parallel`, `textutils`, the
`turtle` API with fuel, an inventory, chests, equipping tools and modems,
crops, buckets and placing computers, and `redstone` both ways, analog
levels and bundled cable included. Not simulated: `http`, crafting, mobs
and players (only the timeline and the Use tool press plates; turtles do
not, as in the game), liquids flowing (a lava or water block stays where
it is put), wireless modem range, power carried through solid blocks,
repeaters and comparators, fluid transfers between tanks, audio discs,
printers and speakers, and items dropped on the ground (they are lost,
as is a chest's contents when it is dug and a floppy ejected from a
drive). Turtles still pass through torches and redstone wire, which the
game does not allow. Fuel values and the block guesses are the plain
Minecraft ones, so modded items will differ from your world.

Scenarios can also be written as text files in `sim/scenarios/`, listed
in `sim/scenarios/index.json`, and can carry checks of the world after a
run. `cd sim && node test.mjs` runs every unit test and scenario check;
see [Testing](docs/testing.md). Chests and other blocks as peripherals,
wired networks, redstone inputs, crops, lava, gps and turtles placing
computers are described in [Simulator](docs/simulator.md), with the
scenarios that show them.

## Installing on a computer in game

One command installs everything on a fresh computer or turtle. Type it
at the shell, or paste it with Ctrl+V:

```
wget run https://raw.githubusercontent.com/imitablerabbit/computercraft/master/programs/github.lua
```

It asks GitHub for the list of files on `master`, downloads every `.lua`
file to the same path on the computer (the browser simulator under `sim/`
is skipped) and asks you to `reboot`, after which `startup.lua` loads the
APIs and puts the `programs` folders on the path. From then on `github`
pulls the latest copies again, and `github <branch>` installs a branch
instead. Files deleted from the repo are not removed from the computer.
This needs the `http` API, which CC: Tweaked enables by default along with
access to GitHub's hosts.

### Installing from your own machine

To try changes before they are pushed, `serve.py` hosts this folder over
plain HTTP so computers in game can `wget` it. It needs nothing beyond
Python 3. On your machine, from this folder:

```bash
python3 serve.py
```

It listens on port 8080 (change with `-p`) and prints the exact command to
run in game, which is:

```
wget run http://<your-ip>:8080/install.lua
```

That downloads every `.lua` file into the same paths on the computer and
saves the installer as `update.lua`, so after the first install you can
just run `update` to pull the latest copies. Reboot afterwards so
`startup.lua` loads the new APIs.

Single files work too:

```
wget http://<your-ip>:8080/programs/turtle/stripmine.lua programs/turtle/stripmine.lua
```

`/files.txt` lists everything the server will hand out.

### If `wget` says the domain is blocked or the request fails

ComputerCraft refuses local and private addresses by default. For
CC: Tweaked, edit `computercraft-server.toml` (under `config/` on a server,
or `saves/<world>/serverconfig/` for single player) and either remove the
rule that denies `$private`, or add an allow rule above it:

```toml
[[http.rules]]
host = "<your-ip>"
action = "allow"
```

Older ComputerCraft versions use an `http_blacklist` line in
`computercraft.cfg` instead; remove the private ranges from it. Restart
the world or server afterwards.

### Running the server under WSL

Minecraft on the Windows side can reach the server at `http://localhost:8080`
or at the WSL address that `serve.py` prints. The WSL address changes on
reboot, so just run `update` with the new URL if the old one stops working:

```
update http://<new-ip>:8080/
```

Other machines on the LAN cannot see WSL directly. Either run `serve.py`
from Windows Python instead, or forward the port from PowerShell as admin
and allow it through the firewall:

```powershell
netsh interface portproxy add v4tov4 listenport=8080 listenaddress=0.0.0.0 connectport=8080 connectaddress=<wsl-ip>
```
