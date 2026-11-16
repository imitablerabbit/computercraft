--[[
Pull all of the files from github using the http api.
--]]

-- Print a usage string on how to use the command
function usage()
    print("github [branch]")
end

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

-- Global variables
local files = {
    "apis/alert.lua",
    "apis/excavate.lua",
    "apis/files.lua",
    "apis/inventory.lua",
    "apis/mine.lua",
    "apis/move.lua",
    "apis/reconstruct.lua",
    "apis/registry.lua",
    "apis/turtlectl.lua",
    "apis/turtleinv.lua",

    "apis/gui/guiapplication.lua",
    "apis/gui/guicomponent.lua",
    "apis/gui/guicomponentui.lua",
    "apis/gui/guievent.lua",
    "apis/gui/guimodel.lua",
    "apis/gui/rootcontainer/guirootcontainer.lua",
    "apis/gui/rootcontainer/guirootcontainerui.lua",
    "apis/gui/button/guibutton.lua",
    "apis/gui/button/guibuttonmodel.lua",
    "apis/gui/button/guibuttonui.lua",
    "apis/gui/text/guitext.lua",
    "apis/gui/text/guitextui.lua",
    "apis/gui/input/guiinput.lua",
    "apis/gui/input/guiinputmodel.lua",
    "apis/gui/input/guiinputui.lua",
    "apis/gui/scrollpane/guiscrollpane.lua",
    "apis/gui/scrollpane/guiscrollpaneui.lua",
    "apis/gui/turtleicon/guiturtleicon.lua",
    "apis/gui/turtleicon/guiturtleiconui.lua",
    "apis/gui/checkbox/guicheckbox.lua",
    "apis/gui/checkbox/guicheckboxui.lua",
    "apis/gui/dropdown/guidropdown.lua",
    "apis/gui/dropdown/guidropdownui.lua",
    "apis/gui/inventorygrid/guiinventorygrid.lua",
    "apis/gui/layout/guilayout.lua",
    "apis/gui/inventorygrid/guiinventorygridui.lua",
    
    "programs/gui/examples/button.lua",
    "programs/gui/examples/input.lua",
    "programs/register.lua",
    "programs/registrydisplay.lua",
    "programs/registrylistener.lua",
    "programs/remotecommand.lua",
    "programs/remotelistener.lua",
    "programs/github.lua",
    "programs/gui/examples/files.lua",
    "programs/gui/examples/form.lua",
    "programs/gui/examples/layout.lua",
    "programs/gui/examples/todo.lua",
    "programs/turtlecontrol.lua",

    "programs/turtle/logger.lua",
    "programs/turtle/flatten.lua",
    "programs/turtle/inventorygui.lua",
    "programs/turtle/loggergui.lua",
    "programs/turtle/mineline.lua",
    "programs/turtle/quarry.lua",
    "programs/turtle/reconstruct.lua",
    "programs/turtle/stripmine.lua",
    "programs/turtle/turtleagent.lua",

    "startup.lua",
}
local branch = "master"
local githubBaseURL = "https://raw.github.com/imitablerabbit/computercraft/"

-- Parse command line args
local args = {...}
if #args > 1 then
  usage()
  return
end
if args[1] then
  if args[1] == "help" or args[1] == "-help" or args[1] == "--help" then
    usage()
    return
  end
  branch = args[1]
end

githubURL = githubBaseURL..branch.."/"
for k, file in pairs(files) do
    url = githubURL..file
    print("fetching "..file)
    if not fetchFile(url, file) then
        print("Error: unable to fetch file: "..file)
    end
end
