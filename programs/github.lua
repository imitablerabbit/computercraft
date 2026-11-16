--[[
Install or update this repo from GitHub.

Asks the GitHub API for the list of files on a branch, then downloads every
.lua file (except the browser simulator under sim/ and the unit tests under
tests/) to the same path on this computer. Nothing to maintain when files are
added: the list comes from the repo itself.

A computer has 1 MB by default, so it checks the files fit before changing
anything, and writes each file next to the old one before swapping it in, so
a failed write leaves the old file as it was. The tests only matter to the
test program; `github [branch] tests` installs them too.

First install, on a computer that has nothing yet:

    wget run https://raw.githubusercontent.com/imitablerabbit/computercraft/master/programs/github.lua

Afterwards startup.lua puts programs/ on the path, so `github` updates.
--]]

local owner = "imitablerabbit"
local repo = "computercraft"
local branch = "master"
-- Directories that are not installed on the computer (tests only when asked).
local skipDirs = { "sim", "tests" }
-- ComputerCraft counts every file as at least this many bytes.
local minFileSize = 500
-- Room kept for new folders and settings files.
local spare = 8000

local function usage()
    print("github [branch] [tests]")
    print("Downloads every .lua file of " .. owner .. "/" .. repo .. " from GitHub.")
    print("tests: the unit tests too, for the test program.")
end

-- GET a URL and return its body, or nil and a reason.
local function fetch(url)
    local r, err = http.get(url)
    if not r then return nil, err or "no response" end
    local code = r.getResponseCode()
    local body = r.readAll()
    r.close()
    if code ~= 200 then return nil, "HTTP " .. tostring(code) end
    return body
end

-- Pull the file paths out of a git tree API response, with their sizes
-- in bytes (path -> size) when they are known.
local function treePaths(json)
    local paths, sizes = {}, {}
    local decode = textutils.unserialiseJSON or textutils.unserializeJSON
    if decode then
        local tree = decode(json)
        if type(tree) ~= "table" or type(tree.tree) ~= "table" then
            return nil, "unexpected API response"
        end
        if tree.truncated then
            print("Warning: GitHub truncated the file list")
        end
        for _, entry in ipairs(tree.tree) do
            if entry.type == "blob" then
                paths[#paths + 1] = entry.path
                sizes[entry.path] = tonumber(entry.size)
            end
        end
    else
        -- Older ComputerCraft has no JSON decoder; the response is one
        -- object per file with a "path" key, which is enough to go on.
        for path in json:gmatch('"path"%s*:%s*"([^"]+)"') do
            paths[#paths + 1] = path
        end
    end
    return paths, sizes
end

local function wanted(path)
    if path:sub(-4) ~= ".lua" then return false end
    for _, dir in ipairs(skipDirs) do
        if path == dir or path:sub(1, #dir + 1) == dir .. "/" then return false end
    end
    return true
end

-- Write to a new file first and only then replace the old one, so a
-- write that fails leaves the old file as it was.
local function save(path, data)
    local part = path .. ".part"
    local ok, err = pcall(function()
        local dir = fs.getDir(path)
        if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
        local h, openErr = fs.open(part, "w")
        if not h then error(openErr or ("cannot open " .. part), 0) end
        local wrote, writeErr = pcall(h.write, data)
        h.close()
        if not wrote then error(writeErr, 0) end
        if fs.exists(path) then fs.delete(path) end
        fs.move(part, path)
    end)
    if not ok then
        pcall(fs.delete, part)
        return false, tostring(err)
    end
    return true
end

-- Bytes more than the computer has now that the files need, or nil
-- when the sizes are not known. Files already here are replaced, so
-- their space counts as free.
local function spaceNeeded(paths, sizes)
    local need = spare
    for _, path in ipairs(paths) do
        local size = sizes[path]
        if not size then return nil end
        need = need + math.max(size, minFileSize)
        if fs.exists(path) and not fs.isDir(path) then
            need = need - math.max(fs.getSize(path), minFileSize)
        end
    end
    return need
end

-- Parse command line args
local args = { ... }
if args[#args] == "tests" then
    table.remove(args)
    skipDirs = { "sim" }
end
if #args > 1 or args[1] == "help" or args[1] == "-help" or args[1] == "--help" then
    usage()
    return
end
if args[1] then branch = args[1] end

if not http then
    print("Error: the http API is disabled in this world's ComputerCraft config")
    return
end

local treeURL = "https://api.github.com/repos/" .. owner .. "/" .. repo
    .. "/git/trees/" .. branch .. "?recursive=1"
local rawURL = "https://raw.githubusercontent.com/" .. owner .. "/" .. repo
    .. "/" .. branch .. "/"

print("Listing " .. owner .. "/" .. repo .. " @ " .. branch)
local json, err = fetch(treeURL)
if not json then
    print("Error: unable to list files: " .. err)
    if err == "HTTP 404" then print("Does branch '" .. branch .. "' exist?") end
    if err == "HTTP 403" then print("GitHub rate limit hit; try again in an hour") end
    return
end

local paths, sizes = treePaths(json)
if not paths then
    print("Error: " .. sizes)
    return
end

local wantedPaths = {}
for _, path in ipairs(paths) do
    if wanted(path) then wantedPaths[#wantedPaths + 1] = path end
end

local need = spaceNeeded(wantedPaths, sizes)
local free = fs.getFreeSpace("/")
if need and type(free) == "number" and need > free then
    print(("Not enough space: this needs about %d KB more, and the computer has %d KB free.")
        :format(math.ceil(need / 1000), math.floor(free / 1000)))
    print("Nothing was changed. Delete files you do not need, or raise")
    print("computer_space_limit in computercraft-server.toml.")
    return
end

local ok, failed = 0, {}
for _, path in ipairs(wantedPaths) do
    write("fetching " .. path .. " ")
    local data, ferr = fetch(rawURL .. path)
    local saved, serr = false, ferr
    if data then saved, serr = save(path, data) end
    if saved then
        print("ok")
        ok = ok + 1
    else
        print("FAILED (" .. tostring(serr) .. ")")
        failed[#failed + 1] = path
        if tostring(serr):find("Out of space") then
            print("The computer is full; stopping. The files not fetched are as they were.")
            break
        end
    end
end

print(("Installed %d file(s), %d failed"):format(ok, #failed))
for _, path in ipairs(failed) do print("  " .. path) end
if ok > 0 then print("Run 'reboot' so startup.lua loads the new files.") end
