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

Items shows the turtle's inventory as the same 4x4 grid as `inventorygui`
below, with the fuel and block icons, and asks the turtle for a fresh copy
every few seconds while it is open. Touching a slot opens its details with
Select, Refuel (one item) and Drop buttons that act on the turtle; the agent
refuses them while a job is running. During a job the fuel icon can only be
shown for items the turtle has already checked, because checking means
selecting the slot.

A job with parameters opens a form first: numbers have -10, -1, +1 and +10
buttons, switches toggle on touch, and text values open an on screen
keyboard. Start sends the job with those values, which are remembered per
turtle for next time. Each job's parameters, defaults and limits are the
`params` table of its catalogue entry in `apis/turtlectl.lua`, one entry per
program argument in order, so adding a program means adding one entry there.

Move is a pad of single steps and actions: forward, back, turn, up, down,
dig, place, suck and drop, each one touch. The result of the last action and
the fuel level are shown above the pad. Moves are refused while a job runs.

Shell is a remote command line. Type with the on screen keyboard (Shift
toggles upper case) and touch Run to run the line on the turtle through its
shell, as if typed at its own terminal. The output streams back to the
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

## Quarry and flatten

`quarry` digs a box straight down and `flatten` clears one straight up; both
bring what they dig back to a chest. Put the turtle in the bottom left
corner of the area, looking along it, with a chest on its left:

```
quarry [width] [length] [depth]     defaults 8 8 8
flatten [width] [length] [height]   defaults 8 8 4
```

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
