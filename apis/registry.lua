--[[
Registry module can be used to keep track of the
different computers, turtles and pocket pcs in the
world.
--]]

local Registry = {
  records = {} -- Holds all of the registered computers
}

--[[
API Functions
--]]

-- Create a new blank registry.
function new()
  r = { records={} }
  setmetatable(r, Registry)
  Registry.__index = Registry
  return r
end

-- Read the registry records from a file.
function Registry:loadFile(file)
  if not file then file = registryFile end
  local h = fs.open(file, "r")
  local d = h.readAll()
  h.close()
  self.records = textutils.unserialize(d)
end

-- Save the registry records to a file.
function Registry:saveFile(file)
  if not file then file = registryFile end
  local d = textutils.serialize(self.records)
  local h = fs.open(file, "w")
  h.write(d)
  h.close()
end

-- Register a new computer to the registry object.
function Registry:register(id, n, l)
  local record = { id, n, l }
  table.insert(self.records, record)
end

-- Print out the registry records in table format.
function Registry:display()
  local regHeader = { colors.orange, { "ID", "Type", "Label" }, colors.white }
  tableContents = {} -- Combine header and registry
  for i, v in pairs(regHeader) do
    table.insert(tableContents, v)
  end
  for i, v in pairs(self.records) do
    table.insert(tableContents, v)
  end
  term.setTextColor(colors.blue)
  print("Registry: "..os.getComputerID())
  print()
  textutils.tabulate(unpack(tableContents))
end