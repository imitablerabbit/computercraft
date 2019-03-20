--[[
Pull all of the files from github using the http api    
--]]

local files = {
    "apis/files.lua",
    "apis/inventory.lua",
    "apis/mine.lua",
    "apis/move.lua",
    "apis/registry",

    "programs/register.lua",
    "programs/registrydisplay.lua",
    "programs/registrylistener.lua",
    "programs/remotecommand.lua",
    "programs/remotelistener.lua",

    "programs/turtle/logger.lua",
    "programs/turtle/mineline.lua",
    "programs/turtle/stripmine.lua",

    "startup.lua"
}

local githubURL = "https://raw.github.com/imitablerabbit/computercraft/"

-- Fetch a single raw file from github url
function fetchFile(url, filepath)
    if not url then error("missing url") end
    if not filepath then error("missing file path") end

    r = http.get(url)
    if not r then return false end
    if r.getResponseCode() ~= 200 then
        r.close()
        return false
    end
    d = r.readAll()
    r.close()
    h = fs.open(filepath, "w")
    h.write(d)
    h.close()
    return true
end

for k, file in pairs(files) do
    url = githubURL .. file
    if not fetchFile(url, file) then
        print("Error: unable to fetch file: "..file)
    end
end