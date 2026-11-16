--[[
Tests for the dispatcher's queue (apis/fleet.lua): checking queued
jobs, picking the job for a free turtle, the moving / running /
returning steps driven by status messages and acks, lost turtles,
saving, and the map helpers.
--]]

-- A status message as turtleagent sends it.
local function status(id, state, fields)
  local s = { type = "status", id = id, label = "T" .. id, state = state, alerts = {}, fuel = 5000, fuelLimit = 20000 }
  for k, v in pairs(fields or {}) do s[k] = v end
  return s
end

local function pos(x, y, z, h)
  return { x = x, y = y, z = z, heading = h or 0, calibrated = true }
end

-- The sends among what the fleet wants done.
local function sends(f)
  local list = {}
  for _, a in ipairs(f:take()) do
    if a.kind == "send" then list[#list + 1] = a end
  end
  return list
end

describe("fleet.checkValues", function()
  local quarry = turtlectl.findJob("quarry")
  it("converts text and fills in defaults", function()
    local v = fleet.checkValues(quarry, { width = "3", length = 4 })
    expect.same(v, { width = 3, length = 4, depth = 8, start = "left", chest = "left" })
  end)
  it("refuses unknown names, bad numbers and choices", function()
    local v, err = fleet.checkValues(quarry, { colour = "red" })
    expect.falsy(v)
    expect.match(err, "no parameter colour")
    expect.match(select(2, fleet.checkValues(quarry, { width = "wide" })), "number")
    expect.match(select(2, fleet.checkValues(quarry, { width = 0 })), "at least 1")
    expect.match(select(2, fleet.checkValues(quarry, { chest = "below" })), "chest must be one of")
  end)
  it("converts switches", function()
    local v = fleet.checkValues(turtlectl.findJob("mineline"), { torches = "false", returnHome = "yes" })
    expect.equal(v.torches, false)
    expect.equal(v.returnHome, true)
  end)
end)

describe("fleet.parseSite", function()
  it("reads x,y,z and an optional heading", function()
    expect.same(fleet.parseSite("10,64,-5"), { x = 10, y = 64, z = -5 })
    expect.same(fleet.parseSite("10,64,-5,east"), { x = 10, y = 64, z = -5, heading = 1 })
    expect.same(fleet.parseSite({ x = 1, y = 2, z = 3, heading = "s" }), { x = 1, y = 2, z = 3, heading = 2 })
    expect.equal(fleet.parseSite(nil), nil)
  end)
  it("refuses nonsense", function()
    expect.match(select(2, fleet.parseSite("1,2")), "x,y,z")
    expect.match(select(2, fleet.parseSite("1,2,3,up")), "unknown heading")
  end)
end)

describe("fleet.estimateJobFuel", function()
  it("uses the box for quarries and a default otherwise", function()
    expect.equal(fleet.estimateJobFuel("quarry", { width = 2, length = 2, depth = 2 }), 8 + 2 * (2 + 2 + 4))
    expect.equal(fleet.estimateJobFuel("logger", {}), fleet.DefaultJobFuel)
    expect.equal(fleet.estimateJobFuel("goto", { x = 3, y = 0, z = 4 }, { x = 0, y = 0, z = 0 }), 7)
  end)
end)

describe("assigning", function()
  local f
  before_each(function() f = fleet.new() end)

  it("gives a free turtle the highest priority job", function()
    f:add({ job = "refuel" })
    local high = f:add({ job = "mineline", values = { length = 4 }, priority = 5 })
    f:take()
    f:onStatus(status(1, "idle"), 0)
    local s = sends(f)
    expect.equal(#s, 1)
    expect.equal(s[1].job, "mineline")
    expect.equal(s[1].turtle, 1)
    expect.equal(high.state, "running")
  end)

  it("prefers the nearest site among equal priorities", function()
    f:add({ job = "refuel", site = "100,64,0" })
    local near = f:add({ job = "refuel", site = "5,64,0" })
    f:take()
    f:onStatus(status(1, "idle", { pos = pos(0, 64, 0) }), 0)
    local s = sends(f)
    expect.equal(near.state, "moving")
    expect.equal(s[1].job, "goto")
    expect.same(s[1].args, { "5", "64", "0", "false" })
  end)

  it("skips busy turtles, turtles with alerts and stale statuses", function()
    f:add({ job = "refuel" })
    f:take()
    f:onStatus(status(1, "busy", { job = "quarry" }), 0)
    f:onStatus(status(2, "idle", { alerts = { fuel = "out of fuel" } }), 0)
    f:onStatus(status(3, "idle"), 0)
    f:take()
    f.turtles[3].entry = nil
    f.entries[1].state = "queued"
    f:tick(100) -- turtle 3's status is 100 s old now
    expect.equal(#sends(f), 0)
  end)

  it("keeps a job for the turtle it names", function()
    local e = f:add({ job = "refuel", turtle = "Digger" })
    f:onStatus(status(1, "idle"), 0)
    expect.equal(e.state, "queued")
    f:onStatus(status(2, "idle", { label = "Digger" }), 0)
    expect.equal(e.state, "running")
    expect.equal(e.turtle, 2)
    local byId = f:add({ job = "refuel", turtle = 1 })
    f:onStatus(status(1, "idle"), 1)
    expect.equal(byId.turtle, 1)
  end)

  it("does not send a turtle without the fuel for the trip and the job", function()
    local e = f:add({ job = "quarry", values = { width = 2, length = 2, depth = 2 }, site = "40,64,0" })
    f:onStatus(status(1, "idle", { pos = pos(0, 64, 0), fuel = 100 }), 0)
    expect.equal(e.state, "queued")
    expect.match(f.turtles[1].short, "needs %d+ fuel for #1")
    f:onStatus(status(1, "idle", { pos = pos(0, 64, 0), fuel = 1000 }), 1)
    expect.equal(e.state, "moving")
  end)
end)

describe("an entry with a site", function()
  local f, e
  before_each(function()
    f = fleet.new()
    e = f:add({ job = "quarry", values = { width = 2, length = 2, depth = 1 }, site = "10,64,5,east" })
    f:onStatus(status(1, "idle", { pos = pos(0, 64, 0, 2) }), 0)
    f:take()
  end)

  it("goes to the site, runs the job and comes back", function()
    expect.equal(e.state, "moving")
    f:onAck(1, { type = "ack", ok = true, job = "goto" }, 1)
    f:onStatus(status(1, "busy", { job = "goto", pos = pos(3, 64, 0) }), 2)
    expect.equal(#sends(f), 0)
    f:onStatus(status(1, "idle", { message = "finished goto", pos = pos(10, 64, 5, 1) }), 10)
    local s = sends(f)
    expect.equal(e.state, "running")
    expect.equal(s[1].job, "quarry")
    expect.same(s[1].args, turtlectl.jobArgs(turtlectl.findJob("quarry"), e.values))
    -- a heartbeat sent before the turtle took the job changes nothing
    f:onStatus(status(1, "idle", { message = "finished goto", pos = pos(10, 64, 5, 1) }), 11)
    expect.equal(e.state, "running")
    f:onAck(1, { type = "ack", ok = true, job = "quarry" }, 11)
    f:onStatus(status(1, "idle", { message = "finished quarry", pos = pos(10, 64, 5, 1) }), 30)
    s = sends(f)
    expect.equal(e.state, "returning")
    expect.same(s[1].args, { "0", "64", "0", "false", "south" })
    f:onStatus(status(1, "busy", { job = "goto" }), 31)
    f:onStatus(status(1, "idle", { message = "finished goto", pos = pos(0, 64, 0, 2) }), 40)
    expect.equal(e.state, "done")
    expect.falsy(f.turtles[1].entry)
  end)

  it("sends the heading of the site with the goto", function()
    f = fleet.new()
    f:add({ job = "refuel", site = "1,2,3,west" })
    f:onStatus(status(1, "idle"), 0)
    expect.same(sends(f)[1].args, { "1", "2", "3", "false", "west" })
  end)

  it("queues the job again when the goto ends somewhere else", function()
    f:onAck(1, { type = "ack", ok = true, job = "goto" }, 1)
    f:onStatus(status(1, "idle", { message = "finished goto", pos = pos(9, 64, 5) }), 5)
    -- queued again and given straight back to the only free turtle
    expect.equal(e.attempts, 1)
    expect.equal(e.state, "moving")
  end)

  it("fails when the turtle cannot get there", function()
    f:onAck(1, { type = "ack", ok = true, job = "goto" }, 1)
    f:onStatus(status(1, "error", { message = "stopped at 3 64 0: blocked" }), 5)
    expect.equal(e.state, "failed")
    expect.match(e.message, "could not reach the site")
  end)

  it("fails with the job's error", function()
    f:onAck(1, { type = "ack", ok = true, job = "goto" }, 1)
    f:onStatus(status(1, "idle", { message = "finished goto", pos = pos(10, 64, 5) }), 5)
    f:onAck(1, { type = "ack", ok = true, job = "quarry" }, 6)
    f:onStatus(status(1, "error", { message = "blocked going down" }), 9)
    expect.equal(e.state, "failed")
    expect.equal(e.message, "blocked going down")
  end)

  it("fails a job stopped by hand", function()
    f:onAck(1, { type = "ack", ok = true, job = "goto" }, 1)
    f:onStatus(status(1, "idle", { message = "stopped" }), 5)
    expect.equal(e.state, "failed")
    expect.equal(e.message, "stopped by hand")
  end)

  it("queues the job again when the agent restarts on the way", function()
    f:onAck(1, { type = "ack", ok = true, job = "goto" }, 1)
    f:onStatus(status(1, "idle", { pos = pos(2, 64, 0) }), 5)
    expect.equal(e.attempts, 1)
    expect.equal(e.message, nil) -- given out again at once
    expect.equal(e.state, "moving")
  end)

  it("queues it again when the turtle goes silent on the way", function()
    f:onAck(1, { type = "ack", ok = true, job = "goto" }, 1)
    f:tick(30)
    expect.equal(e.state, "moving")
    f:tick(61)
    expect.equal(e.state, "queued")
    expect.match(e.message, "went silent")
  end)

  it("queues it again when the turtle never takes the command", function()
    f:tick(fleet.AckTimeout + 1)
    expect.equal(e.state, "queued")
    expect.match(e.message, "never started goto")
  end)

  it("queues it again when the turtle says it is busy, and fails when it cannot run it", function()
    f:onAck(1, { type = "ack", ok = false, job = "goto", message = "busy with shell" }, 1)
    expect.equal(e.state, "queued")
    f:onStatus(status(1, "idle", { pos = pos(0, 64, 0) }), 2)
    f:onAck(1, { type = "ack", ok = false, job = "goto", message = "program not installed" }, 3)
    expect.equal(e.state, "failed")
    expect.match(e.message, "program not installed")
  end)
end)

describe("a running job whose turtle is lost", function()
  it("fails by default and is queued again with the requeue policy", function()
    for _, policy in ipairs({ "fail", "requeue" }) do
      local f = fleet.new({ lostPolicy = policy })
      local e = f:add({ job = "mineline" })
      f:onStatus(status(1, "idle"), 0)
      f:onAck(1, { type = "ack", ok = true, job = "mineline" }, 1)
      f:onStatus(status(1, "idle"), 5) -- restarted
      if policy == "fail" then
        expect.equal(e.state, "failed")
        expect.equal(e.message, "the turtle restarted")
      else
        expect.equal(e.attempts, 1) -- queued again and given straight back
        expect.equal(e.state, "running")
      end
    end
  end)
end)

describe("editing the queue", function()
  it("removes waiting entries but not active ones", function()
    local f = fleet.new()
    local a = f:add({ job = "refuel" })
    local b = f:add({ job = "refuel" })
    f:onStatus(status(1, "idle"), 0)
    expect.equal(a.state, "running")
    expect.falsy(f:remove(a.id))
    expect.truthy(f:remove(b.id))
    expect.equal(#f.entries, 1)
  end)
  it("changes priorities and retries failed entries", function()
    local f = fleet.new()
    local a = f:add({ job = "refuel" })
    f:bump(a.id, 2)
    expect.equal(a.priority, 2)
    a.state, a.message = "failed", "no"
    expect.truthy(f:retry(a.id, 0))
    expect.equal(a.state, "queued")
    expect.falsy(f:retry(a.id, 0))
  end)
  it("lists active entries first, then the queue by priority", function()
    local f = fleet.new()
    local a = f:add({ job = "refuel" })
    local b = f:add({ job = "refuel", priority = 3 })
    local c = f:add({ job = "refuel" })
    c.state = "done"
    f:onStatus(status(1, "idle"), 0) -- takes b
    local order = {}
    for i, e in ipairs(f:list()) do order[i] = e.id end
    expect.same(order, { b.id, a.id, c.id })
  end)
  it("publishes every change on the bus", function()
    local f = fleet.new()
    f:add({ job = "refuel" })
    local out = f:take()
    expect.equal(out[1].topic, "fleet.job")
    expect.equal(out[1].payload.state, "queued")
    expect.equal(out[1].payload.name, "Refuel")
  end)
end)

describe("saving the queue", function()
  it("keeps entries and their turtle across a restart", function()
    local f = fleet.new()
    local a = f:add({ job = "quarry", values = { width = 2 }, site = "1,2,3" })
    f:add({ job = "refuel", priority = 4 })
    f:onStatus(status(7, "idle", { pos = pos(0, 0, 0) }), 0)
    local g = fleet.new()
    expect.truthy(g:load(f:serialize()))
    expect.equal(#g.entries, 2)
    expect.equal(g:get(a.id).site.z, 3)
    expect.equal(g.nextId, 3)
    -- the turtle with the active entry is lost unless it reports again
    local active = g:entryOf(g.turtles[7])
    expect.truthy(active)
    g:tick(61)
    expect.falsy(active.state == "moving" or active.state == "running")
  end)
end)

describe("the map helpers", function()
  it("fits every point on the screen", function()
    local points = { { x = -50, z = 10 }, { x = 50, z = -10 } }
    local v = fleet.fitView(points, 22, 12)
    for _, p in ipairs(points) do
      expect.truthy(fleet.project(v, 22, 12, p.x, p.z))
    end
    expect.equal(v.cx, 0)
  end)
  it("puts the centre in the middle and north at the top", function()
    local v = { cx = 0, cz = 0, scale = 1 }
    expect.same({ fleet.project(v, 10, 10, 0, 0) }, { 6, 6 })
    expect.same({ fleet.project(v, 10, 10, 0, -2) }, { 6, 4 })
    expect.same({ fleet.project(v, 10, 10, 3, 0) }, { 9, 6 })
    expect.equal(fleet.project(v, 10, 10, 100, 0), nil)
    expect.same({ fleet.unproject(v, 10, 10, 9, 4) }, { 3, -2 })
  end)
  it("zooms in whole blocks", function()
    expect.equal(fleet.zoom({ cx = 0, cz = 0, scale = 4 }, 0.5).scale, 2)
    expect.equal(fleet.zoom({ cx = 0, cz = 0, scale = 1 }, 0.5).scale, 1)
    expect.equal(fleet.zoom({ cx = 0, cz = 0, scale = 1 }, 2).scale, 2)
  end)
  it("draws headings as arrows", function()
    expect.equal(fleet.headingArrow(0) .. fleet.headingArrow(1) .. fleet.headingArrow(2) .. fleet.headingArrow(3), "^>v<")
  end)
end)
