---@class History
---@field max number
---@field items string[][]
---@field index number
---@field current string[]
---@field buffer number
local History = {}

---@param buffer number
---@param max number
---@param previous string[][]
---@return History
function History:new(buffer, max, previous)
  local instance = setmetatable({}, self)
  self.__index = self
  instance.buffer = buffer
  instance.items = previous
  instance.index = 0
  instance.max = max
  instance.current = {}
  return instance
end

function History:update()
  local current = vim.api.nvim_buf_get_lines(self.buffer, 0, -1, false)

  if self.index == 0 then
    table.insert(self.items, 1, current)
    if #self.items > self.max then
      table.remove(self.items)
    end
    self.current = {}
  else
    self.items[self.index] = current
  end

  return self.items
end

function History:scroll_back()
  local old_index = self.index

  if self.index < #self.items then
    self.index = self.index + 1
  end

  if old_index == self.index then
    return
  end

  if self.index == 1 and old_index == 0 then
    self.current = vim.api.nvim_buf_get_lines(self.buffer, 0, -1, false)
    vim.api.nvim_buf_set_lines(self.buffer, 0, -1, false, self.items[self.index])
  elseif self.index > 1 then
    vim.api.nvim_buf_set_lines(self.buffer, 0, -1, false, self.items[self.index])
  end

  self:highlight_lines()
end

function History:scroll_forward()
  local old_index = self.index

  if self.index > 0 then
    self.index = self.index - 1
  end

  if old_index == self.index then
    return
  end

  if self.index == 0 then
    vim.api.nvim_buf_set_lines(self.buffer, 0, -1, false, self.current)
  else
    vim.api.nvim_buf_set_lines(self.buffer, 0, -1, false, self.items[self.index])
  end

  self:highlight_lines()
end

function History:highlight_lines()
  local lines = vim.api.nvim_buf_get_lines(self.buffer, 0, -1, false)

  for i, line in ipairs(lines) do
    if line:match("^>>>") then
      vim.api.nvim_buf_add_highlight(self.buffer, -1, "Function", i - 1, 0, -1)
    end
  end
end

return History
