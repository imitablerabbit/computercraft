--[[
A tour of the newer components, built with guibuild. The Meters tab
has a progress bar that keeps filling, a fuel bar that turns red when
low, an energy gauge, a tank gauge and a sparkline fed by a timer. The
Items tab is a table: touch a column title to sort by it (again to
reverse), touch a row to select it, Remove asks before removing it.
Theme switches between the dark and light themes, Alert shows a
message box and Quit asks first.
--]]

local w, h = term.getSize()
local compact = guitheme.isCompact(w, h)
local short = h < 16 -- a turtle's screen: no room for gaps
local previousTheme = guitheme.isChosen() and guitheme.getTheme() or nil
guitheme.setTheme("dark")

local app = guiapplication.GUIApplication.new()
local root, ids

local items = {
  { "Coal", 48, "fuel" }, { "Cobblestone", 512, "block" }, { "Torch", 30, "light" },
  { "Iron ore", 17, "ore" }, { "Oak log", 64, "fuel" }, { "Diamond", 3, "ore", color = colors.lightBlue },
  { "Redstone", 120, "ore", color = colors.red }, { "Sand", 200, "block" }, { "Gravel", 75, "block" },
}

local function status(text)
  ids.status:setText(text)
end

local function removeSelected()
  local index, row = ids.items:getSelected()
  if not row then return status("Touch a row first.") end
  guidialog.confirm(root, "Remove", "Remove " .. row[1] .. " from the list?", function()
    table.remove(items, index)
    ids.items:setRows(items)
    ids.items:select(nil)
    status("Removed " .. row[1] .. ".")
  end, function() status("Kept " .. row[1] .. ".") end, { yes = "Remove", no = "Keep", danger = true })
end

local function toggleTheme()
  local name = (guitheme.getTheme() == "dark") and "light" or "dark"
  guitheme.use(name, root)
  ids.theme:setText("Theme: " .. name)
  status("Switched to the " .. name .. " theme.")
end

local meters = {
  type = "box", title = "Meters", dir = "vertical", gap = short and 0 or 1, padding = short and 0 or 1, children = {
    { type = "text", text = "Job progress", fgRole = "muted", h = 1 },
    { type = "progress", id = "job", value = 0, max = 64, h = 1 },
    { type = "text", text = "Fuel (red below 20%)", fgRole = "muted", h = 1 },
    { type = "progress", id = "fuel", value = 80, max = 100, showPercent = true, warnBelow = 20, h = 1 },
    { type = "box", dir = "horizontal", gap = 1, flex = 1, children = {
      { type = "gauge", id = "energy", min = 0, max = 1000, value = 600, label = "RF", w = 5, warnBelow = 200 },
      { type = "box", dir = "vertical", gap = 1, flex = 1, children = {
        { type = "gauge", id = "tank", dir = "horizontal", min = 0, max = 16, value = 9, label = "Tank", h = 1,
          format = function(v) return v .. "B" end },
        { type = "sparkline", id = "spark", showRange = not compact, flex = 1 },
      } },
    } },
  },
}

local itemsTab = {
  type = "box", title = "Items", dir = "vertical", gap = 0, children = {
    { type = "table", id = "items", flex = 1, striped = true, emptyText = "Nothing left.",
      columns = { { title = "Item", flex = 1 }, { title = "Count", width = 6, align = "right" },
                  { title = "Kind", width = compact and 5 or 7 } },
      rows = items,
      onSelect = function(e) status("Selected " .. e.row[1] .. " x" .. e.row[2]) end },
  },
}

root, ids = guibuild.build({
  type = "root", title = "Widgets", dir = "vertical", gap = 0, children = {
    { type = "tabs", id = "tabs", flex = 1, children = { meters, itemsTab },
      onChange = function(e) status("Tab " .. e.title) end },
    { type = "text", id = "status", text = "Touch a tab, a title or a row.", h = 1, fgRole = "muted" },
    { type = "grid", rows = 1, columns = 4, gap = 1, h = 1, children = {
      { type = "button", id = "theme", text = "Theme: dark", onPress = toggleTheme },
      { type = "button", text = "Remove", onPress = removeSelected },
      { type = "button", text = "Alert", onPress = function()
          guidialog.alert(root, "Hello", "This is a message box. Nothing underneath can be pressed until it is closed.")
        end },
      { type = "button", text = "Quit", onPress = function()
          guidialog.confirm(root, "Quit", "Leave the widgets example?", function() app:stop() end, nil,
            { yes = "Quit", no = "Stay", danger = true })
        end },
    } },
  },
})
app:setRootContainer(root)

-- The timer drives the meters: the job creeps along, fuel burns down
-- and is topped up, the energy wanders and the sparkline records it.
local timer = os.startTimer(0.5)
local energy = 600
app:addEventListener(function(event)
  if event[1] ~= "timer" or event[2] ~= timer then return end
  timer = os.startTimer(0.5)
  local job = ids.job:getValue() + 1
  if job > 64 then job = 0 end
  ids.job:setProgress(job, 64, job .. "/64 blocks")
  local fuel = ids.fuel:getValue() - 3
  if fuel < 0 then fuel = 100 end
  ids.fuel:setValue(fuel)
  energy = math.max(0, math.min(1000, energy + math.random(-120, 110)))
  ids.energy:setValue(energy)
  ids.tank:setValue((ids.tank:getValue() + 1) % 17)
  ids.spark:push(energy)
end)

app:setUPS(20)
app:start()
guitheme.setTheme(previousTheme)
