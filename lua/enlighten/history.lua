---@class History
---@field max number
---@field items string[]
---@field index number
local History = {}

---@param max number
---@return History
function History:new(max)
  local instance = setmetatable({}, self)
  self.__index = self
  instance.max = max
  instance.items = {}
  instance.index = 0
  return instance
end

---@param history string
function History:add(history)
  table.insert(self.items, 1, history)
  if #self.items > self.max then
    table.remove(self.items)
  end
  self.index = 0
end

---@return string|nil
function History:scroll_forward()
  if self.index < #self.items then
    self.index = self.index + 1
  end
  return self.index > 0 and self.items[self.index] or nil
end

---@return string|nil
function History:scroll_back()
  if self.index > 0 then
    self.index = self.index - 1
  end
  return self.index > 0 and self.items[self.index] or nil
end

function History:init()
  self.index = 0
end

return History
