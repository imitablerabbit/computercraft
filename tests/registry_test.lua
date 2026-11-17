--[[
Tests for the registry of computers: records, and saving to and
loading from a file.
--]]

local tmp = "/.registry_test.tmp"

describe("registry", function()
  after_each(function()
    if fs.exists(tmp) then fs.delete(tmp) end
  end)

  it("starts empty", function()
    expect.same(registry.new().records, {})
  end)

  it("records id, type and label", function()
    local r = registry.new()
    r:register(4, "turtle", "Digger")
    r:register(5, "advanced computer")
    expect.same(r.records, { { 4, "turtle", "Digger" }, { 5, "advanced computer" } })
  end)

  it("gives every registry its own records", function()
    local a, b = registry.new(), registry.new()
    a:register(1, "turtle", "A")
    expect.same(b.records, {})
  end)

  it("saves and loads a file", function()
    local a = registry.new()
    a:register("7", "turtle", "Runner")
    a:saveFile(tmp)
    local b = registry.new()
    expect.truthy(b:loadFile(tmp))
    expect.same(b.records, { { "7", "turtle", "Runner" } })
  end)

  it("keeps its records when the file is missing", function()
    local r = registry.new()
    r:register(1, "turtle", "A")
    expect.falsy(r:loadFile(tmp))
    expect.same(r.records, { { 1, "turtle", "A" } })
  end)

  it("saves to registry_store.dat when no file is given", function()
    local written = {}
    testing.stub(fs, "open", function(path, mode)
      written.path, written.mode = path, mode
      return { write = function(d) written.data = d end, close = function() end }
    end)
    local r = registry.new()
    r:register(2, "turtle", "B")
    r:saveFile()
    expect.equal(written.path, "registry_store.dat")
    expect.equal(written.mode, "w")
    expect.same(textutils.unserialize(written.data), { { 2, "turtle", "B" } })
  end)
end)
