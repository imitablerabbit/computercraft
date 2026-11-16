--[[
Tests for the turtle control job catalogue (defaults, program
arguments, form options) and the capture terminal that streams a
shell command's output back to the controller.
--]]

local quarry = turtlectl.findJob("quarry")
local flatten = turtlectl.findJob("flatten")
local stripmine = turtlectl.findJob("stripmine")

local function param(job, name)
  for _, p in ipairs(job.params) do
    if p.name == name then return p end
  end
end

describe("turtlectl.findJob", function()
  it("finds jobs by id", function()
    expect.equal(quarry.id, "quarry")
    expect.equal(turtlectl.findJob("refuel").name, "Refuel")
  end)
  it("returns nil for unknown ids", function()
    expect.falsy(turtlectl.findJob("dance"))
    expect.falsy(turtlectl.findJob(nil))
  end)
end)

describe("the job catalogue", function()
  it("has unique ids and something to run for every job", function()
    local seen = {}
    for _, job in ipairs(turtlectl.jobs) do
      expect.falsy(seen[job.id], "duplicate " .. job.id)
      seen[job.id] = true
      expect.truthy(job.program or job.fn, job.id)
    end
  end)
  it("has well formed params with valid defaults", function()
    for _, job in ipairs(turtlectl.jobs) do
      for _, p in ipairs(job.params or {}) do
        local where = job.id .. "." .. tostring(p.name)
        expect.truthy(p.name and p.label, where)
        expect.contains({ "number", "bool", "string", "choice" }, p.type, where)
        if p.type == "number" then expect.equal(type(p.default), "number", where) end
        if p.type == "bool" then expect.equal(type(p.default), "boolean", where) end
        if p.type == "choice" then
          expect.contains(turtlectl.paramOptions(p, turtlectl.jobDefaults(job)), p.default, where)
        end
      end
    end
  end)
end)

describe("turtlectl.jobDefaults", function()
  it("gives every param's default by name", function()
    expect.same(turtlectl.jobDefaults(quarry), { width = 8, length = 8, depth = 8, start = "left", chest = "left" })
  end)
  it("is empty for a job without params", function()
    expect.same(turtlectl.jobDefaults(turtlectl.findJob("refuel")), {})
  end)
end)

describe("turtlectl.jobArgs", function()
  it("puts params in their argument positions", function()
    local args = turtlectl.jobArgs(quarry, { width = 3, length = 4, depth = 2, start = "middle", chest = "behind" })
    expect.same(args, { "3", "4", "2", "behind", "middle" })
  end)
  it("fills in defaults", function()
    expect.same(turtlectl.jobArgs(quarry), { "8", "8", "8", "left", "left" })
    expect.same(turtlectl.jobArgs(quarry, { depth = 1 }), { "8", "8", "1", "left", "left" })
  end)
  it("writes bools as true and false", function()
    local args = turtlectl.jobArgs(stripmine, { torches = false })
    expect.same(args, { "5", "3", "64", "false", "10", "left" })
    expect.equal(turtlectl.jobArgs(stripmine)[4], "true")
  end)
  it("gives no arguments for a job without params", function()
    expect.same(turtlectl.jobArgs(turtlectl.findJob("refuel"), { x = 1 }), {})
  end)
end)

describe("turtlectl.paramOptions", function()
  it("returns plain options", function()
    expect.same(turtlectl.paramOptions(param(quarry, "start")), { "left", "middle", "right" })
  end)
  it("returns nothing for a param without options", function()
    expect.same(turtlectl.paramOptions(param(quarry, "width")), {})
  end)
  it("only offers chest sides outside a quarry", function()
    expect.same(turtlectl.paramOptions(param(quarry, "chest"), {}), { "left", "right", "behind", "above", "depot" })
  end)
  it("offers flatten chest sides by width and start", function()
    local chest = param(flatten, "chest")
    expect.same(turtlectl.paramOptions(chest, { width = 3, start = "left" }), { "left", "behind", "below", "depot" })
    expect.same(turtlectl.paramOptions(chest, { width = 3, start = "right" }), { "right", "behind", "below", "depot" })
    expect.same(turtlectl.paramOptions(chest, { width = 3, start = "middle" }), { "behind", "below", "depot" })
    expect.same(turtlectl.paramOptions(chest, { width = 1, start = "middle" }), { "left", "right", "behind", "below", "depot" })
  end)
  it("agrees with excavate.chestSides for boxes at least two high", function()
    -- A one high flatten leaves the block above alone, so excavate
    -- allows a chest above it while the form never offers one.
    for _, job in ipairs({ quarry, flatten }) do
      local dir = job.id == "quarry" and "down" or "up"
      for width = 1, 5 do
        for _, start in ipairs(excavate.Starts) do
          for height = 2, 4 do
            local values = { width = width, length = 3, depth = height, height = height, start = start }
            local sides = excavate.chestSides(width, 3, height, dir, start)
            table.insert(sides, "depot") -- the form also offers the depot
            expect.same(turtlectl.paramOptions(param(job, "chest"), values),
              sides, job.id .. " " .. width .. " " .. start .. " " .. height)
          end
        end
      end
    end
  end)
end)

describe("turtlectl.newCaptureTerm", function()
  local lines, t
  before_each(function()
    lines = {}
    t = turtlectl.newCaptureTerm(20, function(line) table.insert(lines, line) end)
  end)

  it("hands over a line when it scrolls, without trailing spaces", function()
    t.write("hello  ")
    expect.same(lines, {})
    t.scroll(1)
    expect.same(lines, { "hello" })
    expect.same({ t.getCursorPos() }, { 1, 1 })
  end)

  it("pads up to the cursor and overwrites in place", function()
    t.setCursorPos(4, 1)
    t.write("x")
    t.scroll(1)
    t.write("abcdef")
    t.setCursorPos(2, 1)
    t.write("XY")
    t.finish()
    expect.same(lines, { "   x", "aXYdef" })
  end)

  it("finish sends only an unfinished line", function()
    t.finish()
    expect.same(lines, {})
    t.write("a")
    t.finish()
    t.finish()
    expect.same(lines, { "a" })
  end)

  it("is one line high and the given width", function()
    expect.same({ t.getSize() }, { 20, 1 })
    expect.falsy(t.isColour())
  end)

  it("catches print output through term.redirect", function()
    local old = term.redirect(t)
    local ok, err = pcall(function()
      print("first line")
      print("second")
      write("partial")
    end)
    term.redirect(old)
    expect.truthy(ok, err)
    t.finish()
    expect.same(lines, { "first line", "second", "partial" })
  end)
end)
