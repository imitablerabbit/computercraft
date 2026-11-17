--[[
Nav keeps track of where a turtle is and which way it faces, remembers
the blocks it has seen, and finds its way to a position with A*. It is
the shared way for programs to know where a turtle is and get it
somewhere: goto, where, build and scan use it, and anything that sends
turtles around (a dispatcher, a depot) can build on it.

Coordinates and headings

  x is east, y is up, z is south, as in Minecraft's own coordinates
  (F3). Headings: 0 north (-z), 1 east (+x), 2 south (+z), 3 west (-x),
  turning right adds one. Until nav is calibrated it counts from where
  tracking started: that block is 0, 0, 0 and the way the turtle faced
  is "north", so forward is -z, right is +x and up is +y. nav.calibrate()
  switches to real Minecraft coordinates with gps (it finds the heading
  by moving one block and asking gps again), and nav.setPosition()
  sets them by hand, for example from F3. Calibrating carries the map
  and the home over to the new coordinates.

Position tracking

  Only moves made through nav are tracked. Every move writes the
  position it is about to move to (and the fuel level) to StateFile
  before calling the turtle, and the new position after, so a reboot
  in the middle of a move can be sorted out: on the next use, if a
  move was pending, nav asks gps when it is calibrated and gps answers,
  and otherwise compares the fuel level with the one saved before the
  move (a move costs exactly one fuel, so one less means it happened,
  the same means it did not; the usual ComputerCraft trick). With
  unlimited fuel and no gps it assumes the move did not happen and
  marks the position unsure. A turn costs no fuel, so an interrupted
  turn cannot be checked: nav keeps the old heading and marks the
  heading unsure; goTo recalibrates first when it can, and `where`
  shows it.

  Programs that move with turtle.forward() and friends directly (such
  as quarry, stripmine and the other excavate and mine jobs) leave
  nav's position wrong. Call nav.locate() afterwards when calibrated
  (gps puts it right), or nav.setPosition().

The map

  Every inspect and detect through nav, every dig and every move
  records the block in a sparse map: air, solid (with its name),
  liquid (turtles move through it), unbreakable (bedrock, or a dig that
  said so). It is saved to MapFile every MapSaveEvery changes and at
  the end of goTo, one short line per block, and kept to MaxCells
  blocks by forgetting the ones furthest from the turtle. A turtle in
  the way is remembered for TransientSeconds only and never saved.

Finding a way

  nav.findPath is the A* search on its own, with no turtle calls, so it
  can be tested: 6 neighbours (forward in the current heading, up,
  down, and turning left or right on the spot), each move costs 1 and
  each turn TurnCost. Unknown blocks are assumed free but cost
  UnknownCost more, so known air is preferred. Known solid blocks cost
  DigCost more when digging is allowed and cannot be entered when it
  is not; protected blocks (chests, barrels, anything from
  ComputerCraft such as computers and turtles, and whatever opts.protect
  adds), unbreakable blocks and turtles are never entered. The search
  stops after MaxNodes expanded states.

  nav.goTo plans, walks the plan and replans whenever a move fails,
  recording what was in the way, up to MaxReplans times. Something it
  cannot see in the way (another turtle, a mob, a player) is waited for
  WaitTries times a second apart before it is routed around. Before
  leaving, and on every replan, it checks the fuel covers the planned
  moves plus FuelMargin and refuses rather than strand the turtle.

API (every function loads the saved state on first use)

  nav.position() -> x, y, z, heading
  nav.status() -> { x, y, z, heading, headingName, calibrated, sure,
                    headingSure, home = { x, y, z, heading } or nil, cells }
  nav.setPosition(x, y, z, heading [, frame])  frame "world" (default,
                    e.g. from F3) or "local"; the map and home are kept
                    only when both the old and new frame are "world"
  nav.reset()      back to 0, 0, 0 facing north uncalibrated, map and
                    home forgotten
  nav.forward(), nav.back(), nav.up(), nav.down() -> ok, reason
  nav.turnLeft(), nav.turnRight(), nav.face(heading) -> true
  nav.inspect(), nav.inspectUp(), nav.inspectDown() -> as turtle.inspect
  nav.detect(), nav.detectUp(), nav.detectDown() -> as turtle.detect
  nav.dig(), nav.digUp(), nav.digDown() -> as turtle.dig
  nav.locate([timeout]) -> x, y, z or nil, reason; corrects the position
                    too when calibrated
  nav.calibrate([opts]) -> true, x, y, z, heading or false, reason;
                    opts.dig lets it dig one block to make room to move,
                    opts.protect, opts.timeout
  nav.goTo(x, y, z [, opts]) -> true or false, reason. opts: dig,
                    protect (list of block names or Lua patterns),
                    blocked (function(x, y, z) true for blocks the path
                    must not enter or dig), heading (face it at the end),
                    force (skip the fuel check), maxReplans, maxNodes,
                    waits, unknownCost, digCost, turnCost
  nav.setHome([x, y, z, heading]) (default where the turtle is)
  nav.getHome() -> { x, y, z, heading } or nil
  nav.goHome([opts]) -> as goTo, facing the home heading at the end
  nav.distance([x, y, z]) -> blocks to there (to home with no
                    arguments, nil when there is none), counted along
                    the axes
  nav.findPath(start, goal, cellAt, opts) -> steps, cost, expanded or
                    nil, reason. start { x, y, z, h }, goal { x, y, z },
                    cellAt(x, y, z) -> kind, name (nil when unknown),
                    opts as goTo plus minY, maxY and yield (called now and
                    then so a long search does not stop the computer).
                    steps are { action, x, y, z, h } with action one of
                    forward, up, down, turnLeft, turnRight and x, y, z, h
                    where the turtle is after it.
  nav.cellAt(x, y, z) -> kind, name; nav.record(x, y, z, kind [, name])
                    kinds: "a" air, "s" solid, "l" liquid, "u"
                    unbreakable, "t" a turtle (temporary)
  nav.classify(present, info) -> kind, name from a turtle.inspect result
  nav.isProtected(name [, extra]) -> true for blocks never to dig
  nav.relative(origin, right, up, forward) -> x, y, z of the block that
                    far from origin ({ x, y, z, h }) as the turtle there
                    sees it
  nav.parseHeading(text or number) -> 0..3 or nil ("north", "n", "2")
  nav.headingName(h) -> "north" ...
  nav.save()       write the state and map now

Settings below are the defaults; os.loadAPI copies the API table, so
changing nav.MaxReplans from outside does nothing: pass opts instead.
--]]

StateFile = "/.nav_state"
MapFile = "/.nav_map"
MaxCells = 4000         -- blocks the map remembers
MapSaveEvery = 20       -- map changes between saves
FuelMargin = 10         -- spare fuel goTo insists on above the planned moves
MaxReplans = 64         -- failed moves goTo replans after before giving up
MaxNodes = 20000        -- states the A* search may expand
UnknownCost = 1         -- extra cost of a block nothing is known about
DigCost = 3             -- extra cost of digging through a known block
TurnCost = 1            -- a turn takes as long as a move (but no fuel)
WaitTries = 5           -- seconds to wait for a turtle or mob in the way
TransientSeconds = 30   -- how long a turtle in the way is avoided
MaxDigs = 20            -- digs into one block (falling gravel) before giving up

HeadingNames = { [0] = "north", "east", "south", "west" }

-- Blocks never dug, as Lua patterns matched against the block name.
Protected = {
  "chest", "barrel", "shulker_box", "^computercraft:", "hopper", "furnace",
  "smoker", "spawner", "beacon", "_bed$", "^minecraft:bedrock$",
}

-- Blocks that cannot be dug at all.
Unbreakable = {
  ["minecraft:bedrock"] = true, ["minecraft:barrier"] = true,
  ["minecraft:end_portal_frame"] = true, ["minecraft:command_block"] = true,
  ["minecraft:reinforced_deepslate"] = true,
}

-- Where heading h points: x and z steps.
local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = -1, 0, 1, 0 }

local state            -- nil until loaded
local cells = {}       -- "x,y,z" -> { k = kind, n = name }
local cellCount = 0
local dirty = 0        -- map changes since the last save
local transient = {}   -- "x,y,z" -> os.clock() time it stops blocking

--[[
Small helpers
--]]

function headingName(h)
  return HeadingNames[(tonumber(h) or 0) % 4]
end

function parseHeading(h)
  if type(h) == "number" then return math.floor(h) % 4 end
  if type(h) ~= "string" then return nil end
  local n = tonumber(h)
  if n then return math.floor(n) % 4 end
  h = h:lower()
  for i = 0, 3 do
    if HeadingNames[i] == h or HeadingNames[i]:sub(1, 1) == h then return i end
  end
  return nil
end

local function key(x, y, z) return x .. "," .. y .. "," .. z end

local function parseKey(k)
  local x, y, z = k:match("^(%-?%d+),(%-?%d+),(%-?%d+)$")
  return tonumber(x), tonumber(y), tonumber(z)
end

-- The heading whose step is dx, dz, or nil.
local function headingOf(dx, dz)
  for h = 0, 3 do
    if DX[h] == dx and DZ[h] == dz then return h end
  end
  return nil
end

-- Turn an x, z step clockwise r quarter turns.
local function rotate(dx, dz, r)
  for i = 1, r % 4 do dx, dz = -dz, dx end
  return dx, dz
end

function relative(origin, right, up, forward)
  local h = (origin.h or origin.heading or 0) % 4
  local rh = (h + 1) % 4
  right, up, forward = right or 0, up or 0, forward or 0
  return origin.x + DX[h] * forward + DX[rh] * right,
    origin.y + up,
    origin.z + DZ[h] * forward + DZ[rh] * right
end

function isProtected(name, extra)
  if not name then return false end
  for _, p in ipairs(Protected) do
    if name:find(p) then return true end
  end
  for _, p in ipairs(extra or {}) do
    if name == p then return true end
    local ok, found = pcall(string.find, name, p)
    if ok and found then return true end
  end
  return false
end

function classify(present, info)
  if not present then return "a" end
  local name = type(info) == "table" and info.name or nil
  if not name then return "s" end
  if name:find("^computercraft:turtle") then return "t", name end
  if Unbreakable[name] then return "u", name end
  if name == "minecraft:water" or name == "minecraft:lava" or name == "minecraft:bubble_column" then
    return "l", name
  end
  return "s", name
end

--[[
The pure A* search
--]]

-- Positions are packed into numbers relative to the start so the
-- search can use them as table keys cheaply. The search never goes
-- further than Range from the start.
local Range = 2048
local Span = 4096

function findPath(start, goal, cellAt, opts)
  opts = opts or {}
  local maxNodes = opts.maxNodes or MaxNodes
  local unknownCost = opts.unknownCost or UnknownCost
  local digCost = opts.digCost or DigCost
  local turnCost = opts.turnCost or TurnCost
  local blocked, protect, dig = opts.blocked, opts.protect, opts.dig
  local minY, maxY, yield = opts.minY, opts.maxY, opts.yield
  local sx, sy, sz = start.x, start.y, start.z
  local sh = (start.h or start.heading or 0) % 4
  local gx, gy, gz = goal.x, goal.y, goal.z
  local abs = math.abs

  local function cellKey(x, y, z)
    return ((x - sx + Range) * Span + (y - sy + Range)) * Span + (z - sz + Range)
  end

  -- What it costs to step into a block, nil when it cannot be entered.
  local costs = {}
  local function enterCost(x, y, z)
    if (minY and y < minY) or (maxY and y > maxY) then return nil end
    if abs(x - sx) >= Range or abs(y - sy) >= Range or abs(z - sz) >= Range then return nil end
    local ck = cellKey(x, y, z)
    local c = costs[ck]
    if c ~= nil then return c or nil end
    c = false
    if not (blocked and blocked(x, y, z)) then
      local kind, name = cellAt(x, y, z)
      if kind == nil then c = 1 + unknownCost
      elseif kind == "a" or kind == "l" then c = 1
      elseif kind == "s" and dig and not isProtected(name, protect) then c = 1 + digCost
      end
    end
    costs[ck] = c
    return c or nil
  end

  if sx == gx and sy == gy and sz == gz then return {}, 0, 0 end
  if not enterCost(gx, gy, gz) then return nil, "the goal " .. key(gx, gy, gz) .. " is blocked" end

  -- A binary heap of nodes ordered by f, then by the larger g, so
  -- among equally good nodes the one furthest along is tried first.
  local heap, n = {}, 0
  local function less(a, b)
    if a.f ~= b.f then return a.f < b.f end
    return a.g > b.g
  end
  local function push(node)
    n = n + 1
    local i = n
    heap[i] = node
    while i > 1 do
      local p = math.floor(i / 2)
      if less(heap[i], heap[p]) then
        heap[i], heap[p] = heap[p], heap[i]
        i = p
      else break end
    end
  end
  local function pop()
    local top = heap[1]
    heap[1] = heap[n]
    heap[n] = nil
    n = n - 1
    local i = 1
    while true do
      local l, r, m = i * 2, i * 2 + 1, i
      if l <= n and less(heap[l], heap[m]) then m = l end
      if r <= n and less(heap[r], heap[m]) then m = r end
      if m == i then break end
      heap[i], heap[m] = heap[m], heap[i]
      i = m
    end
    return top
  end

  local function estimate(x, y, z) return abs(x - gx) + abs(y - gy) + abs(z - gz) end

  local best, closed = {}, {}
  local function relax(from, x, y, z, h, cost, action)
    local g = from.g + cost
    local k = cellKey(x, y, z) * 4 + h
    if closed[k] then return end
    local old = best[k]
    if old and old <= g then return end
    best[k] = g
    push({ x = x, y = y, z = z, h = h, g = g, f = g + estimate(x, y, z), key = k, parent = from, action = action })
  end

  local first = { x = sx, y = sy, z = sz, h = sh, g = 0, f = estimate(sx, sy, sz), key = cellKey(sx, sy, sz) * 4 + sh }
  best[first.key] = 0
  push(first)
  local expanded = 0
  while n > 0 do
    local cur = pop()
    if not closed[cur.key] then
      closed[cur.key] = true
      if cur.x == gx and cur.y == gy and cur.z == gz then
        local steps = {}
        local node = cur
        while node.parent do
          table.insert(steps, 1, { action = node.action, x = node.x, y = node.y, z = node.z, h = node.h })
          node = node.parent
        end
        return steps, cur.g, expanded
      end
      expanded = expanded + 1
      if expanded > maxNodes then
        return nil, "no route found within " .. maxNodes .. " search steps"
      end
      if yield and expanded % 500 == 0 then yield() end
      local x, y, z, h = cur.x, cur.y, cur.z, cur.h
      relax(cur, x, y, z, (h + 1) % 4, turnCost, "turnRight")
      relax(cur, x, y, z, (h + 3) % 4, turnCost, "turnLeft")
      local fx, fz = x + DX[h], z + DZ[h]
      local c = enterCost(fx, y, fz)
      if c then relax(cur, fx, y, fz, h, c, "forward") end
      c = enterCost(x, y + 1, z)
      if c then relax(cur, x, y + 1, z, h, c, "up") end
      c = enterCost(x, y - 1, z)
      if c then relax(cur, x, y - 1, z, h, c, "down") end
    end
  end
  return nil, "no route: everything around the goal is blocked"
end

--[[
State and map files
--]]

local function newState()
  return { x = 0, y = 0, z = 0, h = 0, frame = "local", sure = true, headingSure = true }
end

local function readFile(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r")
  if not f then return nil end
  local text = f.readAll()
  f.close()
  return text
end

local function writeFile(path, text)
  local f = fs.open(path, "w")
  if not f then return false end
  f.write(text)
  f.close()
  return true
end

local function saveState()
  writeFile(StateFile, textutils.serialize(state))
end

local function saveMap()
  local names, index = {}, {}
  local lines = { "navmap 1" }
  for k, c in pairs(cells) do
    local line = k .. "," .. c.k
    if c.n then
      if not index[c.n] then
        names[#names + 1] = c.n
        index[c.n] = #names
        lines[#lines + 1] = "=" .. c.n
      end
      line = line .. "," .. index[c.n]
    end
    lines[#lines + 1] = line
  end
  writeFile(MapFile, table.concat(lines, "\n") .. "\n")
  dirty = 0
end

local function loadMap()
  cells, cellCount, dirty = {}, 0, 0
  local text = readFile(MapFile)
  if not text then return end
  local names = {}
  for line in text:gmatch("[^\r\n]+") do
    if line:sub(1, 1) == "=" then
      names[#names + 1] = line:sub(2)
    else
      local x, y, z, k, i = line:match("^(%-?%d+),(%-?%d+),(%-?%d+),(%a),?(%d*)$")
      if x then
        cells[x .. "," .. y .. "," .. z] = { k = k, n = names[tonumber(i) or 0] }
        cellCount = cellCount + 1
      end
    end
  end
end

-- Keep the map to MaxCells: forget the blocks furthest from the turtle.
local function trimMap()
  local list = {}
  for k in pairs(cells) do
    local x, y, z = parseKey(k)
    list[#list + 1] = { k = k, d = math.abs(x - state.x) + math.abs(y - state.y) + math.abs(z - state.z) }
  end
  table.sort(list, function(a, b) return a.d < b.d end)
  local keep = math.floor(MaxCells * 3 / 4)
  for i = keep + 1, #list do cells[list[i].k] = nil end
  cellCount = math.min(#list, keep)
end

local function gpsLocate(timeout)
  if not gps or not gps.locate then return nil end
  local ok, x, y, z = pcall(gps.locate, timeout or 2)
  if not ok or not x then return nil end
  return math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5)
end

-- A move was interrupted by a reboot: work out whether it happened.
local function recover()
  local p = state.pending
  state.pending = nil
  if p.action == "turnLeft" or p.action == "turnRight" then
    state.headingSure = false
  else
    local fixed = false
    if state.frame == "world" then
      local x, y, z = gpsLocate(2)
      if x then
        state.x, state.y, state.z = x, y, z
        fixed = true
      end
    end
    if not fixed then
      local fuel = turtle.getFuelLevel()
      if fuel ~= "unlimited" and p.fuel ~= "unlimited" and fuel == p.fuel - 1 then
        state.x, state.y, state.z = p.x, p.y, p.z
      elseif fuel ~= "unlimited" and fuel == p.fuel then
        -- it did not happen; nothing to change
      else
        state.sure = false
      end
    end
  end
  saveState()
end

function load()
  if state then return state end
  local text = readFile(StateFile)
  local s = text and textutils.unserialize(text)
  if type(s) == "table" and tonumber(s.x) and tonumber(s.y) and tonumber(s.z) then
    state = s
    state.h = (tonumber(state.h) or 0) % 4
    state.frame = state.frame or "local"
  else
    state = newState()
  end
  loadMap()
  if state.pending then recover() end
  return state
end

function save()
  load()
  saveState()
  saveMap()
end

--[[
The map
--]]

function record(x, y, z, kind, name)
  load()
  local k = key(x, y, z)
  if kind == "t" then
    transient[k] = os.clock() + TransientSeconds
    return
  end
  transient[k] = nil
  local old = cells[k]
  if old and old.k == kind and old.n == name then return end
  if not old then cellCount = cellCount + 1 end
  cells[k] = { k = kind, n = name }
  dirty = dirty + 1
  if cellCount > MaxCells then trimMap() end
  if dirty >= MapSaveEvery then saveMap() end
end

function cellAt(x, y, z)
  load()
  local k = key(x, y, z)
  local t = transient[k]
  if t then
    if t > os.clock() then return "t" end
    transient[k] = nil
  end
  local c = cells[k]
  if c then return c.k, c.n end
  return nil
end

--[[
Position
--]]

function position()
  load()
  return state.x, state.y, state.z, state.h
end

function status()
  load()
  local home = state.home and { x = state.home.x, y = state.home.y, z = state.home.z, heading = state.home.h } or nil
  return {
    x = state.x, y = state.y, z = state.z, heading = state.h, headingName = headingName(state.h),
    calibrated = state.frame == "world", sure = state.sure ~= false, headingSure = state.headingSure ~= false,
    home = home, cells = cellCount,
  }
end

function setPosition(x, y, z, heading, frame)
  load()
  x, y, z = tonumber(x), tonumber(y), tonumber(z)
  if not (x and y and z) then error("setPosition needs x, y and z", 2) end
  frame = frame or "world"
  if frame ~= "world" and frame ~= "local" then error("frame is world or local", 2) end
  if not (state.frame == "world" and frame == "world") then
    cells, cellCount, transient = {}, 0, {}
    state.home = nil
    saveMap()
  end
  state.x, state.y, state.z = math.floor(x), math.floor(y), math.floor(z)
  if heading ~= nil then
    local h = parseHeading(heading)
    if not h then error("unknown heading " .. tostring(heading), 2) end
    state.h = h
  end
  state.frame = frame
  state.sure, state.headingSure = true, true
  saveState()
end

function reset()
  state = newState()
  cells, cellCount, transient = {}, 0, {}
  saveState()
  saveMap()
end

function setHome(x, y, z, heading)
  load()
  if x == nil then
    state.home = { x = state.x, y = state.y, z = state.z, h = state.h }
  else
    state.home = { x = tonumber(x), y = tonumber(y), z = tonumber(z), h = parseHeading(heading) or state.h }
  end
  saveState()
end

function getHome()
  load()
  local h = state.home
  return h and { x = h.x, y = h.y, z = h.z, heading = h.h } or nil
end

function distance(x, y, z)
  load()
  if x == nil then
    if not state.home then return nil end
    x, y, z = state.home.x, state.home.y, state.home.z
  end
  return math.abs(x - state.x) + math.abs(y - state.y) + math.abs(z - state.z)
end

--[[
Moving, turning and looking
--]]

-- The block next to the turtle in a direction (forward, back, up, down).
local function ahead(dir)
  if dir == "up" then return state.x, state.y + 1, state.z end
  if dir == "down" then return state.x, state.y - 1, state.z end
  local h = state.h
  if dir == "back" then h = (h + 2) % 4 end
  return state.x + DX[h], state.y, state.z + DZ[h]
end

local suffix = { forward = "", up = "Up", down = "Down" }

local function move(action)
  load()
  local x, y, z = ahead(action)
  state.pending = { action = action, x = x, y = y, z = z, fuel = turtle.getFuelLevel() }
  saveState()
  local ok, reason = turtle[action]()
  if ok then
    state.x, state.y, state.z = x, y, z
    record(x, y, z, "a")
  end
  state.pending = nil
  saveState()
  return ok, reason
end

local function turn(action)
  load()
  local h = (state.h + (action == "turnRight" and 1 or 3)) % 4
  state.pending = { action = action, h = h }
  saveState()
  local ok = turtle[action]()
  if ok ~= false then state.h = h end
  state.pending = nil
  saveState()
  return true
end

function forward() return move("forward") end
function back() return move("back") end
function up() return move("up") end
function down() return move("down") end
function turnLeft() return turn("turnLeft") end
function turnRight() return turn("turnRight") end

function face(heading)
  load()
  local h = parseHeading(heading)
  if not h then error("unknown heading " .. tostring(heading), 2) end
  local diff = (h - state.h) % 4
  if diff == 1 then turnRight()
  elseif diff == 2 then turnRight(); turnRight()
  elseif diff == 3 then turnLeft() end
  return true
end

local function inspectDir(dir)
  load()
  local present, info = turtle["inspect" .. suffix[dir]]()
  local x, y, z = ahead(dir)
  local kind, name = classify(present, info)
  record(x, y, z, kind, name)
  return present, info
end

local function detectDir(dir)
  load()
  local present = turtle["detect" .. suffix[dir]]()
  local x, y, z = ahead(dir)
  if not present then
    record(x, y, z, "a")
  else
    local kind = cellAt(x, y, z)
    if kind ~= "s" and kind ~= "u" then record(x, y, z, "s") end
  end
  return present
end

local function digDir(dir)
  load()
  local ok, reason = turtle["dig" .. suffix[dir]]()
  local x, y, z = ahead(dir)
  if ok then
    record(x, y, z, "a")
  elseif reason and reason:find("Unbreakable") then
    local _, name = cellAt(x, y, z)
    record(x, y, z, "u", name)
  end
  return ok, reason
end

function inspect() return inspectDir("forward") end
function inspectUp() return inspectDir("up") end
function inspectDown() return inspectDir("down") end
function detect() return detectDir("forward") end
function detectUp() return detectDir("up") end
function detectDown() return detectDir("down") end
function dig() return digDir("forward") end
function digUp() return digDir("up") end
function digDown() return digDir("down") end

--[[
gps
--]]

function locate(timeout)
  load()
  local x, y, z = gpsLocate(timeout)
  if not x then return nil, "no gps fix (needs a wireless modem and 4 gps hosts in range)" end
  if state.frame == "world" then
    state.x, state.y, state.z = x, y, z
    state.sure = true
    saveState()
  end
  return x, y, z
end

-- Move every remembered block and the home from the current frame to
-- Minecraft coordinates: the turtle, at sx, sy, sz in the old frame,
-- is at wx, wy, wz, and old headings are r quarter turns short.
local function toWorld(sx, sy, sz, wx, wy, wz, r)
  local function convert(x, y, z)
    local dx, dz = rotate(x - sx, z - sz, r)
    return wx + dx, wy + (y - sy), wz + dz
  end
  local moved = {}
  for k, c in pairs(cells) do
    local x, y, z = convert(parseKey(k))
    moved[key(x, y, z)] = c
  end
  cells, transient = moved, {}
  if state.home then
    local h = state.home
    h.x, h.y, h.z = convert(h.x, h.y, h.z)
    h.h = (h.h + r) % 4
  end
end

function calibrate(opts)
  load()
  opts = opts or {}
  local ax, ay, az = gpsLocate(opts.timeout)
  if not ax then return false, "no gps fix (needs a wireless modem and 4 gps hosts in range)" end
  local turned, moved = 0, false
  for i = 1, 4 do
    if forward() then moved = true break end
    if opts.dig then
      local kind, name = classify(inspect())
      if kind == "s" and not isProtected(name, opts.protect) and dig() and forward() then
        moved = true
        break
      end
    end
    if i < 4 then
      turnRight()
      turned = turned + 1
    end
  end
  if not moved then
    for i = 1, turned do turnLeft() end
    return false, "no room to move one block to find the heading"
  end
  local bx, by, bz = gpsLocate(opts.timeout)
  local movingH = state.h
  local backOk = back()
  if not backOk then
    -- something moved in behind: turn round and go forward instead
    turnRight(); turnRight()
    backOk = forward()
    turnRight(); turnRight()
  end
  for i = 1, turned do turnLeft() end
  if not bx then return false, "lost the gps fix while calibrating" end
  if not backOk then return false, "could not get back to where calibrating started" end
  local worldH = headingOf(bx - ax, bz - az)
  if not worldH or by ~= ay then return false, "gps positions one block apart did not make sense" end
  local r = (worldH - movingH) % 4
  if state.frame ~= "world" then
    toWorld(state.x, state.y, state.z, ax, ay, az, r)
  end
  state.x, state.y, state.z = ax, ay, az
  state.h = (state.h + r) % 4
  state.frame = "world"
  state.sure, state.headingSure = true, true
  saveState()
  saveMap()
  return true, ax, ay, az, state.h
end

--[[
Going places
--]]

local function yieldNow()
  os.queueEvent("nav_yield")
  os.pullEvent("nav_yield")
end

-- One planned move, digging when allowed and waiting for whatever is
-- in the way to go. Returns true, or false, why and whether it is not
-- worth replanning (out of fuel).
local function tryMove(action, opts)
  local waits, digs = 0, 0
  while true do
    local ok, reason = move(action)
    if ok then return true end
    if reason and reason:lower():find("fuel") then return false, "out of fuel", true end
    local x, y, z = ahead(action)
    local where = " at " .. key(x, y, z)
    if reason and (reason:find("Too high") or reason:find("Too low")) then
      record(x, y, z, "t")
      return false, reason .. where
    end
    local present, info = inspectDir(action)
    local kind, name = classify(present, info)
    -- Look around too, so the next plan knows more.
    if action == "forward" then inspectDir("up"); inspectDir("down") end
    if kind == "s" or kind == "u" then
      if kind == "u" or not opts.dig or isProtected(name, opts.protect) or (opts.blocked and opts.blocked(x, y, z)) then
        return false, "blocked by " .. (name or "a block") .. where
      end
      digs = digs + 1
      if digs > MaxDigs then return false, "kept being blocked" .. where end
      local dug, why = digDir(action)
      if not dug then return false, "could not dig " .. (name or "the block") .. where .. ": " .. tostring(why) end
    else
      -- Another turtle, a mob or a player: wait a little first.
      waits = waits + 1
      if waits > (opts.waits or WaitTries) then
        record(x, y, z, "t")
        return false, "something in the way" .. where
      end
      sleep(1)
    end
  end
end

function goTo(x, y, z, opts)
  load()
  opts = opts or {}
  x, y, z = tonumber(x), tonumber(y), tonumber(z)
  if not (x and y and z) then return false, "goTo needs x, y and z" end
  x, y, z = math.floor(x), math.floor(y), math.floor(z)
  if not state.headingSure and state.frame == "world" then
    calibrate({ dig = opts.dig, protect = opts.protect })
  end
  local planOpts = {
    dig = opts.dig, protect = opts.protect, blocked = opts.blocked, maxNodes = opts.maxNodes,
    unknownCost = opts.unknownCost, digCost = opts.digCost, turnCost = opts.turnCost, yield = yieldNow,
  }
  if state.frame == "world" then planOpts.minY, planOpts.maxY = -64, 319 end
  local maxReplans = opts.maxReplans or MaxReplans
  local replans, last = 0, nil
  while state.x ~= x or state.y ~= y or state.z ~= z do
    local steps, err = findPath({ x = state.x, y = state.y, z = state.z, h = state.h }, { x = x, y = y, z = z }, cellAt, planOpts)
    if not steps then
      saveMap()
      return false, err .. (last and (" (last blocked: " .. last .. ")") or "")
    end
    local moves = 0
    for _, s in ipairs(steps) do
      if s.action ~= "turnLeft" and s.action ~= "turnRight" then moves = moves + 1 end
    end
    local fuel = turtle.getFuelLevel()
    if fuel ~= "unlimited" and not opts.force and fuel < moves + FuelMargin then
      saveMap()
      return false, "not enough fuel: " .. moves .. " moves and " .. FuelMargin .. " spare needed, have " .. fuel
    end
    local ok, why, fatal = true, nil, false
    for _, s in ipairs(steps) do
      if s.action == "turnLeft" then turnLeft()
      elseif s.action == "turnRight" then turnRight()
      else
        ok, why, fatal = tryMove(s.action, opts)
        if not ok then break end
      end
    end
    if not ok then
      last = why
      if fatal then
        saveMap()
        return false, why
      end
      replans = replans + 1
      if replans > maxReplans then
        saveMap()
        return false, "gave up after " .. maxReplans .. " replans; last: " .. why
      end
    end
  end
  if opts.heading ~= nil then face(opts.heading) end
  saveMap()
  return true
end

function goHome(opts)
  load()
  if not state.home then return false, "no home set (nav.setHome or goto sethome)" end
  local o = {}
  for k, v in pairs(opts or {}) do o[k] = v end
  o.heading = state.home.h
  return goTo(state.home.x, state.home.y, state.home.z, o)
end
