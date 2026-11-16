--[[
Tests for the on-screen keyboard: its keys fit the screen at every
size, and the keys type, delete, clear and finish as they should.
--]]

-- A keyboard laid out for a screen of w x h, without showing it.
local function laidOut(w, h, opts)
  local k = guikeyboard.GUIKeyboard.new("Search items", "", opts)
  k:build({ w = w, h = h })
  return k
end

-- A keyboard that takes presses, as if it were open.
local function opened(text, opts)
  local k = guikeyboard.GUIKeyboard.new("Type", text, opts)
  k:build({ w = 39, h = 19 })
  k.open = true
  k.ax, k.ay = 1, 1
  return k
end

local function keyFor(k, what)
  for _, key in ipairs(k.keys) do
    if key.char == what or key.action == what then return key end
  end
end

describe("keyboard layout", function()
  for _, size in ipairs({ { 26, 20 }, { 39, 13 }, { 51, 19 }, { 57, 24 }, { 29, 12 }, { 82, 40 }, { 22, 9 } }) do
    it("fits a " .. size[1] .. "x" .. size[2] .. " screen", function()
      local k = laidOut(size[1], size[2], { hint = function() return "" end })
      expect.truthy(k.w <= size[1] and k.h <= size[2], "box " .. k.w .. "x" .. k.h)
      expect.equal(#k.keys, 46)
      for i, a in ipairs(k.keys) do
        expect.truthy(a.x >= 1 and a.y >= 1 and a.x + a.w - 1 <= k.w and a.y + a.h - 1 <= k.h,
          "key " .. i .. " out of the box")
        expect.truthy(a.y > 2, "key " .. i .. " over the text")
        for j = i + 1, #k.keys do
          local b = k.keys[j]
          local apart = a.x + a.w <= b.x or b.x + b.w <= a.x or a.y + a.h <= b.y or b.y + b.h <= a.y
          expect.truthy(apart, "keys " .. i .. " and " .. j .. " overlap")
        end
      end
    end)
  end

  it("makes the keys bigger on a big screen", function()
    expect.equal(laidOut(26, 20).keys[1].w, 2)
    expect.equal(laidOut(82, 40).keys[1].h, 3)
    expect.equal(laidOut(39, 13).keys[1].h, 1)
  end)

  it("finds the key under a point", function()
    local k = laidOut(39, 19)
    local q = keyFor(k, "q")
    expect.equal(k:keyAt(q.x, q.y), q)
    expect.equal(k:keyAt(1, 1), nil)
  end)
end)

describe("keyboard keys", function()
  it("types, deletes, clears and capitalises", function()
    local changes = 0
    local k = opened("co", { onChange = function() changes = changes + 1 end })
    k:press(keyFor(k, "a"))
    k:press(keyFor(k, "l"))
    expect.equal(k:getText(), "coal")
    k:press(keyFor(k, "back"))
    expect.equal(k:getText(), "coa")
    k:press(keyFor(k, "space"))
    k:press(keyFor(k, "shift"))
    k:press(keyFor(k, "x"))
    expect.equal(k:getText(), "coa X")
    expect.equal(k:labelOf(keyFor(k, "q")), "Q")
    k:press(keyFor(k, "clear"))
    expect.equal(k:getText(), "")
    expect.equal(changes, 6)
  end)

  it("gives the text to onDone, and nothing on cancel", function()
    local got, cancelled
    local k = opened("", { onDone = function(t) got = t end })
    k:press(keyFor(k, "7"))
    k:press(keyFor(k, "done"))
    expect.equal(got, "7")
    expect.falsy(k:isOpen())
    got = nil
    local k2 = opened("abc", { onDone = function(t) got = t end, onCancel = function() cancelled = true end })
    k2:press(keyFor(k2, "cancel"))
    expect.equal(got, nil)
    expect.truthy(cancelled)
  end)

  it("stops at maxLength", function()
    local k = opened("12", { maxLength = 3 })
    k:press(keyFor(k, "3"))
    k:press(keyFor(k, "4"))
    expect.equal(k:getText(), "123")
  end)

  it("presses the key touched but not on the touch that opened it", function()
    local k = opened("")
    local e = keyFor(k, "e")
    local opening = { x = e.x, y = e.y }
    k.ignore = opening
    k:touchHandler(opening)
    expect.equal(k:getText(), "")
    k:touchHandler({ x = e.x, y = e.y })
    expect.equal(k:getText(), "e")
  end)

  it("shows the hint for the text", function()
    local k = opened("co", { hint = function(t) return #t .. " letters" end })
    expect.equal(k:hintText(), "2 letters")
  end)
end)
