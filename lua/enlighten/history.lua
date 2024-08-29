---@class HistoryItem
---@field messages AiMessages
---@field date string

---@class History
--- Items is a list of the current history. A history item is a list of buffer lines.
---@field items HistoryItem[]
--- The current index in the items list that is checked out. Zero is used to identify the
--- current content, not saved in history. Indexes 1+ are used to index the history items.
---@field index number
--- Temp storage of the current unsaved content while scrolling past history.
---@field current string[]
--- The curret buffer.
---@field buffer number
--- Flag for whether the current session has already been saved. This is used to
--- skip the history item at index 1 when it is a saved version of the current content.
--- This prevents scrolling a duplicate of the current content. A bit hacky.
---@field saved boolean
local History = {}

-- Only keep a max of 10 past prompts or conversations
local MAX_HISTORY = 10

---@param previous HistoryItem[]
---@return History
function History:new(previous)
  self.__index = self

  self.items = previous
  self.index = 0

  return self
end

function History:is_current()
  return self.index == 0
end

--- Update the history item with the buffer content. Create a new history item
--- if one has not been created yet.
---@param messages AiMessages | string
---@return HistoryItem[]
function History:update(messages)
  if type(messages) == "string" then
    messages = { { role = "user", content = messages } }
  end

  ---@type HistoryItem
  local item = {
    messages = messages,
    date = tostring(os.date("%Y-%m-%d")),
  }

  if self.index == 0 then
    table.insert(self.items, 1, item)
    if #self.items > MAX_HISTORY then
      table.remove(self.items)
    end
    self.saved = true
  else
    self.items[self.index] = item
  end

  return self.items
end

--- Scroll back through the history items.
---@return HistoryItem?
function History:scroll_back()
  local old_index = self.index

  if self.index < #self.items then
    self.index = self.index + 1
  end

  if old_index == self.index then
    return
  end

  if self.index == 0 then
    return nil
  else
    return self.items[self.index]
  end
end

--- Scroll forward through the history items.
---@return HistoryItem?
function History:scroll_forward()
  local old_index = self.index

  if self.index > 0 then
    self.index = self.index - 1
  end

  if old_index == self.index then
    return nil
  end

  if self.index == 0 then
    return
  else
    return self.items[self.index]
  end
end

return History
