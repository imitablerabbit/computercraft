--[[
Automatically load the apis in the apis folder.
--]]

-- Fold over files recurse folders. Call fun on all the
-- individual files.
function foldFiles(fun, acc, folder)
  if not fun then error("undefined fold fun") end
  if not folder then error("undefined folder in fold") end
  local wildcard = fs.combine(folder, "*")
  local fx = fs.find(wildcard)
  if not fx then return end -- nothing to do
  for i, f in pairs(fx) do
    if fs.isDir(f) then
      foldFiles(fun, acc, f)
    else
      acc = fun(f, acc)
    end
  end
  return acc
end

-- Fold over files recurse folders. Call fun on all the
-- individual files.
function foldDirs(fun, acc, folder)
  if not fun then error("undefined fold fun") end
  if not folder then error("undefined folder in fold") end
  acc = fun(folder, acc)
  local wildcard = fs.combine(folder, "*")
  local fx = fs.find(wildcard)
  if not fx then return end -- nothing to do
  for i, f in pairs(fx) do
    if fs.isDir(f) then
      acc = foldFiles(fun, acc, f)
    end
  end
  return acc
end

-- Recursively load all files nested under the apis folder.
local apiDir = "/apis"
local loadAPIs = function(f, acc) 
  return os.loadAPI(f) and acc
end
foldFiles(loadAPIs, true, apiDir)

-- Set the path so that the programs folder is loaded
local path = shell.path()
local programDir = "/programs" 
local addPath = function(f, acc)
  return acc..":"..f
end
local newPath = foldDirs(addPath, path, programDir)
shell.setPath(newPath)
