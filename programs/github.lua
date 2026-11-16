--[[
Install or update this repo from GitHub.

Asks the GitHub API for the list of files on a branch, then downloads every
.lua file (except the browser simulator under sim/) to the same path on this
computer. Nothing to maintain when files are added: the list comes from the
repo itself.

First install, on a computer that has nothing yet:

    wget run https://raw.githubusercontent.com/imitablerabbit/computercraft/master/programs/github.lua

Afterwards startup.lua puts programs/ on the path, so `github` updates.
--]]

local owner = "imitablerabbit"
local repo = "computercraft"
local branch = "master"
-- Directories that are never installed on the computer.
local skipDirs = { "sim" }

local function usage()
    print("github [branch]")
    print("Downloads every .lua file of " .. owner .. "/" .. repo .. " from GitHub.")
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

-- Pull the file paths out of a git tree API response.
local function treePaths(json)
    local paths = {}
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
            if entry.type == "blob" then paths[#paths + 1] = entry.path end
        end
    else
        -- Older ComputerCraft has no JSON decoder; the response is one
        -- object per file with a "path" key, which is enough to go on.
        for path in json:gmatch('"path"%s*:%s*"([^"]+)"') do
            paths[#paths + 1] = path
        end
    end
    return paths
end

local function wanted(path)
    if path:sub(-4) ~= ".lua" then return false end
    for _, dir in ipairs(skipDirs) do
        if path == dir or path:sub(1, #dir + 1) == dir .. "/" then return false end
    end
    return true
end

local function save(path, data)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local h, err = fs.open(path, "w")
    if not h then return false, err end
    h.write(data)
    h.close()
    return true
end

-- Parse command line args
local args = { ... }
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

local paths, perr = treePaths(json)
if not paths then
    print("Error: " .. perr)
    return
end

local ok, failed = 0, {}
for _, path in ipairs(paths) do
    if wanted(path) then
        write("fetching " .. path .. " ")
        local data, ferr = fetch(rawURL .. path)
        if data then
            local saved, serr = save(path, data)
            if saved then
                print("ok")
                ok = ok + 1
            else
                print("FAILED (" .. tostring(serr) .. ")")
                failed[#failed + 1] = path
            end
        else
            print("FAILED (" .. ferr .. ")")
            failed[#failed + 1] = path
        end
    end
end

print(("Installed %d file(s), %d failed"):format(ok, #failed))
for _, path in ipairs(failed) do print("  " .. path) end
if ok > 0 then print("Run 'reboot' so startup.lua loads the new files.") end
