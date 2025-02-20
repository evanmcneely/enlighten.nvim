-- TODO Persist history across sessions.
-- The current implementation will need to be heavily refactored and future-proofed.
-- History should be initialized from a file somewhere when the plugin is setup. Updates
-- should be saved to the file.

---@class HistoryItem
--- Conversation data from the past session.
---@field messages AiMessages
--- The date the session was saved to history.
---@field date string

--- A class for managing a history of past sessions with the a plugin feature for a current active session.
---@class History
--- A list of past sessions with a particular plugin feature, cumulatively reperesting the history
--- of the user using that feature.
---@field items HistoryItem[]
--- The current index in the items list that is checked out. Zero is used to identify the
--- current content, not saved in history (yet). Indexes 1+ are used to index the history items.
---@field index number
--- Temp storage of the current unsaved content while scrolling past history. This is just a
--- list of buffer lines.
---@field current string[]
--- Flag for whether the current session has already been saved to the list of history items.
--- This is used to skip the history item at index 1 when it is a saved version of the current content.
--- This prevents scrolling a duplicate of the current content. A bit hacky but works well.
---@field saved boolean
local History = {}
History.__index = History

-- Only keep a max of 10 past prompts or conversations
local MAX_HISTORY = 10

---@param previous HistoryItem[]
---@return History
function History:new(previous)
  local history = setmetatable({}, self)
  history.items = previous
  history.index = 0

  return history
end

function History:is_current()
  return self.index == 0
end

--- Update history with the buffer content. Create a new history item
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

--- Scroll back through session history.
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

--- Scroll forward through session history.
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
