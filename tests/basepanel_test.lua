--[[
Tests for which screen gets which input: a GUI on the computer's own
screen ignores monitor touches (multishell gives them to every tab),
a GUI on a monitor takes only that monitor's touches, and two panels
on one computer cannot share a monitor.
--]]

local function root(side)
  local r = guirootcontainer.GUIRootContainer.new(window.create(term.current(), 1, 1, 20, 6, false), side)
  r.touches, r.clicks = 0, 0
  r:addMonitorTouchListener(function() r.touches = r.touches + 1 end)
  r:addMouseClickListener(function() r.clicks = r.clicks + 1 end)
  return r
end

local function touch(r, side)
  r:triggerMonitorTouchEvent(guievent.GUIMonitorTouchEvent.new(side, 2, 2))
end

describe("screen input", function()
  it("keeps monitor touches away from a GUI on the computer's own screen", function()
    local r = root(nil)
    touch(r, "right")
    touch(r, "monitor_0")
    expect.equal(r.touches, 0)
    r:triggerMouseClickEvent(guievent.GUIMouseClickEvent.new(1, 2, 2))
    expect.equal(r.clicks, 1)
  end)

  it("gives a GUI on a monitor only that monitor's touches", function()
    local r = root("right")
    touch(r, "left")
    expect.equal(r.touches, 0)
    touch(r, "right")
    expect.equal(r.touches, 1)
    r:triggerMouseClickEvent(guievent.GUIMouseClickEvent.new(1, 2, 2))
    expect.equal(r.clicks, 0)
  end)
end)

describe("basepanel monitors", function()
  local monitors

  -- Two advanced monitors, right and top.
  before_each(function()
    monitors = {}
    for _, name in ipairs({ "right", "top" }) do
      monitors[name] = {
        isColor = function() return true end, setTextScale = function() end,
        getSize = function() return 40, 20 end, name = name,
      }
    end
    testing.stub(peripheral, "hasType", function(name, t) return t == "monitor" and monitors[name] ~= nil end)
    testing.stub(peripheral, "wrap", function(name) return monitors[name] end)
    testing.stub(peripheral, "getName", function(m) return m.name end)
    testing.stub(peripheral, "find", function(t, filter)
      for _, name in ipairs({ "right", "top" }) do
        if t == "monitor" and (not filter or filter(name, monitors[name])) then return monitors[name] end
      end
    end)
  end)

  -- what this test took is free for the next
  after_each(function()
    basepanel.release({ side = "right" })
    basepanel.release({ side = "top" })
  end)

  -- A panel in another tab: display called from its own coroutine,
  -- which stays alive until finish is called.
  local function otherTab(arg)
    local disp
    local co = coroutine.create(function()
      disp = basepanel.display(arg, 30, 12)
      coroutine.yield()
      basepanel.release(disp)
    end)
    coroutine.resume(co)
    return disp, function() coroutine.resume(co) end
  end

  it("will not put a second panel on a monitor another tab is using", function()
    local disp, finish = otherTab("right")
    expect.equal(disp.side, "right")
    local d, why = basepanel.display("right", 30, 12)
    expect.falsy(d)
    expect.match(why, "already showing")
    -- with no monitor named it takes the free one
    local free = basepanel.display(nil, 30, 12)
    expect.equal(free.side, "top")
    basepanel.release(free)
    finish()
    expect.equal(basepanel.display("right", 30, 12).side, "right")
  end)

  it("says so when every monitor is in use", function()
    local _, finishRight = otherTab("right")
    local _, finishTop = otherTab("top")
    local d, why = basepanel.display(nil, 30, 12)
    expect.falsy(d)
    expect.match(why, "already showing")
    finishRight()
    finishTop()
  end)

  it("forgets the monitor of a panel whose tab has ended", function()
    local co = coroutine.create(function() basepanel.display("right", 30, 12) end)
    coroutine.resume(co)
    expect.equal(coroutine.status(co), "dead")
    expect.equal(basepanel.display("right", 30, 12).side, "right")
  end)

  it("lets a panel run again from the same tab after it failed", function()
    expect.truthy(basepanel.display("right", 30, 12))
    expect.truthy(basepanel.display("right", 30, 12))
  end)
end)
