--[[
A storage at the base, used from afar: what "storage remote" runs on a
pocket computer. It stands in for the storage object of
apis/storage.lua, so the storage program shows the same screens, but
every answer comes from the storage computer over the bus, and items
go to and from the remote's own chest on the storage network (an ender
chest, say, whose other half the player carries).

  local s = remotestorage.new(remotestorage.loadConfig())
  s:refresh()                        -- the item list, from the base
  s:register("enderstorage:ender_chest_0")
  s:withdraw("minecraft:coal", 16)   -- delivered to that chest
  s:deposit()                        -- empty that chest into storage

The messages, each answered to the asker (to) with the same requestId,
and only by the storage computer named in server when it is given:

  base.storage.list     {}                 -> base.storage.items
      { label, items = { { key, name, nbt, displayName, count, maxCount } },
        used, total, chest, choices, recipes }
  base.storage.register { chest, label }   -> base.storage.registered { ok, chest, why }
  base.storage.request  { item, count }    -> base.storage.result { moved, message }
  base.storage.deposit  {}                 -> base.storage.deposited { stored, left, why }
  base.storage.craft    { recipe, count }  -> base.storage.crafting { message }

Several remotes can share one storage, each with its own chest; the
storage keeps which chest is whose by computer id.
--]]

ConfigFile = "/storageremote.cfg"
DefaultConfig = {
  server = nil,       -- id of the storage computer last used
  autoDeposit = 0,    -- seconds between deposits from the chest, 0 for off
  refresh = 60,       -- seconds between fetching the item list again
}

function loadConfig(path)
  return storage.loadConfig(path or ConfigFile, DefaultConfig)
end

function saveConfig(config, path)
  return storage.saveConfig(config, path or ConfigFile)
end

-- It searches like the storage object; apis load in name order, so
-- this one before storage, and the link is made on first use.
local Remote = {}
Remote.__index = Remote

function new(config, opts)
  opts = opts or {}
  if not getmetatable(Remote) then setmetatable(Remote, { __index = storage.Class }) end
  return setmetatable({
    config = config, server = config.server, timeout = opts.timeout or 5,
    items = {}, info = {}, names = {}, used = 0, total = 0,
    chest = nil, choices = {}, recipes = {}, label = nil, lastError = nil,
  }, Remote)
end

local counter = 0

-- Publish topic and wait for the answer with the same requestId.
-- Returns the answer and the storage computer's id, or nil and why.
function Remote:ask(topic, payload, answer, timeout)
  if not bus.open() then return nil, "no modem" end
  bus.subscribe(answer)
  counter = counter + 1
  payload.requestId = os.getComputerID() .. ":r" .. counter
  payload.server = self.server
  bus.publish(topic, payload)
  local deadline = os.clock() + (timeout or self.timeout)
  while os.clock() < deadline do
    local t, p, sender = bus.receive(math.max(0.05, deadline - os.clock()))
    if t == nil then break end -- the time is up
    if t == answer and type(p) == "table" and p.requestId == payload.requestId then return p, sender end
  end
  return nil, self.server and ("storage computer " .. self.server .. " did not answer") or "no storage computer answered"
end

-- Fetch the item list. Returns true, or false and why.
function Remote:refresh()
  local p, sender = self:ask("base.storage.list", {}, "base.storage.items")
  if not p then
    self.lastError = sender
    return false, sender
  end
  self.server, self.config.server = sender, sender
  self.label = p.label
  local items = {}
  for _, it in ipairs(p.items or {}) do
    items[it.key] = { key = it.key, name = it.name, nbt = it.nbt, displayName = it.displayName,
                      count = it.count, maxCount = it.maxCount, stacks = 0, chests = {} }
    self.info[it.key] = { displayName = it.displayName, maxCount = it.maxCount }
  end
  self.items = items
  self.used, self.total = p.used or 0, p.total or 0
  self.chest, self.choices, self.recipes = p.chest, p.choices or {}, p.recipes or {}
  self.lastError = nil
  return true
end

function Remote:index() return self.items end
function Remote:capacity() return self.used, self.total end
function Remote:inputCount() return self.chest and 1 or 0 end
function Remote:checkSpace() return nil, self.used, self.total end

-- What stops the remote working, or nil.
function Remote:problem()
  if self.lastError then
    return "Cannot reach the storage: " .. self.lastError .. ". This computer and the storage computer "
      .. "both need a wireless or ender modem, in range of each other."
  end
  if not self.chest then
    return "Pick your chest on the Settings tab: the chest on the storage network that your items "
      .. "are delivered to, such as an ender chest."
  end
  return nil
end

-- Send count of an item to this remote's chest. Returns the number
-- moved and, when short, why.
function Remote:withdraw(text, count)
  local item, why = self:find(text)
  if not item then return 0, why end
  count = storage.parseAmount(count or 1, item)
  if not count then return 0, "bad amount" end
  local p, err = self:ask("base.storage.request", { item = item.key, count = count }, "base.storage.result", 30)
  if not p then return 0, err end
  local moved = p.moved or 0
  item.count = item.count - moved
  if item.count <= 0 then self.items[item.key] = nil end
  return moved, p.message
end

-- Empty this remote's chest into storage. Returns stored, left, why.
function Remote:deposit()
  local p, err = self:ask("base.storage.deposit", {}, "base.storage.deposited", 60)
  if not p then return 0, 0, err end
  self:refresh()
  return p.stored or 0, p.left or 0, p.why
end

-- Make chest this remote's own. Returns true, or false and why.
function Remote:register(chest)
  local p, err = self:ask("base.storage.register", { chest = chest, label = os.getComputerLabel() },
    "base.storage.registered", 10)
  if not p then return false, err end
  if p.ok then self.chest = p.chest end
  return p.ok, p.why
end

-- Craft count items of a recipe at the base. Returns a message.
function Remote:craft(recipe, count)
  local p, err = self:ask("base.storage.craft", { recipe = recipe, count = count }, "base.storage.crafting", 10)
  if not p then return err end
  return p.message
end
