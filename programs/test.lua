--[[
Test runs the unit tests written with the testing API. With no
arguments it runs every file ending in _test.lua under /tests; given
files or folders it runs just those, and a bare name such as
"inventory" means tests/inventory_test.lua. Each test is printed with
ok or FAIL (green and red on an advanced computer), failures are
listed again at the end with their errors, then a summary line. When
anything failed the program ends with an error, so shell.run returns
false and scripts can tell.

Usage: test [-q] [file or folder ...]
  -q  only print failures and the summary
--]]

local TestDir = "/tests"
local Suffix = "_test.lua"

local quiet = false
local targets = {}
for _, a in ipairs({ ... }) do
  if a == "-q" then quiet = true
  elseif a == "-h" or a == "--help" then
    print("Usage: test [-q] [file or folder ...]")
    return
  else
    table.insert(targets, a)
  end
end

-- Every *_test.lua below a folder, sorted.
local function findTests(dir, found)
  local entries = fs.list(dir)
  table.sort(entries)
  for _, name in ipairs(entries) do
    local path = fs.combine(dir, name)
    if fs.isDir(path) then
      findTests(path, found)
    elseif name:sub(-#Suffix) == Suffix then
      table.insert(found, path)
    end
  end
  return found
end

local files = {}
if #targets == 0 then
  if not fs.isDir(TestDir) then error("no " .. TestDir .. " folder", 0) end
  findTests(TestDir, files)
else
  for _, t in ipairs(targets) do
    local path = shell.resolve(t)
    if not fs.exists(path) then
      local named = fs.combine(TestDir, t .. Suffix)
      if fs.exists(named) then path = named end
    end
    if fs.isDir(path) then findTests(path, files)
    elseif fs.exists(path) then table.insert(files, path)
    else error("no test file " .. t, 0) end
  end
end

local colour = term.isColour and term.isColour()
local function say(text, c)
  if colour and c then
    local old = term.getTextColour()
    term.setTextColour(c)
    print(text)
    term.setTextColour(old)
  else
    print(text)
  end
end

local summary = testing.runFiles(files, {
  file = function(path) if not quiet then say(path, colours.lightBlue) end end,
  loadError = function(path, err) say("  FAIL loading: " .. err, colours.red) end,
  result = function(path, name, ok, err)
    if ok then
      if not quiet then say("  ok   " .. name, colours.green) end
    else
      say("  FAIL " .. name, colours.red)
      if quiet then say("       " .. err, colours.orange) end
    end
  end,
})

if #summary.failures > 0 then
  print()
  say("Failures:", colours.red)
  for _, f in ipairs(summary.failures) do
    say(fs.getName(f.file) .. ": " .. f.name, colours.red)
    say("  " .. f.err, colours.orange)
  end
end
say(string.format("tests: %d passed, %d failed, %d files", summary.passed, summary.failed, summary.files),
  summary.failed == 0 and colours.green or colours.red)
if summary.failed > 0 then
  error(summary.failed .. " test" .. (summary.failed == 1 and "" or "s") .. " failed", 0)
end
