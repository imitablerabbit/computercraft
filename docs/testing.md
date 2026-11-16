# Testing

## Tests

There are two kinds of test: unit tests in Lua for the APIs, which run
in game as well as in the simulator, and scenario checks, which run a
program on a turtle in the simulator and look at the world afterwards.
Both run headless with one command from `sim/`:

```
cd sim && npm install          (once, fetches fengari)
node test.mjs                  everything, about a second
node test.mjs quarry           only the tests whose name has "quarry"
```

It prints `ok` or `FAIL` for every test, what went wrong under each
failure, then a summary, and exits with 1 when anything failed, so it
can run in CI. A filter that matches a Lua test file's path (for example
`node test.mjs inventory`) runs just that file's unit tests.

### Running the unit tests in game

`startup.lua` loads the `testing` API like any other, and the `test`
program runs every file ending in `_test.lua` under `/tests`:

```
test                          every test file
test inventory                tests/inventory_test.lua
test tests/excavate_test.lua  a file or a folder
test -q                       only failures and the summary
```

Each test is printed with ok in green or FAIL in red (plain on a basic
computer), the failures are listed again at the end with their errors,
then a line like `tests: 94 passed, 0 failed, 6 files`. When something
failed the program ends with an error, so `shell.run("test")` returns
false. The installer copies `tests/` along with everything else, and
the tests never touch the real turtle: the turtle code is tested
against a fake one.

### Writing unit tests

A test file is `tests/<name>_test.lua`. It names its tests with
`describe` and `it`, as in busted, and checks values with `expect`
(also available as `assert.equal` and so on; plain `assert(v)` still
works):

```lua
describe("excavate.columns", function()
  it("puts the extra column of an even width on the right", function()
    expect.same({ excavate.columns(4, "middle") }, { -1, 2 })
  end)
end)
```

The checks are `expect.equal(actual, expected)` (with `==`),
`expect.same(actual, expected)` (tables compared deeply; a failure names
the first difference, such as `.slots[2].count: expected 5, got 4`),
`expect.truthy(v)`, `expect.falsy(v)`, `expect.error(fn, pattern)` (fn
must fail, with a message matching the pattern when one is given; it
returns the message), `expect.near(a, b, eps)`, `expect.contains(list,
v)` (also a substring of a string) and `expect.match(s, pattern)`. Each
takes a message as an extra last argument, printed in front of the
failure. `before_each` and `after_each` run around every test in their
`describe`, outer ones first. A failure reports the test file and line.

For turtle code, `testing.fakeTurtle(script)` makes a stand-in for the
`turtle` API and `testing.useTurtle(fake)` puts it in place of the
global for the rest of the test, so the APIs being tested use it:

```lua
it("empties into the chest on the left and turns back", function()
  local t = testing.useTurtle(testing.fakeTurtle({
    slots = { { name = "minecraft:coal", count = 5 } },
    detect = true,             -- there is a chest there
  }))
  expect.truthy(inventory.dumpTo("left"))
  expect.same(t.dropped, { { name = "minecraft:coal", count = 5, dir = "" } })
  expect.same(t.names(function(n) return n:find("^turn") end), { "turnLeft", "turnRight" })
end)
```

Unscripted, the fake behaves like a turtle in an empty world: moves
work and are tracked in `t.x`, `t.y`, `t.z` and `t.heading` (starting
at 0, 0, 0 facing north), each costing a fuel; `detect` finds nothing;
and the inventory functions work on its slots (`slots`, `selected`,
`fuel` in the script), with coal, logs and the like burning for their
usual fuel. Dropped items are listed in `t.dropped`. Any function can
be scripted by name: a value (`forward = false`), a list of values one
per call with the last repeating (`detect = { true, true, false }`),
`testing.returns(false, "Nothing to dig here")` for several return
values, or a function given the fake and the call's arguments. A
scripted `true` still does the default, so a scripted move is still
tracked. Every call is recorded in `t.calls`; `t.called("dig")` counts
them and `t.names(filter)` lists them in order (`testing.actionsOnly`
leaves out queries such as `getItemCount`).

`testing.stub(table, key, value)` swaps any other field for one test,
such as `print` to keep a chatty function quiet or `fs.open` to see
what would be written; everything stubbed is put back when the test
ends.

## Scenario files

Simulator scenarios can be written as text files in `sim/scenarios/`
instead of JavaScript. `sim/scenarios/quarry-file.scn` is the quarry
scenario written this way. A file named `<key>.scn` runs headless as
`node headless.mjs <key> "command" 60` (a path to a .scn file works
too), and appears in the browser's scenario list after the built-in
ones once it is added to `sim/scenarios/index.json`, the list of files
the page loads (the browser cannot list a folder; `node test.mjs`
fails when the index and the folder disagree).

One command per line. Words are separated by spaces, and "double
quotes" make one word of several. `key=value` words give named fields.
Numbers become numbers and `true` and `false` booleans unless quoted.
`#` at the start of a word starts a comment. Coordinates are the
simulator's: x east, y north, z up. Indenting is only for the reader.

```
name Quarry (from file)
description One turtle on the ground with a chest on its left.
description Type a command in its screen, for example: quarry 4 4 3

ground -6 -6 10 10 0 9          # corners x y, top z, depth
block -1 0 1 chest
items -1 0 1 coal*20 torch*5

turtle 3 label=Miner
  pos 0 0 1
  heading north
  fuel 800
  slots coal*20
  peripheral left modem
```

The world, built in file order:

- `name <text>` and `description <text>` (several description lines
  are joined).
- `ground x0 y0 x1 y1 top depth` is the layered ground of the built-in
  scenarios: grass at `top`, two layers of dirt, stone with coal, iron
  and gravel, bedrock below. `ores=false` and `pockets=false` leave out
  the ores and the gravel.
- `hill x0 y0 x1 y1 base height` is dirt topped with grass.
- `fill x0 y0 z0 x1 y1 z1 <type>` fills a box (corners in any order);
  `air` clears it, as does `clear x0 y0 z0 x1 y1 z1`.
- `block x y z <type> key=value...` puts one block, with any extra
  `key=value` words as its state (`block -1 1 1 reconstructor facing=1`).
  `fill` takes them too.
- `items x y z <item>...` fills a chest's slots in order: `coal*20`
  (`minecraft:` is assumed without a prefix), `ic2:sapling*4`,
  `stone_pickaxe*1@3` for damage 3, and `_` for an empty slot.
- `tree x y base` is an oak tree.

Computers start with a line `turtle <id>`, `computer <id>` or
`pocket <id>`, optionally followed by a label and `key=value` fields,
and the lines after it describe it:

- `label <text>`, `pos x y z` (or `x,y,z`), `heading north` (or 0 to 3),
  `fuel <n>`, `advanced false` (computers are advanced by default).
- `slots <item>...` sets the slots in order; `slot <n> <item>` sets one.
- `autorun <command line>` runs at boot after `startup.lua`.
- `peripheral <side> <type> key=value...` attaches a peripheral, with
  any fields passed on (`peripheral back modem wired=true
  network=storage`). Given the computer's id first, `peripheral 7 left
  modem` works anywhere in the file. A monitor takes `size=3x2` and
  `at=x,y,z`, its bottom left block: it stands in the x and z
  directions from there, like the built-in control scenario's.
- `set key=value...` sets any other field of the definition, and so do
  `key=value` words on the first line (`turtle 3 label=Miner
  pos=0,0,1 fuel=800`).

Turtles default to (0, 0, 1) facing north with 1000 fuel. Things that
happen while the scenario runs go on `at` lines:
`at <seconds> <action> <words...> key=value...` becomes
`{ at, action, ... }` in the scenario's timeline, with the words named
for the known actions (`at 10 toggle 2 0 1` gives x, y and z,
`at 20 give 7 minecraft:coal 8` gives computer, item and count) and
kept in `args` for the rest.

## Scenario checks

A check runs a command on a scenario and tests the end state. Checks
live in `tests/scenarios/*.check` files, or at the end of a .scn file
for its own scenario. `node test.mjs` runs them all.

```
check a 3x3x2 hole from the left
  scenario quarry
  run quarry 3 3 2
  seconds 120
  until done:
  expect turtle 3 pos 0 0 1
  expect blocks 0 0 0 2 2 -1 air
  expect chest -1 0 1 item dirt = 18
  expect screen 3 done: dug 18 blocks
  expect no-error
```

`check <name>` starts one. `scenario <key>` is a built-in scenario or a
scenario file (not needed inside a .scn), `run <command>` replaces what
the first turtle runs at boot (`on <id>` picks another computer),
`seconds <n>` is how long to run (default 60) and `until <text>` stops
as soon as a printed line contains the text. Then any number of:

- `expect turtle <id> pos x y z`, `heading <dir>`, `fuel <op> <n>`,
  `item <name> <op> <n>` (that item across its slots) or
  `items <op> <n>` (everything it carries).
- `expect chest x y z item <name> <op> <n>` or `items <op> <n>`.
- `expect block x y z <type>` (`air` for nothing).
- `expect blocks x0 y0 z0 x1 y1 z1 <type>` for every block in the box,
  or with `<op> <n>` for how many of them are that type.
- `expect screen <id> <text>`: one of the computer's screens shows the
  text (wrapped lines are joined).
- `expect log <text>`: some printed line has the text.
- `expect no-error` (or `no-error <id>`): no computer crashed or printed
  a Lua error, a failed API load or "No such program".

The comparisons are `=`, `!=`, `<`, `<=`, `>` and `>=`; leaving one out
means at least one. `not` in front of `block`, `screen` or `log` turns
it round. A failing check prints each expectation that did not hold
with its file and line and what was there instead.

To cover a new program: put the world it needs in
`sim/scenarios/<key>.scn` (and in `index.json` for the browser), try it
with `node headless.mjs <key> "program args" 60`, then write a check
with the end state you expect, either at the end of the .scn or in
`tests/scenarios/<program>.check`. Its pure functions get a
`tests/<api>_test.lua` with the fake turtle standing in for the world.
