---@class History
--- Items is a list of the current history. A history item is a list of buffer lines.
---@field items string[][]
--- The current index in the items list that is checked out. Zero is used to identify the
--- current prompt, not saved in history. Indexes 1+ are used to index the history items.
---@field index number
--- Temp storage of the current unsaved content while scrolling past history.
---@field current string[]
--- The curret buffer.
---@field buffer number
--- Flag for whether the current session has already been saved. This is used to
--- skip the history item and index 1, to prevent scrolling a duplicate of the current content
--- that has already been saved. This is a bit hacky.
---@field saved boolean
local History = {}

-- Only keep a max of 10 past prompts or conversations
local MAX_HISTORY = 10

---@param buffer number
---@param previous string[][]
---@return History
function History:new(buffer, previous)
  self.__index = self

  self.buffer = buffer
  self.items = previous
  self.index = 0
  self.current = {}
  self.saved = false

  return self
end

---@return string[][]
function History:update()
  local current = vim.api.nvim_buf_get_lines(self.buffer, 0, -1, false)

  if self.index == 0 then
    if self.saved then
      self.items[1] = current
    else
      table.insert(self.items, 1, current)
      if #self.items > MAX_HISTORY then
        table.remove(self.items)
      end
      self.saved = true
    end
  else
    self.items[self.index] = current
  end

  return self.items
end

function History:scroll_back()
  local old_index = self.index

  if self.index < #self.items then
    self.index = self.index + 1
    if self.saved and self.index == 1 then
      self.index = #self.items == 1 and 0 or 2
    end
  end

  if old_index == self.index then
    return
  end

  local is_first_entry = self.index == 1 and old_index == 0
  local is_second_entry_with_save = self.saved and self.index == 2 and old_index == 0

  if is_first_entry or is_second_entry_with_save then
    self.current = vim.api.nvim_buf_get_lines(self.buffer, 0, -1, false)
    vim.api.nvim_buf_set_lines(self.buffer, 0, -1, false, self.items[self.index])
  elseif self.index > 1 then
    vim.api.nvim_buf_set_lines(self.buffer, 0, -1, false, self.items[self.index])
  end

  self:_highlight_lines()
end

function History:scroll_forward()
  local old_index = self.index

  if self.index > 0 then
    self.index = self.index - 1
    if self.saved and self.index == 1 then
      self.index = 0
    end
  end

  if old_index == self.index then
    return
  end

  if self.index == 0 then
    vim.api.nvim_buf_set_lines(self.buffer, 0, -1, false, self.current)
  else
    vim.api.nvim_buf_set_lines(self.buffer, 0, -1, false, self.items[self.index])
  end

  self:_highlight_lines()
end

function History:_highlight_lines()
  local lines = vim.api.nvim_buf_get_lines(self.buffer, 0, -1, false)

  -- Highlight the chat user/assistant markers after the content is set
  for i, line in ipairs(lines) do
    if line:match("^>>>") then
      vim.api.nvim_buf_add_highlight(self.buffer, -1, "Function", i - 1, 0, -1)
    end
  end
end

return History
