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
line pasted with Ctrl+V runs as a command. Settings are kept in a file
in the computer's root (`/storage.cfg`, `/doors.cfg`, `/machines.cfg`,
`/lift.cfg`), which is written with defaults the first time and can be
changed from the panel or with commands. What they do is published on
the bus (see [the event bus](network.md#event-bus)), and anything a person should look at is
an `alert`, so the pocket pager shows it. A pager that starts later
asks for active alerts (`alert.sync`) and these programs answer.

The logic lives in APIs with unit tests (`apis/storage.lua`,
`circuits.lua`, `machines.lua`, `lift.lua`). `apis/basepanel.lua` is the
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

The Items tab lists everything stored with its count. Touch a row to
pick an item, then 1, 16, 64, Stack or All to send that many to the
output chest, or type a number in the box and press Get. A request is
split over as many slots as needed, taking the smallest stacks first so
partial stacks are used up, and honours stack sizes (a stack of ender
pearls is 16). If the output chest fills up, what was sent is reported
with why it stopped. Find narrows the list by name or display name, and
the button next to it sorts by count or name. Deposit moves everything
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

A turtle with a wired modem on the same network can ask for items over
the bus: `storage request coal 16` at its prompt, or
`storage.request(item, count)` from a program such as a builder
restocking. The storage computer pushes them straight into the turtle
(it is `turtle_<id>` on the network) and answers with how many it sent.

Commands: `get <item> [count|stack|all]`, `deposit`, `find <text>`,
`refresh`, `auto <seconds>`, `input <chest>`, `output <chest>`, `list`.

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
calls in look order.

```
cd sim && node headless.mjs base-storage "" 60
cd sim && node test.mjs base
```
