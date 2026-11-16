--[[
Tests for the event bus: topic patterns, subscriptions, what publish
sends, which modem open picks, and that handle and receive pass on
only well formed messages for subscribed topics. rednet, peripheral
and os.pullEvent are stubbed, so nothing goes over the air.
--]]

-- Stub os.pullEvent to hand out these events in turn.
local function feedEvents(events)
  local i = 0
  testing.stub(os, "pullEvent", function()
    i = i + 1
    local e = events[i]
    if not e then error("no more events") end
    return table.unpack(e)
  end)
end

-- A modem setup: names maps side -> "wireless", "wired" or another
-- peripheral type. Returns the list of sides rednet.open was called on.
local function stubModems(names)
  local opened, list = {}, {}
  for side in pairs(names) do list[#list + 1] = side end
  table.sort(list)
  testing.stub(peripheral, "getNames", function() return list end)
  testing.stub(peripheral, "hasType", function(side, t)
    local kind = names[side]
    if t == "modem" then return kind == "wireless" or kind == "wired" end
    return kind == t
  end)
  testing.stub(peripheral, "call", function(side, method)
    if method == "isWireless" then return names[side] == "wireless" end
  end)
  testing.stub(rednet, "open", function(side) opened[#opened + 1] = side end)
  testing.stub(rednet, "isOpen", function(side)
    for _, s in ipairs(opened) do
      if side == nil or s == side then return true end
    end
    return false
  end)
  return opened
end

describe("bus.matches", function()
  it("matches a whole topic", function()
    expect.truthy(bus.matches("alert", "alert"))
    expect.falsy(bus.matches("alert", "alert.sync"))
    expect.falsy(bus.matches("alert", "alerts"))
  end)
  it("matches a prefix ending in *", function()
    expect.truthy(bus.matches("turtle.*", "turtle.status"))
    expect.falsy(bus.matches("turtle.*", "base.door"))
    expect.truthy(bus.matches("*", "anything"))
  end)
  it("does not match things that are not strings", function()
    expect.falsy(bus.matches("alert", nil))
    expect.falsy(bus.matches(nil, "alert"))
    expect.falsy(bus.matches("*", 5))
  end)
end)

describe("bus subscriptions", function()
  after_each(function() bus.unsubscribe() end)

  it("adds and removes patterns", function()
    bus.subscribe("alert")
    bus.subscribe("turtle.*")
    expect.same(bus.getSubscriptions(), { "alert", "turtle.*" })
    expect.truthy(bus.isSubscribed("turtle.status"))
    bus.unsubscribe("turtle.*")
    expect.falsy(bus.isSubscribed("turtle.status"))
    expect.truthy(bus.isSubscribed("alert"))
  end)
  it("removes everything with no pattern", function()
    bus.subscribe("a")
    bus.subscribe("b")
    bus.unsubscribe()
    expect.same(bus.getSubscriptions(), {})
  end)
  it("refuses a pattern that is not a string", function()
    expect.error(function() bus.subscribe(nil) end, "pattern")
    expect.error(function() bus.subscribe("") end, "pattern")
  end)
end)

describe("bus.publish", function()
  it("broadcasts topic, payload, id and label on the bus protocol", function()
    local sent = {}
    testing.stub(rednet, "isOpen", function() return true end)
    testing.stub(rednet, "broadcast", function(msg, protocol) sent[#sent + 1] = { msg = msg, protocol = protocol } end)
    testing.stub(os, "getComputerLabel", function() return "Base" end)
    expect.truthy(bus.publish("alert", { kind = "power" }))
    expect.equal(#sent, 1)
    expect.equal(sent[1].protocol, "bus")
    expect.same(sent[1].msg, { topic = "alert", payload = { kind = "power" }, from = os.getComputerID(), label = "Base" })
  end)
  it("opens a modem first when rednet is closed", function()
    local opened = stubModems({ back = "wireless" })
    local sent = 0
    testing.stub(rednet, "broadcast", function() sent = sent + 1 end)
    expect.truthy(bus.publish("x", 1))
    expect.same(opened, { "back" })
    expect.equal(sent, 1)
  end)
  it("returns false and sends nothing without a modem", function()
    stubModems({})
    local sent = 0
    testing.stub(rednet, "broadcast", function() sent = sent + 1 end)
    expect.falsy(bus.publish("x", 1))
    expect.equal(sent, 0)
  end)
  it("refuses a missing topic", function()
    expect.error(function() bus.publish(nil, {}) end, "topic")
  end)
end)

describe("bus.open", function()
  it("prefers a wireless modem", function()
    local opened = stubModems({ back = "wired", top = "wireless", left = "minecraft:chest" })
    expect.truthy(bus.open())
    expect.same(opened, { "top" })
  end)
  it("falls back to the first modem", function()
    local opened = stubModems({ right = "wired", left = "monitor" })
    expect.truthy(bus.open())
    expect.same(opened, { "right" })
  end)
  it("returns false without a modem", function()
    stubModems({ left = "monitor" })
    expect.falsy(bus.open())
  end)
end)

describe("bus.handle", function()
  before_each(function() bus.subscribe("alert") end)
  after_each(function() bus.unsubscribe() end)

  local good = { topic = "alert", payload = { kind = "fuel" }, from = 99, label = "x" }

  it("returns topic, payload and the rednet sender for a subscribed topic", function()
    local topic, payload, sender, msg = bus.handle("rednet_message", 7, good, "bus")
    expect.equal(topic, "alert")
    expect.same(payload, { kind = "fuel" })
    expect.equal(sender, 7)
    expect.equal(msg.label, "x")
  end)
  it("ignores other events and protocols", function()
    expect.falsy(bus.handle("key", 28))
    expect.falsy(bus.handle("rednet_message", 7, good, "turtlectl"))
    expect.falsy(bus.handle("modem_message", "back", 1, 1, good, 5))
  end)
  it("ignores malformed messages", function()
    expect.falsy(bus.handle("rednet_message", 7, "alert", "bus"))
    expect.falsy(bus.handle("rednet_message", 7, { payload = 1 }, "bus"))
    expect.falsy(bus.handle("rednet_message", 7, { topic = 5 }, "bus"))
    expect.falsy(bus.handle("rednet_message", 7, { topic = "" }, "bus"))
    expect.falsy(bus.handle("rednet_message", 7, nil, "bus"))
  end)
  it("ignores topics nobody subscribed to", function()
    expect.falsy(bus.handle("rednet_message", 7, { topic = "base.door" }, "bus"))
  end)
end)

describe("bus.receive", function()
  before_each(function() bus.subscribe("turtle.*") end)
  after_each(function() bus.unsubscribe() end)

  it("skips everything until a subscribed message", function()
    feedEvents({
      { "key", 28 },
      { "rednet_message", 3, { topic = "turtle.status" }, "turtlectl" },
      { "rednet_message", 3, "junk", "bus" },
      { "rednet_message", 3, { topic = "alert", payload = 1 }, "bus" },
      { "rednet_message", 4, { topic = "turtle.status", payload = { state = "idle" } }, "bus" },
    })
    local topic, payload, sender = bus.receive()
    expect.equal(topic, "turtle.status")
    expect.same(payload, { state = "idle" })
    expect.equal(sender, 4)
  end)
  it("returns nil when its own timer fires, not another one", function()
    testing.stub(os, "startTimer", function() return 42 end)
    feedEvents({ { "timer", 41 }, { "timer", 42 } })
    expect.equal(select("#", bus.receive(2)), 1)
  end)
  it("cancels its timer when a message arrives", function()
    local cancelled
    testing.stub(os, "startTimer", function() return 42 end)
    testing.stub(os, "cancelTimer", function(t) cancelled = t end)
    feedEvents({ { "rednet_message", 4, { topic = "turtle.x" }, "bus" } })
    expect.equal(bus.receive(2), "turtle.x")
    expect.equal(cancelled, 42)
  end)
  it("refuses a timeout that is not a number", function()
    expect.error(function() bus.receive("soon") end, "timeout")
  end)
end)

describe("bus.newAlert", function()
  it("names the source by label", function()
    testing.stub(os, "getComputerLabel", function() return "Smelter" end)
    expect.same(bus.newAlert("power", "no power", true),
      { id = os.getComputerID(), source = "Smelter", kind = "power", message = "no power", active = true })
  end)
end)

describe("alert on the bus", function()
  local sent, clock
  before_each(function()
    sent, clock = {}, 1000
    testing.stub(_G, "turtle", nil)
    testing.stub(_G, "print", function() end)
    testing.stub(os, "queueEvent", function() end)
    testing.stub(os, "clock", function() return clock end)
    testing.stub(bus, "publish", function(topic, payload) sent[#sent + 1] = { topic, payload } return true end)
  end)

  it("publishes raise and clear from a plain computer", function()
    alert.raise("power-test", "no power")
    clock = clock + 1
    alert.clear("power-test")
    expect.equal(#sent, 2)
    expect.equal(sent[1][1], "alert")
    expect.equal(sent[1][2].kind, "power-test")
    expect.equal(sent[1][2].message, "no power")
    expect.truthy(sent[1][2].active)
    expect.falsy(sent[2][2].active)
  end)
  it("repeats an unchanged alert only every RepeatSeconds", function()
    alert.raise("loop-test", "full")
    clock = clock + 1
    alert.raise("loop-test", "full")
    expect.equal(#sent, 1)
    alert.raise("loop-test", "fuller")
    expect.equal(#sent, 2)
    clock = clock + alert.RepeatSeconds
    alert.raise("loop-test", "fuller")
    expect.equal(#sent, 3)
  end)
  it("leaves turtles to turtleagent", function()
    testing.useTurtle(testing.fakeTurtle())
    alert.raise("turtle-test", "out of fuel")
    alert.clear("turtle-test")
    expect.equal(#sent, 0)
  end)
end)
