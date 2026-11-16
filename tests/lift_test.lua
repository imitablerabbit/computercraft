--[[
Tests for the lift dispatcher: choosing the next stop (fifo, look,
scan), queueing calls once, sending pulses or held outputs, and
tracking the vehicle from arrival inputs or travel times.
--]]

local function stops(n, arrived)
  local out = {}
  for i = 1, n do
    out[i] = { name = "F" .. i, call = { side = "left", color = colors.white }, send = { side = "back", color = math.floor(2 ^ (i - 1)) } }
    if arrived then out[i].arrived = { side = "right", color = math.floor(2 ^ (i - 1)) } end
  end
  return out
end

local function dispatcher(cfg)
  local env = { now = 0 }
  cfg.stops = cfg.stops or stops(5)
  cfg.algorithm = cfg.algorithm or "look"
  cfg.travel = cfg.travel or 2
  cfg.dwell = cfg.dwell or 1
  cfg.pulse = cfg.pulse or 0.5
  env.d = lift.new(cfg, { clock = function() return env.now end })
  return env
end

-- The kinds of the events, as "dispatch F3".
local function kinds(events)
  local out = {}
  for i, e in ipairs(events) do out[i] = e.event .. " " .. (e.name or "") end
  return out
end

describe("lift.choose", function()
  it("takes calls in order with fifo", function()
    expect.same({ lift.choose("fifo", 3, 1, { 1, 5, 4 }, 5) }, { 1, -1 })
  end)

  it("takes the nearest call ahead with look", function()
    expect.same({ lift.choose("look", 3, 1, { 1, 5, 4 }, 5) }, { 4, 1 })
  end)

  it("turns round with look when nothing is ahead", function()
    expect.same({ lift.choose("look", 3, 1, { 1, 2 }, 5) }, { 2, -1 })
  end)

  it("runs to the end of the line with scan before turning round", function()
    expect.same({ lift.choose("scan", 3, 1, { 1, 2 }, 5) }, { 5, 1 })
    expect.same({ lift.choose("scan", 5, 1, { 1, 2 }, 5) }, { 2, -1 })
  end)

  it("serves a call at the current stop first", function()
    expect.same({ lift.choose("look", 3, -1, { 5, 3 }, 5) }, { 3, -1 })
  end)

  it("returns nothing for an empty queue", function()
    expect.equal(lift.choose("look", 1, 1, {}, 5), nil)
  end)
end)

describe("lift dispatcher", function()
  it("queues a call once and refuses one for where the vehicle is", function()
    local env = dispatcher({})
    expect.truthy(env.d:call(3))
    local ok, why = env.d:call(3)
    expect.falsy(ok)
    expect.match(why, "already called")
    ok, why = env.d:call(1)
    expect.falsy(ok)
    expect.match(why, "already at")
  end)

  it("pulses the send output and assumes arrival after the travel time", function()
    local env = dispatcher({})
    env.d:call(3)
    expect.same(kinds(env.d:update()), { "call F3", "dispatch F3" })
    local outs = env.d:outputs()
    expect.truthy(outs[3].on)
    expect.falsy(outs[1].on)
    env.now = 0.5
    env.d:update()
    expect.falsy(env.d:outputs()[3].on, "the pulse is over")
    env.now = 3.9
    expect.same(env.d:update(), {}, "two stops at 2 s each")
    env.now = 4
    expect.same(kinds(env.d:update()), { "arrive F3" })
    expect.equal(env.d.position, 3)
    expect.equal(env.d.state, "dwell")
    env.now = 5
    expect.same(kinds(env.d:update()), { "idle F3" })
  end)

  it("holds the send output until the next trip when hold is set", function()
    local env = dispatcher({ hold = true })
    env.d:call(2)
    env.d:update()
    env.now = 10
    env.d:update()
    expect.truthy(env.d:outputs()[2].on)
    env.d:call(4)
    env.now = 11
    env.d:update()
    expect.falsy(env.d:outputs()[2].on)
    expect.truthy(env.d:outputs()[4].on)
  end)

  it("serves calls nearest first in the direction of travel with look", function()
    local env = dispatcher({ algorithm = "look" })
    env.d:call(5)
    env.d:update()              -- off to 5
    env.d:call(2)
    env.d:call(4)
    env.now = 8
    env.d:update()              -- arrives at 5
    env.now = 9
    local events = env.d:update()
    expect.same(kinds(events), { "dispatch F4" })
    env.now = 11; env.d:update() -- at 4
    env.now = 12
    expect.same(kinds(env.d:update()), { "dispatch F2" })
  end)

  it("serves calls in order with fifo", function()
    local env = dispatcher({ algorithm = "fifo" })
    env.d:call(5)
    env.d:update()
    env.d:call(2)
    env.d:call(4)
    env.now = 8; env.d:update()
    env.now = 9
    expect.same(kinds(env.d:update()), { "dispatch F2" })
  end)

  it("tracks the vehicle from arrival inputs and waits for them", function()
    local env = dispatcher({ stops = stops(3, true), timeout = 30 })
    env.d:call(3)
    env.d:update()
    env.now = 20
    expect.same(env.d:update(), {}, "no assumed arrival with an arrival input")
    env.d:arrive(2)
    expect.same(kinds(env.d:update()), { "pass F2" })
    expect.equal(env.d.position, 2)
    env.d:arrive(3)
    expect.same(kinds(env.d:update()), { "arrive F3" })
  end)

  it("calls a trip lost after the timeout and assumes it arrived", function()
    local env = dispatcher({ stops = stops(3, true), timeout = 30 })
    env.d:call(2)
    env.d:update()
    env.now = 30
    expect.same(kinds(env.d:update()), { "lost F2", "arrive F2" })
    expect.equal(env.d.position, 2)
  end)

  it("notices the vehicle moved without being sent", function()
    local env = dispatcher({ stops = stops(3, true) })
    env.d:call(3)
    env.d:arrive(3) -- someone rode it there by hand before the dispatch
    expect.same(kinds(env.d:update()), { "call F3", "arrive F3" })
    expect.same(env.d.queue, {})
  end)

  it("finds stops by number and name", function()
    local env = dispatcher({})
    expect.equal(env.d:find("4"), 4)
    expect.equal(env.d:find("f2"), 2)
    expect.equal(env.d:find("nowhere"), nil)
  end)

  it("validates configs", function()
    expect.truthy(lift.validate({ algorithm = "look", stops = stops(2) }))
    expect.falsy(lift.validate({ algorithm = "look", stops = stops(1) }))
    expect.falsy(lift.validate({ algorithm = "random", stops = stops(2) }))
  end)
end)
