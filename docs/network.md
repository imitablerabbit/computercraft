# Pager, alerts and the event bus

## Pocket pager

`pager` turns an advanced pocket computer with a wireless modem into a
pager for the whole base. It also runs on any computer's own screen.

```
pager
```

The Alerts tab lists every alert that is active right now, from
turtles and from base computers alike, newest first, with where it
came from, its kind, the message and how long ago it started. When a
new one arrives the title bar and the bottom line flash red with the
message, and if the pocket computer has a speaker upgrade (or a
speaker is attached) it plays a couple of notes. Touch an alert to see
the whole message, which computer sent it and when, with Acknowledge
(Ack on a pocket screen): an acknowledged alert turns grey, stops
counting as new and does not flash again until it clears or its
message changes. Acknowledgements are saved in `pager_acks.dat`, so
they survive a restart. Unack takes one back.

The Turtles tab is a small fleet view: every turtle heard with its
state and job (green idle, orange busy, red when it failed or needs
help), a fuel bar (2000 counts as full, red below 200) and the job's
progress bar, or the alert or last message when it is not reporting
progress. Turtles send their status every 5 seconds; one not heard
from for 30 seconds is greyed out, with how long it has been quiet, and
so are its alerts. Base computers that only send alerts are never
greyed, since they say nothing in between.

Alerts come from three places, all over the bus below: `turtleagent`
passes on what its jobs raise with `alert.raise` (the same alerts turtle
control shows), any computer that is not a turtle publishes its own
`alert.raise` calls directly, and the base automation programs publish
theirs. When the pager starts it asks everyone for their active alerts
(`alert.sync`); turtles and the base programs answer, and turtle
statuses carry their alerts anyway. An alert raised once by a plain
program that has since ended is only heard by pagers running at the
time.

In the simulator, the Pager scenario has a pocket computer running
`pager`, two turtles running `turtleagent`, one of which is sent a mine
line it has too little fuel for, and a base computer that raises a
power alert.

## Alerts from base computers

`alert.raise(kind, message)` and `alert.clear(kind)` in `apis/alert.lua`
work on any computer. On a turtle they go through `turtleagent` as
before. On a computer that is not a turtle (a base computer, a pocket
computer) they are also published on the bus, opening an attached
modem if needed, so pagers show them; without a modem they are only
printed. Programs often raise or clear in a loop, so an unchanged
alert is sent again at most every 30 seconds. From the shell (handy in
startup files and for trying the pager):

```
alert <kind> <message...>
alert clear <kind>
```

For example `alert power Smelter out of power`, then `alert clear power`.

## Starting a turtle job from the shell

`turtlejob` starts a job from the turtle control catalogue on a turtle
running `turtleagent` without the touch dashboard, for scripts and
quick tests. Arguments after the job name are its parameters in order,
as the program takes them; leave them out for the defaults. It prints
the turtle's answer, or that there was none within 5 seconds.

```
turtlejob <turtleID> <job> [args...]
turtlejob <turtleID> stop
```

For example `turtlejob 7 quarry 4 4 3`.

## Event bus

`apis/bus.lua` is a shared message channel over rednet (protocol
`bus`) for everything in the base. A message has a topic and a
payload and reaches every computer in range with the bus open, so a
new listener (a pager, a log, a wall display) needs no change to the
programs that publish.

```lua
bus.open()                               -- rednet on a modem; false if none
bus.publish("base.door", { open = true }) -- false without a modem
bus.subscribe("turtle.*")                -- a topic, or a prefix ending in *
local topic, payload, senderId = bus.receive(5)  -- nil after 5 seconds
```

- `bus.open()` opens rednet on a wireless (or ender) modem if there is
  one, otherwise the first modem, and returns whether rednet is open.
  `publish` opens one by itself when needed.
- `bus.publish(topic, payload)` broadcasts `{ topic, payload, from =
  computer id, label }`. A computer does not hear its own broadcasts.
- `bus.subscribe(pattern)` and `bus.unsubscribe(pattern)` (no pattern:
  all). `"*"` matches every topic. Subscriptions belong to the
  computer, since APIs are loaded once, so check the topic you get.
- `bus.receive(timeout)` waits for the next message on a subscribed
  topic and returns topic, payload and the sender's id, or nil after
  timeout seconds. Like `rednet.receive` it throws away other events,
  so give it its own function under `parallel` (each function there
  sees every event).
- `bus.handle(event, ...)` is for programs with their own event loop
  (a GUI application's event listener, say): given an `os.pullEvent`
  result it returns topic, payload and sender for a bus message on a
  subscribed topic, otherwise nil. Malformed messages are ignored.
- `bus.newAlert(kind, message, active)` builds an alert payload for
  this computer; `bus.matches(pattern, topic)`, `bus.isSubscribed`,
  `bus.getSubscriptions` and `bus.isOpen` are small helpers.

Topics in use: `turtle.status` (a turtle's turtle control status:
id, label, state, job, message, fuel, fuelLimit, alerts, progress, every
5 seconds from `turtleagent`), `alert` (`{ id, source, kind, message,
active }`, active false when it is over; use it for anything a person
should look at), `alert.sync` (a listener that just started asks for
the active alerts; programs that keep alerts publish them again),
`registry.join` (`{ id, label, kind }` from `register`), `base.*` for
base automation and `fleet.*` for the dispatcher. The turtle control
protocol is unchanged; the bus messages are extra.

## Registry on the bus

`register` now also announces the computer on the bus, so the
registry's ID can be left out, and `registrylistener` takes both kinds
of message. A computer that registers again replaces its old record
instead of being listed twice.

```
register [registryID]
registrylistener [file]
```
