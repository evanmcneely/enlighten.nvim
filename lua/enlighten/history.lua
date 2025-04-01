local Logger = require("enlighten.logger")

---@alias Files { path: string, content: string[] }[]
---@alias FileIndex table<number, Files>

---@class HistoryItem
--- Conversation data from the past session.
---@field messages AiMessages
--- The date the session was saved to history.
---@field date string
--- An index of files added to messages. Each key is a 1-based index of file information
--- that map to the index of a message in messages.
---@field files? FileIndex

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
--- The file path to persist history for this feature.
---@field file_path string
local History = {}
History.__index = History

-- Maximum history entries to store.
local MAX_HISTORY = 25

--- Helper to get the base directory for plugin data
---@return string
local function get_base_directory()
  local base = vim.fn.stdpath("data") .. "/enlighten.nvim/"
  -- Ensure the directory exists. "p" flag creates intermediate dirs.
  vim.fn.mkdir(base, "p")
  return base
end

--- Helper to determine the current project name. If the current directory is in a
--- Git repo, returns the repository's name. Otherwise, returns "default"
---@return string
local function get_project_name()
  local project_name = "default"
  -- Try getting the git top level; suppress error messages
  local git_top = vim.fn.system("git rev-parse --show-toplevel 2> /dev/null")
  if vim.v.shell_error == 0 then
    -- trim any trailing whitespace/newlines
    git_top = git_top:gsub("%s+", "")
    project_name = vim.fn.fnamemodify(git_top, ":t")
  end
  return project_name
end

--- Generates a file path based on the given feature name.
--- The file is saved under a sub-directory per project.
---@param feature string
---@return string
local function get_history_file(feature)
  local project = get_project_name()
  local project_dir = get_base_directory() .. project .. "/"
  -- Ensure the project directory exists.
  vim.fn.mkdir(project_dir, "p")
  return project_dir .. feature .. ".json"
end

--- Writes the given history items as JSON to the specified file.
---@param file_path string
---@param items HistoryItem[]
local function save_history_to_file(file_path, items)
  local file = io.open(file_path, "w")
  if file then
    local data = vim.fn.json_encode(items)
    file:write(data)
    file:close()
  else
    Logger:log("save_history_to_file - failed", { file_path = file_path })
  end
end

--- Loads history items from the specified file. Returns an empty table if the file does not exist.
---@param file_path string
---@return HistoryItem[]
local function load_history_from_file(file_path)
  local file = io.open(file_path, "r")
  if not file then
    return {}
  end
  local content = file:read("*a")
  file:close()
  if #content == 0 then
    return {}
  end
  local ok, items = pcall(vim.fn.json_decode, content)
  if not ok then
    Logger:log("load_history_from_file - failed", { file_path = file_path })
    return {}
  end
  return items
end

--- Constructor for the History class.
--- Pass the feature name to have separate history persisted per feature under /enlighten.nvim/<feature>.json.
---@param feature string The feature identifier for which to load/persist history.
---@return History
function History:new(feature)
  assert(type(feature) == "string" and #feature > 0, "feature must be a non-empty string")

  local history = setmetatable({}, self)
  history.file_path = get_history_file(feature)
  -- Load persisted history for the given feature.
  history.items = load_history_from_file(history.file_path)
  history.index = 0
  history.current = {}
  history.saved = false
  return history
end

--- Checks if the current content is unsaved.
---@return boolean True if current session is unsaved.
function History:is_current()
  return self.index == 0
end

--- Updates history with new messages.
--- If messages is a string, it will be wrapped as an AI message.
---@param messages AiMessages|string
---@param files Files
---@return HistoryItem[] Updated list of HistoryItem objects.
function History:update(messages, files)
  if type(messages) == "string" then
    messages = { { role = "user", content = messages } }
  end

  ---@type HistoryItem
  local item = {
    messages = messages,
    date = tostring(os.date("%Y-%m-%d")),
    files = files
  }

  if self.index == 0 then
    table.insert(self.items, 1, item)
    if #self.items > MAX_HISTORY then
      table.remove(self.items) -- Remove the oldest history item.
    end
    self.saved = true
  else
    self.items[self.index] = item
  end

  -- Persist history to file.
  save_history_to_file(self.file_path, self.items)
  return self.items
end

--- Sets the history items, overriding any existing history.
--- Used in tests to set initial state of history.
---@param new_items HistoryItem[] the new list of history items
function History:set(new_items)
  self.items = new_items
  self.index = 0
  save_history_to_file(self.file_path, self.items)
end

--- Scrolls back through session history.
---@return HistoryItem|nil Returns the history item or nil if already at the oldest item.
function History:scroll_back()
  local old_index = self.index
  if self.index < #self.items then
    self.index = self.index + 1
  end

  if old_index == self.index then
    return nil
  end

  if self.index == 0 then
    return nil
  end

  return self.items[self.index]
end

--- Scrolls forward through session history.
---@return HistoryItem|nil Returns the history item or nil if already at the current session.
function History:scroll_forward()
  local old_index = self.index
  if self.index > 0 then
    self.index = self.index - 1
  end

  if old_index == self.index then
    return nil
  end

  if self.index == 0 then
    return nil
  else
    return self.items[self.index]
  end
end

return History
