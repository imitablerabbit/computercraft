--[[
Jobform builds the parameter form of a turtle control catalogue job
(apis/turtlectl.lua): one row per parameter, or two on narrow screens.
Numbers get -10, -1, +1 and +10 buttons (the param's step), switches a
checkbox, choices a dropdown whose options can follow the other values
(optionsFor), and text values a button that asks for the text, or a
dropdown of suggestions with Other... (and Discover... when the
program can offer it) at the end. turtle control's job screen and the
dispatcher's Add screen both use it.

  local startY, startH = jobform.add(root, job, values, {
    top = 3, w = w, h = h,
    onText = function(param) ... end,      -- type a text value
    onDiscover = function(param) ... end,  -- optional: pick from the turtle
  })
  root:add(startButton at row startY, startH rows high)

values (param name -> value) is changed in place as the form is used.
onText and onDiscover are called for the program to show its own
screen; when that is done it sets values[param.name] and builds the
form again.
--]]

local function newLabel(text, x, y, w, color)
  local label = guitext.GUIText.new(text)
  label:setPreferredBounds(x, y, math.max(1, w), 1)
  label:setBorder(false)
  label:setBackgroundColor(colors.black)
  label:setTextColor(color or colors.white)
  return label
end

local function newButton(text, x, y, w, h, color, onClick)
  local button = guibutton.GUIButton.new(text)
  button:setPreferredBounds(x, y, math.max(1, w), math.max(1, h))
  button:setBackgroundColor(color or colors.blue)
  button.pressColor = colors.lightGray
  button:setTextColor(colors.white)
  button:setBorderColor(colors.gray)
  button:setBorder(h >= 3)
  if onClick then button:addButtonListener(onClick) end
  return button
end

-- A dropdown showing value (or the first option) from options.
function newDropdown(options, value, x, y, w)
  local index = 1
  for i, o in ipairs(options) do
    if o == value then index = i end
  end
  local dropdown = guidropdown.GUIDropdown.new(options, index)
  dropdown:setPreferredBounds(x, y, math.max(3, w), 1)
  dropdown:setBackgroundColor(colors.cyan)
  dropdown:setTextColor(colors.white)
  dropdown:setListColor(colors.gray)
  dropdown:setHighlightColor(colors.lightGray)
  return dropdown
end

-- Add the rows for job's params to root from row opts.top in a
-- opts.w x opts.h screen. Returns the row and height for the start
-- button below them.
function add(root, job, values, opts)
  local w, h = opts.w, opts.h
  local top = opts.top or 3
  local params = job.params or {}
  local labelW = math.min(12, math.floor(w / 3))
  -- When the five number buttons do not fit beside the label, each
  -- parameter takes two rows: the label, then its controls.
  local narrow = w - labelW - 1 < 20
  local rowsPer = narrow and 2 or 1
  local startH = (h - top >= #params * (rowsPer + 1) + 3) and 3 or 1
  local gap = (h - top - startH >= #params * (rowsPer + 1)) and (rowsPer + 1) or rowsPer
  local cellW = math.max(3, math.floor(((narrow and (w - 1)) or (w - labelW - 1)) / 5))
  local valueButtons = {}
  local dependents = {} -- dropdowns whose options follow other values

  local function valueText(param)
    local v = values[param.name]
    if param.type == "bool" then return v and "true" or "false" end
    return tostring(v)
  end

  -- After any value changes, dropdowns with optionsFor get their
  -- options again; a value that is no longer offered becomes the first
  -- one that is.
  local function refreshDependents()
    for _, d in ipairs(dependents) do
      local options = turtlectl.paramOptions(d.param, values)
      local current = values[d.param.name]
      local known, index = false, 1
      for i, o in ipairs(options) do
        if o == current then known, index = true, i end
      end
      if not known then
        current = options[1]
        values[d.param.name] = current
      end
      d.dropdown:setOptions(options, index)
    end
  end

  for i, param in ipairs(params) do
    local y = top + (i - 1) * gap
    root:add(newLabel(param.label, 1, y, narrow and (w - 1) or labelW, colors.lightGray))
    local x = labelW + 2
    if narrow then x, y = 2, y + 1 end
    if param.type == "number" then
      local small = (param.step and param.step[1]) or 1
      local big = (param.step and param.step[2]) or 10
      local function adjust(delta)
        local v = (tonumber(values[param.name]) or param.default) + delta
        if param.min and v < param.min then v = param.min end
        if param.max and v > param.max then v = param.max end
        values[param.name] = v
        valueButtons[i]:setText(valueText(param))
        refreshDependents()
      end
      root:add(newButton("-" .. big, x, y, cellW - 1, 1, colors.blue, function() adjust(-big) end))
      root:add(newButton("-" .. small, x + cellW, y, cellW - 1, 1, colors.blue, function() adjust(-small) end))
      valueButtons[i] = newLabel(valueText(param), x + cellW * 2, y, cellW - 1, colors.yellow)
      valueButtons[i]:setTextAlign("center")
      root:add(valueButtons[i])
      root:add(newButton("+" .. small, x + cellW * 3, y, cellW - 1, 1, colors.blue, function() adjust(small) end))
      root:add(newButton("+" .. big, x + cellW * 4, y, cellW - 1, 1, colors.blue, function() adjust(big) end))
    elseif param.type == "bool" then
      local box = guicheckbox.GUICheckbox.new(values[param.name] and "yes" or "no", values[param.name])
      box:setPreferredBounds(x, y, cellW * 2 - 1, 1)
      box:addChangeListener(function(e)
        values[param.name] = e.checked
        box:setText(e.checked and "yes" or "no")
        refreshDependents()
      end)
      root:add(box)
    elseif param.type == "choice" or (param.type == "string" and (param.options or param.optionsFor)) then
      -- A dropdown. A text parameter with options also offers Other...
      -- which asks for the text, and shows a typed value at the top.
      local options = {}
      for i, o in ipairs(turtlectl.paramOptions(param, values)) do options[i] = tostring(o) end
      local custom = param.type == "string"
      local current = values[param.name]
      if param.optionsFor and param.type == "choice" then
        local known = false
        for _, o in ipairs(options) do
          if o == current then known = true end
        end
        if not known then
          current = options[1]
          values[param.name] = current
        end
      end
      if custom then
        local known = false
        for _, o in ipairs(options) do
          if o == current then known = true end
        end
        if current ~= nil and current ~= "" and not known then table.insert(options, 1, tostring(current)) end
        if opts.onDiscover then table.insert(options, "Discover...") end
        table.insert(options, "Other...")
      end
      local longest = 0
      for _, o in ipairs(options) do longest = math.max(longest, #o) end
      local dw = math.min(w - x + 1, math.max(cellW * 2 - 1, longest + 3))
      local dropdown = newDropdown(options, current, x, y, dw)
      dropdown:addSelectListener(function(e)
        if custom and e.value == "Other..." then
          opts.onText(param)
        elseif custom and e.value == "Discover..." then
          opts.onDiscover(param)
        else
          values[param.name] = e.value
          refreshDependents()
        end
      end)
      if param.optionsFor then table.insert(dependents, { param = param, dropdown = dropdown }) end
      root:add(dropdown)
    else
      root:add(newButton(valueText(param), x, y, w - x, 1, colors.purple, function()
        opts.onText(param)
      end))
    end
  end

  return math.min(h - startH + 1, top + #params * gap), startH
end
