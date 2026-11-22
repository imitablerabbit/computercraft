# Base automation

Four programs run plain computers around the base: `storage` (a chest
network), `doors` (lights and doors), `machines` (energy, tanks and
inventories) and `lift` (an elevator or train dispatcher). Each one is
a touch panel built on the GUI framework. It goes on the first advanced
monitor it finds, or on the monitor named as the first argument, or on
the computer's own screen with `term` (an advanced computer or pocket
computer, used with the mouse). With the panel on a monitor, the
computer's own screen logs what happens and has a prompt for commands
(`help` lists them, `quit` stops the program). On the own screen, a
line pasted with Ctrl+V runs as a command. Only one panel can use a
monitor at a time: started again in another multishell tab (from the
desktop, say), a panel takes the next free monitor, or says which
program has the monitor it was given. Settings are kept in a file
in the computer's root (`/storage.cfg`, `/doors.cfg`, `/machines.cfg`,
`/lift.cfg`), which is written with defaults the first time and can be
changed from the panel or with commands. What they do is published on
the bus (see [the event bus](network.md#event-bus)), and anything a person should look at is
an `alert`, so the pocket pager shows it. A pager that starts later
asks for active alerts (`alert.sync`) and these programs answer.

The logic lives in APIs with unit tests (`apis/storage.lua`,
`crafting.lua`, `circuits.lua`, `machines.lua`, `lift.lua`). `apis/basepanel.lua` is the
shared frame: picking the screen, the command prompt, bus alerts.

## Storage

`storage` keeps an index of a network of chests. Put a computer with a
wired modem on the same cable as the chests. One chest is the input,
where items are put to be stored, one is the output, where requested
items come out, and every other inventory on the network is storage.

```
storage [monitor|term] [input output]
storage request <item> [count]
```

`input` and `output` are the chests' names on the network
(`minecraft:chest_6`); given once, they are saved. Without them the
panel opens on Settings, where both are picked from a list.

All the chests have to be on the same wired network. A chest touching
the computer is also seen under the name of that side (`left`, `top`
...), and the chests on the cable cannot push items to or from that
name. So side chests are never storage and are not offered in
Settings, and an input or output chest set to a side opens Settings
with a message saying to put a wired modem on it and pick its network
name. A setup with no cable at all, where every chest touches the
computer, still works with side names.

The Items tab lists everything stored with its count. Touch a row to
pick an item, then 1, 16, 64, Stack or All to send that many to the
output chest, or put a number in the box and press Get. A request is
split over as many slots as needed, taking the smallest stacks first so
partial stacks are used up, and honours stack sizes (a stack of ender
pearls is 16). If the output chest fills up, what was sent is reported
with why it stopped. Find narrows the list by name or display name, x
clears it, and the button next to it sorts by count or name.

On a monitor, touching the Find box or the amount box opens an
on-screen keyboard over the panel: digits, letters, `_ : . -`, Aa for
capitals, Space, Del, Clear, Cancel and Done. The search keyboard
shows how many items match as you type; Done applies it. The keys are
three lines high on a big monitor and one line on a small one. Any
text box in the GUI framework does the same on a monitor (see
`apis/gui/readme.md`). Deposit moves everything
in the input chest into storage, topping up stacks of the same item
first, then empty slots in chests that already hold that item, then any
empty slot. Auto deposits by itself every 10 s to 5 minutes. The bar at
the top is the storage slots used; it turns red and raises a `storage`
alert at 90% (set in Settings), cleared again under 85%.

Peripheral calls take a game tick each, so every chest is listed in
parallel (32 at a time) and the index is then kept up to date from what
the program moves rather than listed again. Everything is re-listed
every minute, and Re-index does it at once, to catch changes made by
hand. Items with NBT data (enchanted books, named items) are kept apart
from plain ones, as they do not stack.

Sort chests (on Settings, or the `sort` command) tidies storage up.
It first pours partial stacks of the same item together, so each item
takes as few slots as it can. Then it lays the items out one kind
after another in name order (`minecraft:coal`, `minecraft:cobblestone`
...), filling the first chest slot by slot, then the next, so the free
slots all end up at the end. A stack in the way is moved aside to a
free slot first, so at least one slot must be free. Each slot takes at
most two moves, and a move is a game tick. The sort runs 16 moves at a
time, with deposits, requests and Get in between, and the status line
counts the moves. When the chests change under it, by this program or
by hand, it plans the rest again. Pressing the button again (it reads
Stop sorting meanwhile) or `sort stop` stops it.

A turtle with a wired modem on the same network can ask for items over
the bus: `storage request coal 16` at its prompt, or
`storage.request(item, count)` from a program such as a builder
restocking. The storage computer pushes them straight into the turtle
(it is `turtle_<id>` on the network) and answers with how many it sent.

Commands: `get <item> [count|stack|all]`, `deposit`, `find <text>`,
`refresh`, `sort [stop]`, `craft <recipe> [count|max]`, `craft stop`,
`recipes [all] [text]`, `auto <seconds>`, `input <chest>`, `output <chest>`,
`craftchest <chest>`, `list`.

### Crafting

Storage can craft from what it holds, with a crafty turtle (a turtle
with a crafting table equipped) doing the crafting. It comes with
built-in recipes, and you can add your own.

Setting it up:

1. Put a new chest on the storage cable, with a wired modem on it, and
   pick it as the crafting chest on Settings (or `craftchest
   minecraft:chest_9`). It is no longer used as storage.
2. Put a crafty turtle beside that chest, with the chest in front of
   it, above it or below it, and run `crafter` on it (in its startup
   file, so it comes back after a restart). Leave the turtle empty.
3. The turtle needs a modem the storage computer can reach. Give both
   a wireless modem (a crafty wireless turtle has the crafting table on
   one side and the modem on the other), or touch the turtle with a
   wired modem block on the storage cable.

The Craft tab's top line says when the crafter has been heard
("Crafter Crafty 6 is ready").

To make a recipe, open the Recipe tab. Touch a square of the 3x3 grid
and type part of an item's name on the on-screen keyboard; the line
under the text shows what it finds. Done fills the square when one
item matches, or lists the matches beside the grid to touch. Done with
nothing typed, or Empty square, empties it. Give the recipe a name,
or leave it blank, and press Save. A recipe learns what it makes, and
how many, the first time it is crafted, and a recipe saved without a
name then takes that item's name. Edit on the Craft tab loads a recipe
back into the grid, and Delete removes it. Recipes are kept in
`/recipes.cfg`.

The built-in recipes are in `apis/recipebook.lua`. They cover the
vanilla (1.20 and later) and CC: Tweaked recipes a base uses most:
- planks, slabs, stairs, fences, gates, doors, trapdoors, signs,
  pressure plates, buttons and boats in every wood;
- sticks, chests, crafting tables, barrels, ladders and torches;
- wooden, stone, iron, golden and diamond tools;
- leather, iron, golden and diamond armour;
- furnaces, glass panes, rails, hoppers, pistons and redstone parts;
- storage blocks and back;
- computers, turtles, monitors, modems and cables.

They aren't saved to `/recipes.cfg`, and they already know what they
make. Recipes that take any planks, logs, coal or cobblestone use a
tag such as "Any planks". Each batch uses the kind that storage has
most of. On the Craft tab:
- **Can make** shows your own recipes and the built-in ones that
  storage has the items for. Touch it to switch to **All**.
- **Find** narrows the list by name.
- **Edit** on a built-in recipe saves a copy of it, which then replaces
  the built-in one. Delete the copy to get the built-in one back.

`recipes` at the prompt lists the same as Can make; `recipes all door`
lists every recipe with "door" in its name.

To craft, touch a recipe on the Craft tab and press 1, 16, 64 or Max,
or put a number in the box and press Craft. The number is how many
items to make; Can shows how many the storage has the ingredients
for. A recipe that has never been crafted makes one craft first, to
learn its output, and then the rest. `craft stick 64` does the same
from the prompt.

Each round, the storage puts away anything in the crafting chest and
moves the ingredients in, one square to a chest slot (square 1 in
slot 1 and so on), up to a stack of each. It then asks the turtle over
the bus. The turtle sucks the slots into its own crafting grid,
crafts, and drops what it made back into the chest. The storage puts
that away and starts the next round, until it has made the number
asked for or runs out of an ingredient. Stop (the New button while
crafting) or `craft stop` stops after the round under way. When the
turtle does not answer in time, or reports a problem, the storage puts
the ingredients away again and says why.

### Storage remote

A pocket computer, or any computer, can use the storage at the base
from afar with `storage remote`. It has the same Items and Craft tabs,
and items come to the player's own chest on the storage network. That
is usually an ender chest whose other half the player carries.
Several people can each have their own chest and pocket computer on
one storage.

Setting it up:

1. Give the storage computer a wireless (or ender) modem, besides its
   wired one. The pocket computer needs one too, in range.
2. Put each player's chest on the storage cable with a wired modem.
   An ender chest from a mod such as EnderStorage works, with the
   matching one carried or placed where the player is. Any inventory
   whose network name has `ender_chest` in it is never used as
   storage, even before it is picked.
3. On the pocket computer, run `storage remote` (Storage remote on the
   desktop) and pick the chest on its Settings tab. The storage
   computer remembers which chest is whose, by computer id. A chest
   already picked by someone else is refused.

Then:

- **Get** (1, 16, 64, Stack, All, or a number) sends items to your
  chest.
- **Deposit** empties your chest into storage. Auto deposits every few
  seconds.
- **Craft** asks the base to craft one of its recipes, built-in or
  saved. The results go into storage, ready to get. Recipes are made
  at the base.
- **Find** and the sort button work on the list the base sends, which
  is fetched again every minute and after every deposit. Refresh on
  Settings fetches it at once.

The first storage computer that answers is used, and remembered in
`/storageremote.cfg`. Find storage on Settings looks again. At the
base, `remotes` lists the remote chests and `unremote <id>` forgets
one. The pocket's commands are `get`, `deposit`, `find`, `refresh`,
`craft`, `recipes`, `auto`, `chest <name>` and `list`.

## Doors and lights

`doors` drives the redstone on the sides of a computer as named
circuits: lights, doors, gates, bells. A circuit's output is a side
(`back`), or one colour of bundled cable on a side (`back:white`), so
several circuits can share a side. Each has a mode:

- manual: on or off from the panel, remembered across restarts.
- schedule: on between two times of the Minecraft day (`os.time()`),
  for example 18:30 to 6:00, across midnight.
- sensor: follows a redstone input such as a pressure plate or a
  daylight sensor, and stays on for a delay after it goes off, so a door
  closes 3 s after the plate is left.
- pulse: on for a moment (1 s by default) when touched, or when its
  input comes on.

```
doors [monitor|term] [configFile]
```

The Panel tab has a button per circuit, green when on and grey when
off, with why (`schedule until 06:00`, `closing in 2s`). Touching a
manual circuit switches it, a pulse fires, and a schedule or sensor is
overridden until its own rule next changes its mind, so lights switched
off by hand still come on again at dusk. Invert drives the output the
other way round. The Edit tab picks a circuit and changes its name,
mode, output and input (side and colour), times, delay and Invert, or
adds a new one; Del asks before removing one and switches its output
off. Every change is published as `base.circuit` { name, state, mode,
reason }.

Commands: `toggle|on|off <name>`, `add <name> manual <out>`,
`add <name> schedule <out> <on> <off>`, `add <name> sensor <out> <in>
[delay]`, `add <name> pulse <out> [seconds] [in]`, `remove <name>`,
`list`, `time`. A name may have spaces: `add Hall lights schedule right
18:30 6:00`.

## Machines

`machines` is a dashboard for every machine the computer can see, next
to it or on its wired network: energy stores (anything with
`getEnergy`), tanks (`tanks`) and inventories (`size` and `list`).

```
machines [monitor|term] [configFile]
```

Each machine gets a gauge per reading with the numbers (`37% 372k/1.0M
FE`) and a small chart of its recent history. Touch a machine's name
for the Details tab, which lists every reading it offers (each `get...`,
`is...`, `list`, `size` and `tanks` method; nothing that changes the
machine is called). The Alerts tab lists active alerts and the rules.

Rules raise alerts with hysteresis. The default is energy below 20%,
cleared again above 90% (kind `power`), and an inventory above 95% full,
cleared below 80% (kind `full`). A rule can also switch a redstone
output while its alert lasts, such as a backup generator:
`rule energy below 20 clear 90 top` replaces the default energy rule
with one that turns the top side on. One bus alert is kept per kind,
naming every machine in that state. Tanks do not say how much they
hold, so a tank's gauge is measured against the most it has been seen
to hold unless `capacity <tank> <mB>` sets it. `log <file>` keeps a CSV
of every reading (time, machine, metric, value, max), moved to
`<file>.1` when it passes 20 kB.

Commands: `list`, `show <machine>`, `rules`, `rule <metric>
below|above <percent> [clear <percent>] [side] [machine]`, `unrule <n>`,
`capacity <tank> <mB>`, `log <file>|off`, `scan`. Machines attached or
removed are picked up by themselves.

## Lift

`lift` dispatches one vehicle, an elevator car or a train, between a
line of stops using only redstone, so it suits Create elevators (a
redstone contact per floor) and train stations (a redstone link per
station) alike. Each stop has a call input (a button at that floor
wired back to the computer), a send output that makes the vehicle go
there, and optionally an arrived input that is on while the vehicle is
at that stop. All of them are a side or a side and bundled colour.

```
lift [monitor|term] [configFile]
```

The panel lists the stops with the highest at the top, marks where the
vehicle is (`[#]`), where it is going (`>`) and which stops are called
(`*`), and has a Call button per stop. Calls are queued once each. The
next stop is chosen by the algorithm: `look` (the default) takes the
nearest call in the direction of travel and turns round when there is
nothing more ahead, as elevators do; `fifo` serves calls in order;
`scan` runs to the end of the line before turning round. The send
output is pulsed for a second, or with Hold kept on until the vehicle
is sent elsewhere. Without an arrived input the vehicle is assumed to
arrive 4 s per stop after it was sent; a trip to a stop with one that
does not arrive within a minute raises a `lift` alert. After arriving
it waits 3 s before the next trip. Calls, departures and arrivals are
published as `base.lift` { event, stop, position, queue, state }.

Commands: `call <stop>`, `arrived <stop>` (to say where the vehicle is),
`stop <name> <call> <send> [arrived]` (add a stop at the top of the
line, or change one; `-` for no signal), `unstop <name>`, `algorithm
look|fifo|scan`, `hold on|off`, `pulse|travel|dwell <seconds>`, `list`.

Limits: the vehicle is sent one stop at a time, so a call between it
and its destination is served on the way back rather than on the way
past. Times are measured on the computer's clock, so a lift whose chunk
unloads in the middle of a trip assumes it arrived.

## Trying them in the simulator

Each program has a world in the simulator: `base-storage`,
`base-doors`, `base-machines` and `base-lift`. Each has a monitor and a
timeline that types commands and presses buttons, and checks that the
items arrive, the door opens and closes on time, the power alert
switches the generator and reaches a pager, and the lift serves its
calls in look order. `storage-remote` has two pocket computers, each
picking its own chest (a stand-in for an ender chest), depositing, and
getting items delivered there. `storage-craft` has a crafty turtle by the
crafting chest; its timeline makes a two-plank recipe on the keyboard,
crafts 16 sticks from the Craft tab and 8 more with `craft stick 8`,
then torches and chests from the built-in recipes.
`storage-sort` has an input chest touching the
computer as well as on the cable, deposits from it, presses Sort chests
and searches for coal on the on-screen keyboard.

```
cd sim && node headless.mjs base-storage "" 60
cd sim && node test.mjs base
```
