--[[
Testing is a small unit test library in the style of busted, for the
code in this repo. A test file calls describe and it to name its
tests, before_each and after_each to set up and tidy up around every
test in a describe, and expect (also callable as assert) to check
values:

  describe("columns", function()
    it("puts a left start at 0", function()
      local x0, x1 = excavate.columns(3, "left")
      expect.equal(x0, 0)
      expect.equal(x1, 2)
    end)
  end)

expect.equal(a, b) compares with ==, expect.same(a, b) compares tables
deeply and says where they differ, expect.truthy(v), expect.falsy(v),
expect.error(fn, pattern) wants fn to fail (with a message matching
the pattern, when given), expect.near(a, b, eps) compares numbers,
expect.contains(list, v) looks for a value in a list (or a substring
in a string) and expect.match(s, pattern) matches a Lua pattern. Each
takes an optional message as its last argument.

For turtle code there is fakeTurtle, a stand-in for the turtle API that
records every call and answers from a script, and useTurtle to put it
in place of the global turtle for the rest of one test. stub replaces
any field of any table (print, alert.raise, os.pullEvent) the same way;
everything is put back after the test.

runFiles runs test files and reports through callbacks; the test
program (programs/test.lua) does the finding and printing.
--]]

--[[
Values and comparison
--]]

local function show(v)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) == "table" then
    local ok, s = pcall(textutils.serialize, v)
    if ok and s then
      s = s:gsub("%s+", " ")
      if #s > 120 then s = s:sub(1, 117) .. "..." end
      return s
    end
  end
  return tostring(v)
end
describeValue = show

local function keyText(k)
  if type(k) == "string" and k:match("^[%a_][%w_]*$") then return "." .. k end
  return "[" .. show(k) .. "]"
end

-- Where two values first differ, as a path like .slots[2].count with
-- both sides, or nil when they are deeply equal.
function difference(a, b, path, seen)
  path = path or ""
  if a == b then return nil end
  if type(a) ~= "table" or type(b) ~= "table" then
    return string.format("%s: expected %s, got %s", path == "" and "value" or path, show(b), show(a))
  end
  seen = seen or {}
  if seen[a] == b then return nil end
  seen[a] = b
  local keys = {}
  for k in pairs(b) do keys[#keys + 1] = k end
  for k in pairs(a) do if b[k] == nil then keys[#keys + 1] = k end end
  table.sort(keys, function(x, y)
    if type(x) == type(y) and (type(x) == "number" or type(x) == "string") then return x < y end
    return type(x) < type(y)
  end)
  for _, k in ipairs(keys) do
    local d = difference(a[k], b[k], path .. keyText(k), seen)
    if d then return d end
  end
  return nil
end

function deepEqual(a, b) return difference(a, b) == nil end

--[[
Expectations
--]]

local function fail(message, extra)
  if extra then message = tostring(extra) .. ": " .. message end
  error(message, 3)
end

expect = {}

function expect.equal(actual, expected, message)
  if actual ~= expected then fail("expected " .. show(expected) .. ", got " .. show(actual), message) end
end

function expect.same(actual, expected, message)
  local d = difference(actual, expected)
  if d then fail(d, message) end
end

function expect.truthy(v, message)
  if not v then fail("expected a true value, got " .. show(v), message) end
end

function expect.falsy(v, message)
  if v then fail("expected false or nil, got " .. show(v), message) end
end

-- fn must raise an error; when pattern is given the message must
-- match it (as a Lua pattern, or failing that as plain text). Returns
-- the error message.
function expect.error(fn, pattern, message)
  local ok, err = pcall(fn)
  if ok then fail("expected an error" .. (pattern and (" matching " .. show(pattern)) or ""), message) end
  if pattern then
    local text = tostring(err)
    local okFind, found = pcall(string.find, text, pattern)
    if not (okFind and found) and not text:find(pattern, 1, true) then
      fail("expected an error matching " .. show(pattern) .. ", got " .. show(text), message)
    end
  end
  return err
end

function expect.near(actual, expected, eps, message)
  eps = eps or 1e-9
  if type(actual) ~= "number" or math.abs(actual - expected) > eps then
    fail("expected " .. show(expected) .. " +/- " .. eps .. ", got " .. show(actual), message)
  end
end

-- A value in a list (compared deeply), or a piece of text in a string.
function expect.contains(list, v, message)
  if type(list) == "string" then
    if not list:find(tostring(v), 1, true) then fail("expected " .. show(list) .. " to contain " .. show(v), message) end
    return
  end
  if type(list) ~= "table" then fail("expected a list or string, got " .. show(list), message) end
  for _, item in pairs(list) do
    if deepEqual(item, v) then return end
  end
  fail("expected " .. show(list) .. " to contain " .. show(v), message)
end

function expect.match(s, pattern, message)
  if type(s) ~= "string" or not s:find(pattern) then
    fail("expected " .. show(s) .. " to match " .. show(pattern), message)
  end
end

-- assert(v, msg) still works like Lua's; assert.equal and friends are
-- the expectations.
local luaAssert = assert
local function makeAssert()
  return setmetatable({}, {
    __index = expect,
    __call = function(_, v, ...)
      if not v then error((...) or "assertion failed!", 2) end
      return v, ...
    end,
  })
end

--[[
Stubs, restored after every test
--]]

local restores = {}

-- Replace t[key] with value until the current test ends.
function stub(t, key, value)
  local old = rawget(t, key)
  table.insert(restores, function() t[key] = old end)
  t[key] = value
  return value
end

-- Put a fake (or any table) in place of the global turtle until the
-- current test ends. Returns it.
function useTurtle(fake)
  return stub(_G, "turtle", fake)
end

local function restoreAll()
  for i = #restores, 1, -1 do pcall(restores[i]) end
  restores = {}
end

--[[
Fake turtle

fakeTurtle(script) returns a table with every turtle function. With
nothing scripted it behaves like a turtle in an empty world: moves
succeed and are tracked in x, y, z and heading (0 north, 1 east...,
starting at 0, 0, 0 facing north), detect finds nothing, dig has
nothing to dig, and the inventory functions work on its slots
(script.slots, a table of slot -> { name, count, damage }), selected
slot and fuel (script.fuel, default 1000). Dropped items are added to
dropped as { dir = "", "Up" or "Down", name, count }.

Any function can be scripted by name:
  forward = false                 always returns false
  detect = { true, true, false }  one result per call, the last repeats
  dig = testing.returns(false, "Nothing to dig here")  several values
  inspect = function(fake) ... end  computes the result (gets the fake
                                  and the call's arguments)
A list may hold returns(...) results too. Functions that return a
table (getItemDetail, inspect) need a function to script them. When a
scripted (non function) result is true the default runs as well, so a
scripted forward = { true, false } still moves the fake once and a
scripted drop = true still records the drop. A scripting function can
call fake.defaults.forward() and so on itself.

Every call is recorded in calls as { name, args }; called(name) counts
calls of one function and names(filter) lists the names called, those
for which filter(name) is true when given (actionsOnly skips the
queries such as getItemCount).
--]]

local returnsMark = {}

-- Several return values for a scripted turtle function.
function returns(...)
  return { [returnsMark] = true, n = select("#", ...), ... }
end

local fuelValues = {
  ["minecraft:coal"] = 80, ["minecraft:charcoal"] = 80, ["minecraft:coal_block"] = 800,
  ["minecraft:lava_bucket"] = 1000, ["minecraft:oak_log"] = 15, ["minecraft:oak_planks"] = 15,
  ["minecraft:stick"] = 5, ["minecraft:oak_sapling"] = 5, ["minecraft:blaze_rod"] = 120,
}

local queries = {
  getItemCount = true, getItemSpace = true, getItemDetail = true, getSelectedSlot = true,
  getFuelLevel = true, getFuelLimit = true, detect = true, detectUp = true, detectDown = true,
  compare = true, compareUp = true, compareDown = true, compareTo = true, inspect = true,
  inspectUp = true, inspectDown = true,
}

-- For names(): true for functions that change something.
function actionsOnly(name) return not queries[name] end

function fakeTurtle(script)
  script = script or {}
  local f = {
    x = 0, y = 0, z = 0, heading = 0,
    fuel = script.fuel == nil and 1000 or script.fuel,
    fuelLimit = script.fuelLimit or 100000,
    selected = script.selected or 1,
    slots = {},
    dropped = {},
    calls = {},
    fuelValues = script.fuelValues or fuelValues,
  }
  for slot = 1, 16 do
    local s = script.slots and script.slots[slot]
    if s then f.slots[slot] = { name = s.name, count = s.count or 1, damage = s.damage } end
  end
  local counters = {}

  local function slotOf(n) return n or f.selected end
  local function useFuel()
    if f.fuel == "unlimited" then return true end
    if f.fuel <= 0 then return false end
    f.fuel = f.fuel - 1
    return true
  end
  local function take(slot, n)
    local s = f.slots[slot]
    if not s then return nil end
    n = math.min(n or s.count, s.count)
    s.count = s.count - n
    if s.count <= 0 then f.slots[slot] = nil end
    return { name = s.name, count = n, damage = s.damage }
  end

  local defaults = {}
  local offsets = { [0] = { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }
  local function step(sign)
    return function()
      if not useFuel() then return false, "Out of fuel" end
      local o = offsets[f.heading]
      f.x, f.y = f.x + o[1] * sign, f.y + o[2] * sign
      return true
    end
  end
  defaults.forward = step(1)
  defaults.back = step(-1)
  defaults.up = function() if not useFuel() then return false, "Out of fuel" end f.z = f.z + 1 return true end
  defaults.down = function() if not useFuel() then return false, "Out of fuel" end f.z = f.z - 1 return true end
  defaults.turnLeft = function() f.heading = (f.heading + 3) % 4 return true end
  defaults.turnRight = function() f.heading = (f.heading + 1) % 4 return true end
  for _, dir in ipairs({ "", "Up", "Down" }) do
    defaults["detect" .. dir] = function() return false end
    defaults["dig" .. dir] = function() return false, "Nothing to dig here" end
    defaults["attack" .. dir] = function() return false, "Nothing to attack here" end
    defaults["compare" .. dir] = function() return false end
    defaults["inspect" .. dir] = function() return false, "No block to inspect" end
    defaults["suck" .. dir] = function() return false, "No items to take" end
    defaults["place" .. dir] = function()
      if not take(f.selected, 1) then return false, "No items to place" end
      return true
    end
    defaults["drop" .. dir] = function(count)
      local item = take(f.selected, count)
      if not item then return false, "No items to drop" end
      item.dir = dir
      table.insert(f.dropped, item)
      return true
    end
  end
  defaults.select = function(n)
    if type(n) ~= "number" or n < 1 or n > 16 then error("Slot number " .. tostring(n) .. " out of range", 2) end
    f.selected = n
    return true
  end
  defaults.getSelectedSlot = function() return f.selected end
  defaults.getItemCount = function(n) local s = f.slots[slotOf(n)] return s and s.count or 0 end
  defaults.getItemSpace = function(n) local s = f.slots[slotOf(n)] return 64 - (s and s.count or 0) end
  defaults.getItemDetail = function(n)
    local s = f.slots[slotOf(n)]
    if not s then return nil end
    return { name = s.name, count = s.count, damage = s.damage }
  end
  defaults.compareTo = function(n)
    local a, b = f.slots[f.selected], f.slots[n]
    return (a and a.name) == (b and b.name)
  end
  defaults.transferTo = function(n, count)
    local s = f.slots[f.selected]
    if not s then return false end
    local d = f.slots[n]
    if d and d.name ~= s.name then return false end
    local moved = take(f.selected, math.min(count or s.count, 64 - (d and d.count or 0)))
    if d then d.count = d.count + moved.count else f.slots[n] = { name = moved.name, count = moved.count, damage = moved.damage } end
    return true
  end
  defaults.getFuelLevel = function() return f.fuel end
  defaults.getFuelLimit = function() return f.fuelLimit end
  defaults.refuel = function(count)
    local s = f.slots[f.selected]
    local value = s and f.fuelValues[s.name]
    if not value then return false, "Items not combustible" end
    if count == 0 then return true end
    local item = take(f.selected, count)
    if f.fuel ~= "unlimited" then f.fuel = math.min(f.fuelLimit, f.fuel + value * item.count) end
    return true
  end
  defaults.equipLeft = function() return true end
  defaults.equipRight = function() return true end
  defaults.craft = function() return false, "No crafting table" end

  -- The scripted result for this call, packed.
  local function scriptedResult(name, scripted, ...)
    if type(scripted) == "function" then return table.pack(scripted(f, ...)) end
    if type(scripted) == "table" and not scripted[returnsMark] then
      counters[name] = (counters[name] or 0) + 1
      scripted = scripted[math.min(counters[name], #scripted)]
    end
    if type(scripted) == "table" and scripted[returnsMark] then return scripted end
    return table.pack(scripted)
  end

  local function answer(name, scripted, ...)
    if scripted == nil then return defaults[name](...) end
    local result = scriptedResult(name, scripted, ...)
    -- A scripted success still does what the call does by default, so
    -- moves are tracked and drops recorded.
    if result[1] == true and type(scripted) ~= "function" then defaults[name](...) end
    return table.unpack(result, 1, result.n)
  end
  f.defaults = defaults

  for name in pairs(defaults) do
    f[name] = function(...)
      table.insert(f.calls, { name = name, args = table.pack(...) })
      return answer(name, script[name], ...)
    end
  end

  -- How many times a function was called.
  f.called = function(name)
    local n = 0
    for _, c in ipairs(f.calls) do if c.name == name then n = n + 1 end end
    return n
  end
  -- The names of the functions called, in order.
  f.names = function(filter)
    local list = {}
    for _, c in ipairs(f.calls) do
      if not filter or filter(c.name) then list[#list + 1] = c.name end
    end
    return list
  end
  return f
end

--[[
Running tests
--]]

-- Load one test file and collect its tests. Returns a list of
-- { name, fn, frames } (frames are the describes around it, with their
-- hooks), or nil and the error when the file does not load.
function collect(path)
  local tests = {}
  local stack = { { name = nil, before = {}, after = {} } }
  local env
  local function names()
    local parts = {}
    for i = 2, #stack do parts[#parts + 1] = stack[i].name end
    return parts
  end
  local api = {
    describe = function(name, fn)
      table.insert(stack, { name = tostring(name), before = {}, after = {} })
      local ok, err = pcall(fn)
      table.remove(stack)
      if not ok then error(err, 0) end
    end,
    it = function(name, fn)
      local parts = names()
      parts[#parts + 1] = tostring(name)
      -- Hooks are looked up when the test runs, so a before_each
      -- written after the it still applies, as in busted.
      local frames = {}
      for i = 1, #stack do frames[i] = stack[i] end
      table.insert(tests, { name = table.concat(parts, " "), fn = fn, frames = frames })
    end,
    before_each = function(fn) table.insert(stack[#stack].before, fn) end,
    after_each = function(fn) table.insert(stack[#stack].after, fn) end,
    expect = expect,
    assert = makeAssert(),
    testing = testing or _ENV,
  }
  env = setmetatable(api, { __index = _G })
  local fn, err = loadfile(path, "t", env)
  if not fn then return nil, err end
  local ok, runErr = pcall(fn)
  if not ok then return nil, runErr end
  return tests
end

-- Run one collected test. Returns true, or false and the error.
function runTest(test)
  local before, after = {}, {}
  for i, frame in ipairs(test.frames or {}) do
    for _, fn in ipairs(frame.before) do before[#before + 1] = fn end
  end
  for i = #(test.frames or {}), 1, -1 do
    for _, fn in ipairs(test.frames[i].after) do after[#after + 1] = fn end
  end
  local ok, err = true, nil
  for _, fn in ipairs(before) do
    ok, err = pcall(fn)
    if not ok then break end
  end
  if ok then ok, err = pcall(test.fn) end
  for _, fn in ipairs(after) do
    local okAfter, errAfter = pcall(fn)
    if ok and not okAfter then ok, err = false, errAfter end
  end
  restoreAll()
  return ok, ok and nil or tostring(err)
end

-- Run test files. handlers (all optional) are called as things
-- happen: file(path), result(path, name, ok, err), loadError(path, err).
-- Returns { passed, failed, files, failures = { { file, name, err } } }.
function runFiles(paths, handlers)
  handlers = handlers or {}
  local summary = { passed = 0, failed = 0, files = 0, failures = {} }
  for _, path in ipairs(paths) do
    summary.files = summary.files + 1
    if handlers.file then handlers.file(path) end
    local tests, err = collect(path)
    if not tests then
      summary.failed = summary.failed + 1
      table.insert(summary.failures, { file = path, name = "(loading the file)", err = tostring(err) })
      if handlers.loadError then handlers.loadError(path, tostring(err)) end
    else
      for _, test in ipairs(tests) do
        local ok, testErr = runTest(test)
        if ok then
          summary.passed = summary.passed + 1
        else
          summary.failed = summary.failed + 1
          table.insert(summary.failures, { file = path, name = test.name, err = testErr })
        end
        if handlers.result then handlers.result(path, test.name, ok, testErr) end
      end
    end
    -- Let the computer breathe between files so a long run is not
    -- stopped for not yielding.
    if os.queueEvent and os.pullEvent then
      os.queueEvent("testing_yield")
      os.pullEvent("testing_yield")
    end
  end
  return summary
end
