--[[
Tests for door and lighting circuits: schedules across midnight,
sensor off-delays, pulses, overrides and how outputs are combined. The
clock, the time of day and the redstone API are all fakes.
--]]

-- A fake redstone API: inputs set by the test, outputs recorded.
local function fakeIO()
  local io = { inputs = {}, bundledIn = {}, out = {}, bundledOut = {}, writes = 0 }
  io.getInput = function(side) return io.inputs[side] or false end
  io.testBundledInput = function(side, c) return colors.test(io.bundledIn[side] or 0, c) end
  io.getOutput = function(side) return io.out[side] or false end
  io.setOutput = function(side, on) io.out[side] = on; io.writes = io.writes + 1 end
  io.getBundledOutput = function(side) return io.bundledOut[side] or 0 end
  io.setBundledOutput = function(side, mask) io.bundledOut[side] = mask; io.writes = io.writes + 1 end
  return io
end

local function controller(defs)
  local env = { now = 0, hour = 12, io = fakeIO() }
  env.c = circuits.new({ circuits = defs }, {
    clock = function() return env.now end,
    time = function() return env.hour end,
    io = env.io,
  })
  return env
end

describe("circuits.inSchedule", function()
  it("is on between the times on the same day", function()
    expect.truthy(circuits.inSchedule(12, "8:00", "17:00"))
    expect.falsy(circuits.inSchedule(7.9, "8:00", "17:00"))
    expect.falsy(circuits.inSchedule(17, "8:00", "17:00"))
  end)

  it("runs across midnight when off is before on", function()
    expect.truthy(circuits.inSchedule(18.5, "18:30", "6:00"))
    expect.truthy(circuits.inSchedule(23.9, "18:30", "6:00"))
    expect.truthy(circuits.inSchedule(0, "18:30", "6:00"))
    expect.truthy(circuits.inSchedule(5.99, "18:30", "6:00"))
    expect.falsy(circuits.inSchedule(6, "18:30", "6:00"))
    expect.falsy(circuits.inSchedule(12, "18:30", "6:00"))
    expect.falsy(circuits.inSchedule(18.4, "18:30", "6:00"))
  end)

  it("is never on when the times are equal", function()
    expect.falsy(circuits.inSchedule(6, "6:00", "6:00"))
  end)

  it("parses times", function()
    expect.equal(circuits.parseTime("18:30"), 18.5)
    expect.equal(circuits.parseTime("6:00"), 6)
    expect.equal(circuits.parseTime(25), 1)
    expect.equal(circuits.parseTime("noon"), nil)
    expect.equal(circuits.timeText(18.5), "18:30")
  end)
end)

describe("circuits controller", function()
  it("follows a schedule and reports the change", function()
    local env = controller({ { name = "Hall lights", mode = "schedule", output = { side = "right" }, on = "18:30", off = "6:00" } })
    env.hour = 12
    expect.same(env.c:update(), {})
    expect.falsy(env.io.out.right)
    env.hour = 19
    local changes = env.c:update()
    expect.equal(#changes, 1)
    expect.equal(changes[1].name, "Hall lights")
    expect.truthy(changes[1].state)
    expect.truthy(env.io.out.right)
    env.hour = 3
    expect.same(env.c:update(), {})
    env.hour = 6.5
    expect.falsy(env.c:update()[1].state)
    expect.falsy(env.io.out.right)
  end)

  it("keeps a sensor circuit on for its delay after the input goes off", function()
    local env = controller({ { name = "Front door", mode = "sensor", output = { side = "back" }, input = { side = "left" }, delay = 3 } })
    env.c:update()
    expect.falsy(env.io.out.back)
    env.io.inputs.left = true
    env.now = 10
    env.c:update()
    expect.truthy(env.io.out.back)
    env.io.inputs.left = false
    env.now = 11
    env.c:update()
    expect.truthy(env.io.out.back, "still open 1 s after")
    env.now = 12.9
    env.c:update()
    expect.truthy(env.io.out.back, "still open 2.9 s after")
    env.now = 13
    env.c:update()
    expect.falsy(env.io.out.back, "closed 3 s after")
  end)

  it("restarts the delay when the sensor comes on again", function()
    local env = controller({ { name = "Door", mode = "sensor", output = { side = "back" }, input = { side = "left" }, delay = 3 } })
    env.io.inputs.left = true; env.now = 0; env.c:update()
    env.io.inputs.left = false; env.now = 2; env.c:update()
    env.io.inputs.left = true; env.now = 2.5; env.c:update()
    env.io.inputs.left = false; env.now = 3; env.c:update()
    env.now = 5; env.c:update()
    expect.truthy(env.io.out.back)
    env.now = 6; env.c:update()
    expect.falsy(env.io.out.back)
  end)

  it("reads a bundled colour as the sensor input", function()
    local env = controller({ { name = "Gate", mode = "sensor", output = { side = "top" }, input = { side = "bottom", color = "lime" }, delay = 0 } })
    env.io.bundledIn.bottom = colors.white
    env.c:update()
    expect.falsy(env.io.out.top)
    env.io.bundledIn.bottom = colors.combine(colors.white, colors.lime)
    env.c:update()
    expect.truthy(env.io.out.top)
  end)

  it("toggles a manual circuit and remembers it in the config", function()
    local defs = { { name = "Gate", mode = "manual", output = { side = "top" } } }
    local env = controller(defs)
    env.c:update()
    env.c:toggle("gate")
    expect.equal(env.c:update()[1].state, true)
    expect.truthy(defs[1].state)
    env.c:toggle("Gate")
    env.c:update()
    expect.falsy(env.io.out.top)
  end)

  it("fires a pulse for its length", function()
    local env = controller({ { name = "Bell", mode = "pulse", output = { side = "bottom" }, length = 2 } })
    env.c:update()
    env.now = 5
    env.c:toggle("Bell")
    env.c:update()
    expect.truthy(env.io.out.bottom)
    env.now = 6.9
    env.c:update()
    expect.truthy(env.io.out.bottom)
    env.now = 7
    env.c:update()
    expect.falsy(env.io.out.bottom)
  end)

  it("fires a pulse when its input comes on, once per press", function()
    local env = controller({ { name = "Bell", mode = "pulse", output = { side = "bottom" }, length = 1, input = { side = "left" } } })
    env.io.inputs.left = true
    env.c:update()
    expect.truthy(env.io.out.bottom)
    env.now = 2
    env.c:update()
    expect.falsy(env.io.out.bottom, "held input does not pulse again")
  end)

  it("overrides a schedule by hand until the schedule next changes", function()
    local env = controller({ { name = "Lights", mode = "schedule", output = { side = "right" }, on = "18:00", off = "6:00" } })
    env.hour = 20
    env.c:update()
    env.c:toggle("Lights")
    env.c:update()
    expect.falsy(env.io.out.right, "switched off by hand")
    env.hour = 23
    env.c:update()
    expect.falsy(env.io.out.right, "stays off through the night")
    env.hour = 7
    env.c:update()
    env.hour = 19
    env.c:update()
    expect.truthy(env.io.out.right, "on again at the next dusk")
  end)

  it("inverts an output", function()
    local env = controller({ { name = "Door", mode = "manual", output = { side = "back" }, invert = true } })
    env.c:update()
    expect.truthy(env.io.out.back)
  end)

  it("combines bundled colours on one side", function()
    local env = controller({
      { name = "A", mode = "manual", output = { side = "back", color = "white" }, state = true },
      { name = "B", mode = "manual", output = { side = "back", color = "red" }, state = true },
      { name = "C", mode = "manual", output = { side = "back", color = "blue" } },
    })
    env.c:update()
    expect.equal(env.io.bundledOut.back, colors.combine(colors.white, colors.red))
  end)

  it("does not write outputs that are already right", function()
    local env = controller({ { name = "A", mode = "manual", output = { side = "back" } } })
    env.c:update()
    local writes = env.io.writes
    env.c:update()
    expect.equal(env.io.writes, writes)
  end)
end)

describe("circuits.fromWords", function()
  it("makes each mode from command words", function()
    expect.same(circuits.fromWords("Hall", "schedule", "right", "18:30", "6:00"),
      { name = "Hall", mode = "schedule", output = { side = "right" }, on = "18:30", off = "06:00" })
    expect.same(circuits.fromWords("Door", "sensor", "back", "left:lime", "3"),
      { name = "Door", mode = "sensor", output = { side = "back" }, input = { side = "left", color = "lime" }, delay = 3 })
    expect.same(circuits.fromWords("Bell", "pulse", "bottom:white"),
      { name = "Bell", mode = "pulse", output = { side = "bottom", color = "white" }, length = 1 })
  end)

  it("refuses bad sides, colours, modes and times", function()
    expect.falsy(circuits.fromWords("X", "manual", "sideways"))
    expect.falsy(circuits.fromWords("X", "manual", "back:plaid"))
    expect.falsy(circuits.fromWords("X", "blink", "back"))
    expect.falsy(circuits.fromWords("X", "schedule", "back", "dusk", "dawn"))
    expect.falsy(circuits.fromWords("X", "sensor", "back"))
  end)
end)
