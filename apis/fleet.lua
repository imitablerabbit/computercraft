--[[
Fleet is the job queue and dispatcher logic behind the dispatcher
program: a list of jobs from the turtle control catalogue waiting for a
turtle, and the rules for handing them to turtles as they become free.
It does no networking itself, so it can be tested: the program feeds
it the turtles' status messages and acks with the time, and takes back
what to send (fleet:take()).

A queue entry is a catalogue job with its parameter values (checked
against the job's params like the turtle control form does), an
optional site (x, y, z and heading in nav's Minecraft coordinates,
where the turtle must stand to start), an optional turtle (an id or a
label: only that turtle may take it) and a priority (higher first).

Whenever a turtle reports idle with no alerts, the best entry it may
take and has the fuel for is assigned to it: highest priority first,
then the nearest site (from the position the turtle reports, see
turtlectl.newStatus), then the oldest. The fuel needed is the way to
the site (and back, when the entry returns the turtle), a rough
estimate of the job itself (JobFuel) and FuelMargin.

An entry goes through these states:

  queued     waiting for a turtle
  moving     the goto job was sent to take the turtle to the site; when
             it reports idle after "finished goto" at the site, the job
             itself is sent
  running    the job runs; idle after "finished <job>" is success
  returning  the goto back to where the turtle was when it was assigned
             (entries with returnHome, the default, when the turtle
             reported a position)
  done       finished
  failed     the job (or the way to the site) failed, was stopped by
             hand, was refused by the turtle, or the turtle was lost;
             message says why. Retry queues it again.

A command counts as started once the turtle acks it or reports busy
with it. One not started within AckTimeout seconds is queued again. A
turtle that has not been heard from for LostAfter seconds, or that
reports idle without having finished (its agent restarted), is lost:
an entry on its way to the site is queued again for another turtle,
and a running one follows the lostPolicy option ("fail", the default,
since half a job may not be safe to start over, or "requeue").

  local f = fleet.new({ lostPolicy = "fail" })
  local entry, err = f:add({ job = "quarry", values = { width = 3 },
                             site = { x = 10, y = 64, z = -5, heading = 0 } })
  f:onStatus(statusMessage, os.clock())
  f:onAck(senderId, ackMessage, os.clock())
  f:tick(os.clock())
  for _, action in ipairs(f:take()) do ... end
    -- { kind = "send", turtle = id, job = jobId, args = { ... }, entry = id }
    -- { kind = "publish", topic = "fleet.job", payload = summary }

The map helpers (fitView, project, unproject, zoom) place x, z world
positions on a screen of characters for turtle control's fleet map.
--]]

LostAfter = 60    -- seconds of silence before a turtle with a job is lost
FreshFor = 15     -- a status older than this is not trusted for assigning
AckTimeout = 20   -- seconds for a sent command to be acked or seen running
FuelMargin = 50   -- spare fuel insisted on above the estimate
MaxAttempts = 3   -- times an entry is queued again before it fails
DefaultJobFuel = 100 -- fuel assumed for a job without an estimate below

States = { "queued", "moving", "running", "returning", "done", "failed" }

local HeadingNames = { [0] = "north", "east", "south", "west" }

local function num(v) return tonumber(v) end

local function copy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = copy(v) end
  return c
end

-- Blocks between two positions along the axes.
function distance(a, b)
  if not (a and b) then return nil end
  return math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z)
end

--[[
Fuel estimates per job, from its parameter values. Rough on purpose:
they only decide whether a turtle is worth sending.
--]]

local function box(v, h)
  local w, l, d = num(v.width) or 8, num(v.length) or 8, num(v[h]) or 8
  return w * l * d + 2 * (w + l + 2 * d)
end

JobFuel = {
  quarry = function(v) return box(v, "depth") end,
  flatten = function(v) return box(v, "height") end,
  stripmine = function(v)
    local n, sep, len = num(v.mines) or 5, num(v.sep) or 3, num(v.length) or 64
    return n * (2 * len + sep) + sep * n * (n + 1)
  end,
  mineline = function(v) return 2 * (num(v.length) or 64) end,
  tunnel = function(v) return 2 * (num(v.length) or 32) end,
  rail = function(v) return 2 * (num(v.length) or 64) end,
  bridge = function(v) return 2 * (num(v.length) or 32) end,
  reconstruct = function() return 0 end,
  refuel = function() return 0 end,
  lavafuel = function() return 0 end,
}

-- Fuel the job itself needs (not counting the way to its site). from
-- is the turtle's position, for goto.
function estimateJobFuel(jobId, values, from)
  values = values or {}
  if jobId == "goto" then
    local to = { x = num(values.x), y = num(values.y), z = num(values.z) }
    if from and to.x and to.y and to.z then return distance(from, to) end
    return DefaultJobFuel
  end
  local f = JobFuel[jobId]
  if f then
    local ok, n = pcall(f, values)
    if ok and tonumber(n) then return math.max(0, math.floor(n)) end
  end
  return DefaultJobFuel
end

--[[
Checking what is queued
--]]

-- Values for a catalogue job from loose input (strings from a command
-- line, or a form's values): numbers and switches converted, limits and
-- choices checked, defaults filled in. Returns values or nil, error.
function checkValues(job, given)
  given = given or {}
  local params = {}
  for _, p in ipairs(job.params or {}) do params[p.name] = p end
  for name in pairs(given) do
    if not params[name] then return nil, job.id .. " has no parameter " .. tostring(name) end
  end
  local values = turtlectl.jobDefaults(job)
  for _, p in ipairs(job.params or {}) do
    local v = given[p.name]
    if v ~= nil then
      if p.type == "number" then
        local n = tonumber(v)
        if not n then return nil, p.name .. " must be a number" end
        if p.min and n < p.min then return nil, p.name .. " must be at least " .. p.min end
        if p.max and n > p.max then return nil, p.name .. " must be at most " .. p.max end
        values[p.name] = n
      elseif p.type == "bool" then
        if v == true or v == "true" or v == "yes" then values[p.name] = true
        elseif v == false or v == "false" or v == "no" then values[p.name] = false
        else return nil, p.name .. " must be true or false" end
      else
        values[p.name] = tostring(v)
      end
    end
  end
  -- Choices last: their options can depend on the other values.
  for _, p in ipairs(job.params or {}) do
    if p.type == "choice" then
      local ok = false
      for _, o in ipairs(turtlectl.paramOptions(p, values)) do
        if o == values[p.name] then ok = true end
      end
      if not ok then
        return nil, p.name .. " must be one of " .. table.concat(turtlectl.paramOptions(p, values), ", ")
      end
    end
  end
  return values
end

-- A site from a table { x, y, z, heading } or text "x,y,z[,heading]".
-- Returns the site, nil for no site, or nil and an error.
function parseSite(site)
  if site == nil or site == "" or site == false then return nil end
  if type(site) == "string" then
    local parts = {}
    for p in site:gmatch("[^,%s]+") do parts[#parts + 1] = p end
    if #parts < 3 or #parts > 4 then return nil, "a site is x,y,z or x,y,z,heading" end
    site = { x = parts[1], y = parts[2], z = parts[3], heading = parts[4] }
  end
  if type(site) ~= "table" then return nil, "a site is x,y,z or x,y,z,heading" end
  local x, y, z = num(site.x), num(site.y), num(site.z)
  if not (x and y and z) then return nil, "a site needs numbers for x, y and z" end
  local s = { x = math.floor(x), y = math.floor(y), z = math.floor(z) }
  if site.heading ~= nil and site.heading ~= "" then
    local h = site.heading
    if type(h) == "string" and not tonumber(h) then
      for i = 0, 3 do
        if HeadingNames[i] == h:lower() or HeadingNames[i]:sub(1, 1) == h:lower() then s.heading = i end
      end
    elseif tonumber(h) then
      s.heading = math.floor(tonumber(h)) % 4
    end
    if s.heading == nil then return nil, "unknown heading " .. tostring(h) end
  end
  return s
end

function siteText(site)
  if not site then return "-" end
  local text = site.x .. "," .. site.y .. "," .. site.z
  if site.heading then text = text .. " " .. HeadingNames[site.heading]:sub(1, 1):upper() end
  return text
end

--[[
The queue
--]]

local Fleet = {}
Fleet.__index = Fleet

-- opts: lostPolicy ("fail" or "requeue"), returnHome (default true),
-- lostAfter, ackTimeout, fuelMargin, maxAttempts.
function new(opts)
  opts = opts or {}
  local f = setmetatable({
    entries = {},
    nextId = 1,
    turtles = {},
    out = {},
    opts = {
      lostPolicy = opts.lostPolicy or "fail",
      returnHome = opts.returnHome ~= false,
      lostAfter = opts.lostAfter or LostAfter,
      freshFor = opts.freshFor or FreshFor,
      ackTimeout = opts.ackTimeout or AckTimeout,
      fuelMargin = opts.fuelMargin or FuelMargin,
      maxAttempts = opts.maxAttempts or MaxAttempts,
    },
  }, Fleet)
  return f
end

-- What other computers see of an entry (the fleet.job payload, and the
-- rows of fleet.queue).
function Fleet:summary(e)
  local job = turtlectl.findJob(e.job)
  return {
    id = e.id, job = e.job, name = job and job.name or e.job, values = copy(e.values),
    site = copy(e.site), only = e.only, priority = e.priority, state = e.state,
    turtle = e.turtle, turtleLabel = e.turtleLabel, message = e.message,
  }
end

function Fleet:emit(action)
  table.insert(self.out, action)
end

-- An entry changed: tell the bus.
function Fleet:changed(e)
  self.dirty = true
  self:emit({ kind = "publish", topic = "fleet.job", payload = self:summary(e) })
end

-- Hand over (and forget) what the program should send.
function Fleet:take()
  local out = self.out
  self.out = {}
  return out
end

function Fleet:get(id)
  id = tonumber(id)
  for _, e in ipairs(self.entries) do
    if e.id == id then return e end
  end
  return nil
end

-- Entries in queue order: active first, then queued by priority and
-- age, then finished ones newest first.
function Fleet:list()
  local rank = { moving = 1, running = 1, returning = 1, queued = 2, failed = 3, done = 3 }
  local list = {}
  for _, e in ipairs(self.entries) do list[#list + 1] = e end
  table.sort(list, function(a, b)
    local ra, rb = rank[a.state] or 4, rank[b.state] or 4
    if ra ~= rb then return ra < rb end
    if ra == 2 and a.priority ~= b.priority then return a.priority > b.priority end
    if ra == 3 then return a.id > b.id end
    return a.id < b.id
  end)
  return list
end

-- Queue a job. spec: { job = id, values = { name = value }, site =
-- table or "x,y,z[,heading]", turtle = id or label, priority = n,
-- returnHome = bool }. Returns the entry or nil, error.
function Fleet:add(spec)
  if type(spec) ~= "table" then return nil, "nothing to queue" end
  local job = turtlectl.findJob(spec.job)
  if not job then return nil, "unknown job " .. tostring(spec.job) end
  local values, err = checkValues(job, spec.values)
  if not values then return nil, err end
  local site, serr = parseSite(spec.site)
  if serr then return nil, serr end
  local priority = tonumber(spec.priority or 0)
  if not priority then return nil, "priority must be a number" end
  local only = spec.turtle
  if only == "" or only == "any" then only = nil end
  local e = {
    id = self.nextId, job = job.id, values = values, site = site,
    only = only ~= nil and tostring(only) or nil, priority = math.floor(priority),
    state = "queued", attempts = 0,
    returnHome = spec.returnHome,
  }
  if e.returnHome == nil then e.returnHome = self.opts.returnHome end
  self.nextId = self.nextId + 1
  table.insert(self.entries, e)
  self:changed(e)
  self:assignAll(spec.now or 0)
  return e
end

local function isActive(e)
  return e.state == "moving" or e.state == "running" or e.state == "returning"
end

-- Take an entry off the queue. A job a turtle is busy with has to be
-- stopped on the turtle first.
function Fleet:remove(id)
  local e = self:get(id)
  if not e then return false, "no entry " .. tostring(id) end
  if isActive(e) then return false, "#" .. e.id .. " is " .. e.state .. " on " .. (e.turtleLabel or "a turtle") .. "; stop it there first" end
  for i, x in ipairs(self.entries) do
    if x == e then table.remove(self.entries, i) end
  end
  self.dirty = true
  self:emit({ kind = "publish", topic = "fleet.removed", payload = { id = e.id } })
  return true
end

-- Raise or lower an entry's priority.
function Fleet:bump(id, delta)
  local e = self:get(id)
  if not e then return false, "no entry " .. tostring(id) end
  e.priority = e.priority + (delta or 1)
  self:changed(e)
  return true
end

-- Queue a failed (or done) entry again.
function Fleet:retry(id, now)
  local e = self:get(id)
  if not e then return false, "no entry " .. tostring(id) end
  if isActive(e) or e.state == "queued" then return false, "#" .. e.id .. " is " .. e.state end
  e.state, e.message, e.attempts = "queued", nil, 0
  e.turtle, e.turtleLabel, e.started, e.origin = nil, nil, nil, nil
  self:changed(e)
  self:assignAll(now or 0)
  return true
end

-- Remove every finished entry.
function Fleet:clearFinished()
  local keep = {}
  for _, e in ipairs(self.entries) do
    if e.state ~= "done" then keep[#keep + 1] = e end
  end
  self.entries = keep
  self.dirty = true
end

--[[
Turtles
--]]

function Fleet:turtle(id)
  local t = self.turtles[id]
  if not t then
    t = { id = id, label = "Turtle " .. id, state = "unknown", alerts = {} }
    self.turtles[id] = t
  end
  return t
end

-- May the entry go to this turtle (its turtle constraint)?
function matches(e, t)
  if not e.only then return true end
  return e.only == tostring(t.id) or e.only == t.label
end

local function hasAlerts(t)
  return type(t.alerts) == "table" and next(t.alerts) ~= nil
end

-- What sending the entry to the turtle would cost: distance to the
-- site (nil when either is unknown) and fuel needed.
function Fleet:cost(e, t)
  local d = 0
  if e.site then d = t.pos and distance(t.pos, e.site) or nil end
  local job = estimateJobFuel(e.job, e.values, e.site or t.pos)
  local trip = (d or 0) * ((e.returnHome and e.site) and 2 or 1)
  return d, trip + job + self.opts.fuelMargin
end

-- Can this turtle take a job now?
function Fleet:isFree(t, now)
  return t.state == "idle" and not hasAlerts(t) and not t.entry
    and t.lastSeen ~= nil and now - t.lastSeen <= self.opts.freshFor
end

local function send(self, e, t, jobId, args, now)
  e.started = false
  e.sentAt = now
  e.sentJob = jobId
  self:emit({ kind = "send", turtle = t.id, job = jobId, args = args, entry = e.id })
end

local function gotoArgs(p)
  local args = { tostring(p.x), tostring(p.y), tostring(p.z), "false" }
  if p.heading then args[5] = HeadingNames[p.heading % 4] end
  return args
end

local function sendJob(self, e, t, now)
  local job = turtlectl.findJob(e.job)
  e.state = "running"
  send(self, e, t, e.job, turtlectl.jobArgs(job, e.values), now)
end

-- Pick the best entry for a free turtle and send it. Returns the entry.
function Fleet:assign(t, now)
  if not self:isFree(t, now) then return nil end
  local best, bestD, short = nil, nil, nil
  for _, e in ipairs(self.entries) do
    if e.state == "queued" and matches(e, t) then
      local d, need = self:cost(e, t)
      local fuel = t.fuel
      if fuel ~= "unlimited" and (tonumber(fuel) or 0) < need then
        short = short or { entry = e.id, need = need }
      else
        local better = false
        if not best then better = true
        elseif e.priority ~= best.priority then better = e.priority > best.priority
        elseif (d or math.huge) ~= (bestD or math.huge) then better = (d or math.huge) < (bestD or math.huge)
        else better = e.id < best.id end
        if better then best, bestD = e, d end
      end
    end
  end
  -- Why the turtle sits idle while there is work, for the screen.
  t.short = (not best and short) and ("needs " .. short.need .. " fuel for #" .. short.entry) or nil
  if not best then return nil end
  local e = best
  e.turtle, e.turtleLabel = t.id, t.label
  e.origin = t.pos and { x = t.pos.x, y = t.pos.y, z = t.pos.z, heading = t.pos.heading } or nil
  e.message = nil
  t.entry = e.id
  if e.site then
    e.state = "moving"
    send(self, e, t, "goto", gotoArgs(e.site), now)
  else
    sendJob(self, e, t, now)
  end
  self:changed(e)
  return e
end

function Fleet:assignAll(now)
  local ids = {}
  for id in pairs(self.turtles) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do self:assign(self.turtles[id], now) end
end

-- The entry a turtle is working on, if any.
function Fleet:entryOf(t)
  if not t.entry then return nil end
  local e = self:get(t.entry)
  if not e or not isActive(e) or e.turtle ~= t.id then
    t.entry = nil
    return nil
  end
  return e
end

local function release(self, e)
  local t = e.turtle and self.turtles[e.turtle]
  if t and t.entry == e.id then t.entry = nil end
end

local function finish(self, e, state, message)
  release(self, e)
  e.state, e.message = state, message
  e.started, e.sentAt = nil, nil
  self:changed(e)
end

-- Back on the queue for another turtle, or failed after MaxAttempts.
function Fleet:requeue(e, why)
  release(self, e)
  e.attempts = (e.attempts or 0) + 1
  if e.attempts >= self.opts.maxAttempts then
    return finish(self, e, "failed", why .. " (" .. e.attempts .. " tries)")
  end
  e.state, e.message = "queued", why
  e.turtle, e.turtleLabel, e.started, e.sentAt, e.origin = nil, nil, nil, nil, nil
  self:changed(e)
end

-- The turtle working on e went away (silent, or its agent restarted).
function Fleet:lost(e, why)
  if e.state == "moving" or (e.state == "running" and self.opts.lostPolicy == "requeue") then
    self:requeue(e, why)
  elseif e.state == "returning" then
    finish(self, e, "done", "job done; " .. why .. " on the way back")
  else
    finish(self, e, "failed", why)
  end
end

local function atSite(pos, site)
  if not pos then return true end -- an agent that does not report positions
  return pos.x == site.x and pos.y == site.y and pos.z == site.z
end

-- The command sent for e has finished on the turtle (idle after it).
local function stepDone(self, e, t, now)
  if e.state == "moving" then
    if not atSite(t.pos, e.site) then
      return self:requeue(e, "goto ended at " .. siteText(t.pos) .. ", not the site")
    end
    sendJob(self, e, t, now)
    self:changed(e)
  elseif e.state == "running" then
    if e.returnHome and e.site and e.origin then
      e.state = "returning"
      send(self, e, t, "goto", gotoArgs(e.origin), now)
      self:changed(e)
    else
      finish(self, e, "done", t.message)
    end
  else
    finish(self, e, "done", nil)
  end
end

-- A status message from a turtle (turtlectl.newStatus).
function Fleet:onStatus(msg, now)
  if type(msg) ~= "table" or msg.id == nil then return end
  local t = self:turtle(msg.id)
  t.label = msg.label or t.label
  t.state = msg.state or "idle"
  t.job, t.message = msg.job, msg.message
  t.fuel, t.fuelLimit = msg.fuel, msg.fuelLimit
  t.alerts = type(msg.alerts) == "table" and msg.alerts or {}
  t.progress = type(msg.progress) == "table" and msg.progress or nil
  if type(msg.pos) == "table" and tonumber(msg.pos.x) and tonumber(msg.pos.y) and tonumber(msg.pos.z) then
    t.pos = { x = msg.pos.x, y = msg.pos.y, z = msg.pos.z, heading = msg.pos.heading, calibrated = msg.pos.calibrated }
  else
    t.pos = nil
  end
  t.lastSeen = now

  local e = self:entryOf(t)
  if e then
    local expect = e.sentJob
    if t.state == "busy" then
      if t.job == expect then e.started = true end
    elseif t.state == "error" then
      if e.state == "moving" then
        finish(self, e, "failed", "could not reach the site: " .. tostring(t.message))
      elseif e.state == "returning" then
        finish(self, e, "done", "job done; could not get back: " .. tostring(t.message))
      else
        finish(self, e, "failed", tostring(t.message or "failed"))
      end
    elseif t.state == "idle" and e.started then
      if t.message == "finished " .. expect then
        stepDone(self, e, t, now)
      elseif t.message == "stopped" then
        if e.state == "returning" then finish(self, e, "done", "job done; stopped on the way back")
        else finish(self, e, "failed", "stopped by hand") end
      else
        self:lost(e, "the turtle restarted")
      end
    end
  end
  self:assign(t, now)
end

-- An ack from a turtle for a command.
function Fleet:onAck(sender, msg, now)
  if type(msg) ~= "table" then return end
  local t = self.turtles[sender]
  if not t then return end
  local e = self:entryOf(t)
  if not e or msg.job ~= e.sentJob then return end
  if msg.ok then
    e.started = true
  else
    local why = tostring(msg.message or "refused")
    if why:find("^busy") then
      self:requeue(e, t.label .. " was busy")
    elseif e.state == "returning" then
      finish(self, e, "done", "job done; the way back was refused: " .. why)
    else
      finish(self, e, "failed", t.label .. " refused " .. e.sentJob .. ": " .. why)
    end
  end
end

-- Time passing: lost turtles, commands never acked, and turtles that
-- have been free all along (a job just added, fuel just given).
function Fleet:tick(now)
  for _, e in ipairs(self.entries) do
    if isActive(e) then
      local t = e.turtle and self.turtles[e.turtle]
      if not t or not t.lastSeen or now - t.lastSeen > self.opts.lostAfter then
        self:lost(e, (t and t.label or "the turtle") .. " went silent")
      elseif not e.started and e.sentAt and now - e.sentAt > self.opts.ackTimeout then
        if e.state == "returning" then
          finish(self, e, "done", "job done; the way back was never started")
        else
          self:requeue(e, (t.label or "the turtle") .. " never started " .. tostring(e.sentJob))
        end
      end
    end
  end
  self:assignAll(now)
end

--[[
Saving. Times are os.clock() values, which start again after a reboot,
so they are not kept: active entries wait for their turtle's next
status (and are lost after LostAfter without one).
--]]

function Fleet:serialize()
  local entries = {}
  for i, e in ipairs(self.entries) do
    local c = copy(e)
    c.sentAt = nil
    entries[i] = c
  end
  return textutils.serialize({ nextId = self.nextId, entries = entries })
end

function Fleet:load(text)
  local data = type(text) == "string" and textutils.unserialize(text) or nil
  if type(data) ~= "table" or type(data.entries) ~= "table" then return false end
  self.entries = {}
  for _, e in ipairs(data.entries) do
    if type(e) == "table" and tonumber(e.id) and turtlectl.findJob(e.job) then
      e.priority = tonumber(e.priority) or 0
      e.attempts = tonumber(e.attempts) or 0
      table.insert(self.entries, e)
      if isActive(e) and e.turtle then
        local t = self:turtle(e.turtle)
        t.entry = e.id
        t.label = e.turtleLabel or t.label
        t.lastSeen = 0 -- lost unless it reports within LostAfter
      end
    end
  end
  self.nextId = math.max(tonumber(data.nextId) or 1, #self.entries + 1)
  for _, e in ipairs(self.entries) do self.nextId = math.max(self.nextId, e.id + 1) end
  return true
end

function Fleet:saveFile(path)
  local f = fs.open(path, "w")
  if not f then return false end
  f.write(self:serialize())
  f.close()
  self.dirty = false
  return true
end

function Fleet:loadFile(path)
  if not fs.exists(path) then return false end
  local f = fs.open(path, "r")
  if not f then return false end
  local text = f.readAll()
  f.close()
  return self:load(text)
end

--[[
Map helpers: world x (east) and z (south) onto a w x h grid of
characters, north up. A view is { cx, cz, scale } with scale blocks per
character.
--]]

-- A view that shows every point ({ x, z }), with a little room around.
function fitView(points, w, h)
  if not points or #points == 0 then return { cx = 0, cz = 0, scale = 1 } end
  local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
  for _, p in ipairs(points) do
    minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
    minZ, maxZ = math.min(minZ, p.z), math.max(maxZ, p.z)
  end
  local roomW, roomH = math.max(1, w - 2), math.max(1, h - 2)
  local scale = math.max(1, math.ceil((maxX - minX + 1) / roomW), math.ceil((maxZ - minZ + 1) / roomH))
  return { cx = math.floor((minX + maxX) / 2), cz = math.floor((minZ + maxZ) / 2), scale = scale }
end

-- The column and row of a world x, z, or nil when it is off screen.
function project(view, w, h, x, z)
  local s = view.scale
  local col = math.floor((x - view.cx) / s + 0.5) + math.floor(w / 2) + 1
  local row = math.floor((z - view.cz) / s + 0.5) + math.floor(h / 2) + 1
  if col < 1 or col > w or row < 1 or row > h then return nil end
  return col, row
end

-- The world x, z at the middle of a column and row.
function unproject(view, w, h, col, row)
  return view.cx + (col - 1 - math.floor(w / 2)) * view.scale,
    view.cz + (row - 1 - math.floor(h / 2)) * view.scale
end

-- Zoom in (factor < 1) or out, keeping the centre. Scale stays a whole
-- number of blocks, at least 1.
function zoom(view, factor)
  local s = math.max(1, math.floor(view.scale * factor + 0.5))
  if s == view.scale and factor > 1 then s = s + 1 end
  return { cx = view.cx, cz = view.cz, scale = s }
end

-- The character for a heading: ^ north, > east, v south, < west.
function headingArrow(h)
  return ({ [0] = "^", ">", "v", "<" })[(tonumber(h) or 0) % 4]
end
