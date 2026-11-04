# Computercraft APIs and commands 

Various APIs and commands for the computers and turtles in the Computercraft Minecraft mod.

## Turtle control monitor

`turtlecontrol` is a touch dashboard for mining turtles. It runs on a
computer that has a wireless modem and an advanced monitor attached (touch
only works on advanced monitors). The main screen shows an icon for every
turtle it can hear, coloured by what the turtle is doing: green when idle,
orange with a pickaxe while a job runs, red after a job fails and gray once
the turtle has gone quiet. Touch an icon to open that turtle's screen, which
shows its state and fuel and has buttons for the jobs in `apis/turtlectl.lua`
(strip mine, mine line, quarry, flatten, logger, refuel), plus Items, Move,
Shell, Stop and Back. Mine line has a Return switch that walks the turtle back to where it started
once the line is done, so it can be run again from the same spot.

Fuel lists the items the turtle never burns as fuel (`inventory.FuelBlacklist`,
kept in a `fuel_blacklist` file on the turtle so it survives reboots), with a
Remove button each, Add carried item to pick one of the items it is carrying
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

Setup:

1. On each turtle, attach a wireless modem and run `turtleagent`. It
   broadcasts its status every 5 seconds, answers the monitor's requests and
   runs the job it is told to. Label the turtle first (`label set Digger`)
   so the dashboard shows a name instead of an ID.
2. On the monitor computer, run `turtlecontrol`. Optional arguments are the
   monitor side, the text scale (default 0.5) and a registry file from
   `registrylistener`, whose turtles are shown as offline until heard from.

```
turtlecontrol [monitorSide] [textScale] [registryFile]
turtleagent [heartbeatSeconds]
```

Stop aborts the running job on the turtle, which is left wherever it got to.

When a turtle needs a hand its icon turns red and blinks NEEDS HELP with
what it needs (NEEDS FUEL, NEEDS CHEST, ...), and its screen shows the
message in red. The programs raise these through `apis/alert.lua`: running
out of fuel (the turtle then waits, and carries on by itself once fuel is
put in), no chest or a full chest to empty into, no torches left, no
saplings left. `turtleagent` passes alerts to the controller and clears
them when the job ends, so any program can call `alert.raise(kind,
message)` and `alert.clear(kind)` to be shown the same way.

## Quarry and flatten

`quarry` digs a box straight down and `flatten` clears one straight up; both
bring what they dig back to a chest. Put the turtle in the bottom left
corner of the area, looking along it, with a chest next to it:

```
quarry [width] [length] [depth] [chest]     defaults 8 8 8 left
flatten [width] [length] [height] [chest]   defaults 8 8 4 left
```

`chest` says where the chest is relative to the turtle's starting block
and heading: `left`, `right`, `behind`, `below` or `above`. A side that is
inside the area to clear is refused (below for a quarry, right and above
for flatten). The same argument ends `stripmine` (default left)
and `logger` (default behind), and the turtle control forms have a Chest
button that steps through the sides. The turning, dropping and turning
back is `inventory.dumpTo(side, keepSlots)` in `apis/inventory.lua`, so
any program that empties itself can take the same option.

Width is to the turtle's right and length straight ahead. For a quarry the
first layer is the one under the turtle, so it can stand on the ground; for
flatten the first layer is the turtle's own, so it can stand beside the
hill. Each layer is cleared in a snake pattern before moving to the next.
Whenever the inventory is full, and once the job is done, the turtle goes
back to its starting block, turns to the chest and empties itself, then
returns to where it left off. Without a chest on the left it keeps the
items. If it hits bedrock or something it cannot dig through it gives up,
goes home and empties itself, and reports why. When fuel runs lower than
the way home it burns fuel it has dug up (coal, logs, ...) rather than
stopping. Both are jobs in the turtle control job list with forms for the
three sizes; the engine is `apis/excavate.lua`.

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

## Browser simulator

`sim/` is a simulator for everything in this repo that runs in a web browser,
so programs can be tried without the game. The computers run the real Lua
files (Lua in the page through Fengari) against a stand-in for CraftOS, in a
small voxel world drawn in 3D. Start `serve.py` as for installing, then open

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
and three turtles running `turtleagent`, one almost out of fuel), quarry, flatten, strip mine, the
inventory viewer and a blank turtle with a shell. Each computer boots
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
events and timers, `fs` over the repo's files (writes stay in the page),
`shell` with `ls`, `cd`, `cat`, `label`, `programs` and `refuel`,
`peripheral` with monitors and modems, `rednet` between the computers,
`parallel`, `textutils` and the `turtle` API with fuel, an inventory and
chests. Not simulated: `http`, `gps`, redstone, crafting, mobs and liquids.
Fuel values and the block guesses are the plain Minecraft ones, so modded
items will differ from your world.

## Installing on a computer in game

The game can only fetch files over HTTP with `wget`, so this repo ships a
tiny server that hosts it from your own machine. It needs nothing beyond
Python 3.

On your machine, from this folder:

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
