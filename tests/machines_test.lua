--[[
Tests for the machine monitor: discovery from method names, readings,
thresholds with hysteresis, redstone outputs and the rotating log.
--]]

-- A fake peripheral API over machines = { name = { types, methods } }
-- where methods maps a method name to a function returning its result.
local function fakePeripheral(machinesTable)
  local P = {}
  P.getNames = function()
    local names = {}
    for name in pairs(machinesTable) do names[#names + 1] = name end
    table.sort(names)
    return names
  end
  P.getType = function(name) return table.unpack(machinesTable[name].types) end
  P.getMethods = function(name)
    local out = {}
    for m in pairs(machinesTable[name].methods) do out[#out + 1] = m end
    table.sort(out)
    return out
  end
  P.call = function(name, method, ...)
    local fn = machinesTable[name].methods[method]
    if not fn then error("No such method " .. method) end
    return fn(...)
  end
  return P
end

local function cell(level)
  local c = { level = level }
  c.types = { "thermal:energy_cell", "energy_storage" }
  c.methods = {
    getEnergy = function() return c.level end,
    getEnergyCapacity = function() return 1000 end,
  }
  return c
end

local function tank(amount)
  local t = { amount = amount }
  t.types = { "create:fluid_tank", "fluid_storage" }
  t.methods = { tanks = function() return { { name = "minecraft:lava", amount = t.amount } } end }
  return t
end

local function chest(used)
  local list = {}
  for i = 1, used do list[i] = { name = "minecraft:dirt", count = 10 } end
  return { types = { "minecraft:chest", "inventory" }, methods = {
    size = function() return 27 end,
    list = function() return list end,
    pushItems = function() error("must not be called") end,
  } }
end

local function fakeIO()
  local io = { out = {}, bundledOut = {} }
  io.getOutput = function(side) return io.out[side] or false end
  io.setOutput = function(side, on) io.out[side] = on end
  io.getBundledOutput = function(side) return io.bundledOut[side] or 0 end
  io.setBundledOutput = function(side, mask) io.bundledOut[side] = mask end
  return io
end

describe("machines.discover", function()
  it("finds energy, fluid and inventory machines and skips modems and monitors", function()
    local P = fakePeripheral({
      left = cell(10), ["create:fluid_tank_0"] = tank(5), ["minecraft:chest_0"] = chest(1),
      back = { types = { "modem" }, methods = { isWireless = function() return false end } },
      monitor_0 = { types = { "monitor" }, methods = { getSize = function() return 1, 1 end } },
    })
    local found = machines.discover(P)
    local names = {}
    for i, m in ipairs(found) do names[i] = m.name .. "=" .. table.concat(m.metrics, ",") end
    expect.same(names, { "create:fluid_tank_0=fluid", "left=energy", "minecraft:chest_0=inventory" })
  end)
end)

describe("machines readings", function()
  it("reads energy, fluid and inventory as fractions", function()
    local P = fakePeripheral({ a = cell(250), b = tank(4000), c = chest(9) })
    expect.near(machines.fraction(machines.readMetric(P, "a", "energy")), 0.25, 1e-9)
    expect.near(machines.fraction(machines.readMetric(P, "b", "fluid", 16000)), 0.25, 1e-9)
    expect.near(machines.fraction(machines.readMetric(P, "c", "inventory")), 1 / 3, 1e-9)
  end)

  it("measures a tank against the most it has held when no capacity is set", function()
    local P = fakePeripheral({ b = tank(500) })
    local r = machines.readMetric(P, "b", "fluid", nil, 2000)
    expect.equal(r.max, 2000)
    expect.truthy(r.measured)
  end)

  it("lists only reading methods for the details screen", function()
    local P = fakePeripheral({ c = chest(2) })
    local methods = {}
    for i, r in ipairs(machines.readAll(P, "c")) do methods[i] = r.method end
    expect.same(methods, { "list", "size" })
  end)

  it("writes short numbers", function()
    expect.equal(machines.shortNumber(1234567), "1.2M")
    expect.equal(machines.shortNumber(950), "950")
    expect.equal(machines.shortNumber(12500), "13k")
  end)
end)

describe("machines thresholds", function()
  it("raises below the low mark and clears only above the clear mark", function()
    local rule = { below = 0.2, clear = 0.9 }
    expect.falsy(machines.thresholdState(rule, 0.5, false))
    expect.truthy(machines.thresholdState(rule, 0.19, false))
    expect.truthy(machines.thresholdState(rule, 0.5, true), "stays raised in between")
    expect.truthy(machines.thresholdState(rule, 0.89, true))
    expect.falsy(machines.thresholdState(rule, 0.9, true))
  end)

  it("works the other way for stores that must not fill", function()
    local rule = { above = 0.9, clear = 0.7 }
    expect.truthy(machines.thresholdState(rule, 0.95, false))
    expect.truthy(machines.thresholdState(rule, 0.8, true))
    expect.falsy(machines.thresholdState(rule, 0.7, true))
  end)

  it("matches rules by machine and metric", function()
    expect.truthy(machines.ruleMatches({ machine = "*", metric = "energy" }, "left", "energy"))
    expect.falsy(machines.ruleMatches({ machine = "*", metric = "energy" }, "left", "fluid"))
    expect.truthy(machines.ruleMatches({ machine = "energy_cell" }, "thermal:energy_cell_0", "energy"))
    expect.falsy(machines.ruleMatches({ machine = "tank" }, "left", "energy"))
  end)
end)

describe("machines monitor", function()
  local function setup(level)
    local c = cell(level)
    local io = fakeIO()
    local config = { history = 3, rules = { { machine = "*", metric = "energy", below = 0.2, clear = 0.9, kind = "power", output = { side = "top" } } } }
    local m = machines.new(config, { peripheral = fakePeripheral({ left = c }), io = io, clock = function() return 0 end })
    m:scan()
    return m, c, io
  end

  it("raises once, switches the output on, and clears with the output off", function()
    local m, c, io = setup(500)
    expect.same(m:poll(), {})
    c.level = 150
    local events = m:poll()
    expect.equal(#events, 1)
    expect.equal(events[1].action, "raise")
    expect.equal(events[1].kind, "power")
    expect.match(events[1].message, "low: 15%%")
    m:applyOutputs()
    expect.truthy(io.out.top)
    expect.same(m:poll(), {}, "no second raise")
    c.level = 600
    expect.same(m:poll(), {}, "not clear at 60%")
    m:applyOutputs()
    expect.truthy(io.out.top, "generator stays on")
    c.level = 950
    events = m:poll()
    expect.equal(events[1].action, "clear")
    m:applyOutputs()
    expect.falsy(io.out.top)
    expect.equal(#m:activeAlerts(), 0)
  end)

  it("keeps a limited history of fractions", function()
    local m, c = setup(100)
    for i = 1, 5 do c.level = i * 100; m:poll() end
    expect.same(m.history.left.energy, { 0.3, 0.4, 0.5 })
  end)
end)

describe("machines.appendLog", function()
  local path = "/.machines_test.csv"
  after_each(function()
    if fs.exists(path) then fs.delete(path) end
    if fs.exists(path .. ".1") then fs.delete(path .. ".1") end
  end)

  it("writes a header to a new file and rotates when too big", function()
    machines.appendLog(path, "1,a,energy,5,10", 40, "time,machine,metric,value,max")
    expect.truthy(fs.exists(path))
    machines.appendLog(path, "2,a,energy,6,10", 40, "time,machine,metric,value,max")
    expect.truthy(fs.exists(path .. ".1"), "rotated")
    local h = fs.open(path, "r")
    local text = h.readAll()
    h.close()
    expect.match(text, "^time,machine")
    expect.match(text, "2,a,energy")
  end)

  it("does nothing without a file name", function()
    expect.falsy(machines.appendLog("", "x"))
  end)
end)
