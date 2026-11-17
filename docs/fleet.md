# Fleet: dispatcher, depot and map

## Turtle positions

`turtleagent` now says where its turtle is. Every status it sends
carries nav's position and heading (see [Getting around](navigation.md#getting-around-goto-and-where)) once nav has
ever tracked one, and older controllers simply ignore it. When the
agent starts on a turtle with a wireless modem and four gps hosts in
range, it puts nav in Minecraft coordinates: the first time nav moves
the turtle one block and back to learn which way it faces, after that
gps just corrects the position. Without gps nothing moves and nothing
is sent until nav has been used. Most jobs move the turtle without
nav, so the agent asks gps again after every job; that puts the
position right but not the heading, which nav only learns by moving.

## Dispatcher

`dispatcher` keeps a queue of turtle jobs and gives them out to
turtles as they become free, so a list of work can be left for the
fleet to get through. It runs on an advanced computer with a wireless
modem, on the computer's own screen (mouse and keyboard). The turtles
need `turtleagent` and, for jobs with a site, gps.

```
dispatcher [requeue]
fleet add <job> [name=value ...] [at=x,y,z(,heading)] [turtle=<id|label>] [priority=n] [return=false]
fleet list
```

A queued job is any job from the turtle control list with its
parameters, plus where it has to be done (a site: x, y, z in Minecraft
coordinates and optionally the way to face), which turtle must do it
(an id or a label, or any) and a priority. Whenever a turtle reports
idle with no alerts, it is given the best job it may take and has the
fuel for: the highest priority, then the nearest site from where the
turtle says it is, then the oldest. The fuel needed is the way there
and back, a rough estimate for the job (a quarry's box, a mine's
length) and 50 spare, so a turtle low on fuel is passed over (the
turtle list says "low fuel") until it is topped up.

A job with a site starts with `goto` to the site, facing the heading
if one was given. When the turtle reports idle there, the dispatcher
checks it is at the site and sends the job; when that finishes it
sends the turtle back to where it was when it was given the job
(untick Return to leave it at the site). The queue shows each job as
queued, moving, running, returning, done or failed. A job fails when
the turtle reports an error (the message is shown when the row is
touched), when it is stopped by hand, or when the turtle refuses it
(program not installed). A turtle that goes silent for 60 seconds, or
whose agent restarts, loses its job: one still on its way to the site
goes back on the queue for another turtle, one that had started fails,
since half a quarry may not be safe to start again (`dispatcher
requeue` queues those again too). A command the turtle never takes
goes back on the queue after 20 seconds, and after three tries a job
fails. Turtles can still be driven from turtle control; a busy turtle
is simply not given anything.

The screen has the queue above the turtles the dispatcher has heard
(state, fuel, position and what it is doing), and Add, Remove, Up and
Down (priority), Retry (a failed or done job) and Clear (the finished
ones) along the bottom; touch a job first. Add picks the job from a
list, the site (blank for none, `-` keeps whatever heading the turtle
arrives with), the turtle and the priority; Params... fills in the
job's parameters with the same form as turtle control (numbers with
-10 to +10, switches, choices, typed text). The queue is kept in
`fleet_queue.dat`, so it survives a restart; jobs that were running
are matched up again when their turtles report.

`fleet` queues a job from any computer with a wireless modem, over the
bus, for scripts and startup files. Parameters are given by name
(`fleet add quarry width=4 depth=3 chest=depot at=120,64,-30,north`),
the rest take their defaults; it prints the number the dispatcher gave
the job, or why it was refused. `fleet list` prints the queue. On the
bus the dispatcher answers `fleet.enqueue` ({ job, values, site,
turtle, priority }) with `fleet.added`, `fleet.list` with `fleet.queue`
(also sent every 10 seconds), and publishes every change of a job as
`fleet.job`. The queue logic is `apis/fleet.lua`.

## Depot

A depot is a computer that knows where the base's service chests are
(fuel, a dump for what turtles dig, materials) and tells turtles the
nearest one, so they can empty themselves or refuel wherever they are
working instead of beside a chest at their start. The depot computer
needs a wireless modem. Chests on a wired modem's network are read
too, so a full dump chest or an empty fuel chest is skipped; chests it
cannot see are always offered.

```
depot                                                    run the depot
depot add <name> <fuel|dump|materials> <x> <y> <z> <side> [peripheral]
depot remove <name>
depot list
```

Each chest has a name, a role, its block in Minecraft coordinates
(F3), the side the turtle stands on (`north`, `east`, `south`, `west`,
or `above` to stand on it and drop down, or `below`), and optionally
its name on the wired network (`minecraft:chest_0`). `depot` with no
arguments lists them on its screen, with how full each is, and Add,
Edit (touch a chest first) and Remove; Edit has fields for all of it
and a list of the inventories on the network. The list is kept in
`depot.cfg`, and `depot add` from the shell does the same, which suits
a startup file. A full dump chest or an empty fuel chest shows red.

On a turtle with a wireless modem the same program uses the depot:

```
depot unload           empty everything at the nearest dump chest
depot refuel [target]  take fuel at the nearest fuel chest (default 2000)
depot find <role>      say which chest the depot would send it to
```

The turtle asks every depot in range for the nearest chest with room
(or fuel), walks there with nav, empties itself (trying the next dump
chest when one fills up) or takes fuel items and burns them until it
reaches the target, puts back what is left over, and walks back to the
same block, facing the same way. It needs nav in Minecraft
coordinates, which it gets by itself with gps. Depot is in the turtle
control job list with Unload or Refuel and the fuel target.

Quarry, flatten and strip mine take `depot` as their chest. A quarry
or flatten then empties at the depot straight from wherever it fills
up, deep in the hole or not, and carries on where it left off; at the
end it goes back to its start and empties there too. Before digging
anything it checks that gps answers and a depot has a dump chest, and
refuses otherwise. Strip mine keeps its torches and empties at the
depot from its start between lines. The trips use nav's route finding
without digging, and the turtle will not leave without the fuel for
the trip; if a trip fails the turtle raises a chest alert and keeps
its items, as with a full chest.

## Fleet map

Map on turtle control's main screen (top right) shows the fleet from
above, north up: an arrow for every turtle that reports a gps position
(^ > v < for the way it faces), green when idle, orange while working,
red when it failed or needs help, grey when offline, with its name
beside it on wide screens; the depot's chests (F fuel, D dump, M
materials) when a depot is running; and the dispatcher's job sites (x
queued, # being worked) when a dispatcher is running. It fits
everything in at first, with faint + marks at chunk corners when zoomed
in. Touch a turtle to open its screen, or anywhere else to centre the
map there; the buttons along the bottom pan, zoom in and out, and Fit
everything in again. It works on a pocket computer too, without the
names and the legend.

In the simulator, the Fleet scenario has a dispatcher, a depot with a
fuel chest and a dump chest, a base computer, three turtles and a
pocket computer running turtle control, with the GPS demo's hosts. The
timeline sets the depot up, sends a turtle with almost no fuel to
refuel there, and queues two quarries with sites that empty at the
depot (`fleet add quarry width=2 length=2 depth=2 chest=depot
at=-6,1,-4,north`); the dispatcher gives them to the other two
turtles, which come back to their row afterwards. Depot quarry has a
turtle whose inventory is nearly full: `quarry 3 3 4 depot` takes
everything to the depot from four blocks down and comes back to
finish.
