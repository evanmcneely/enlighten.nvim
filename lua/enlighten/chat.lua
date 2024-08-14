local api = vim.api
local buffer = require("enlighten/buffer")
local Writer = require("enlighten/writer/stream")
local Logger = require("enlighten/logger")
local History = require("enlighten/history")

---@class EnlightenChat
---@field settings EnlightenChatSettings
---@field chat_buf number
---@field chat_win number
---@field target_buf number
---@field target_range Range
---@field history History
local EnlightenChat = {}

-- Initial gateway into the chat feature. Initialize all data, windows, keymaps
-- and autocommands that the feature depend on.
---@param ai AI
---@param settings EnlightenChatSettings
---@param history string[][]
---@return EnlightenChat
function EnlightenChat:new(ai, settings, history)
  self.__index = self

  local buf = api.nvim_get_current_buf()
  local range = buffer.get_range()

  -- Getting the current snippet must occur before we create the buffers
  ---@type string[]
  local snippet
  if buffer.is_visual_mode() then
    snippet = buffer.get_lines(buf, range.row_start, range.row_end + 1)
  end

  local chat_win = self._create_chat_window(settings)

  self.ai = ai
  self.settings = settings
  self.chat_buf = chat_win.bufnr
  self.chat_win = chat_win.win_id
  self.target_buf = buf
  self.history = History:new(chat_win.bufnr, 5, history)

  self:_set_chat_keymaps()
  self:_add_user(snippet)

  vim.cmd("startinsert")

  return self
end

-- Close the chat buffer. Any generated content will be LOST!
function EnlightenChat:close()
  if api.nvim_win_is_valid(self.chat_win) then
    Logger:log("chat:close - closing window", { chat_win = self.chat_win })
    api.nvim_win_close(self.chat_win, true)
  end

  if api.nvim_buf_is_valid(self.chat_buf) then
    Logger:log("chat:close - deleting buffer", { chat_buf = self.chat_buf })
    api.nvim_buf_delete(self.chat_buf, { force = true })
  end
end

-- Focus the chat buffer.
function EnlightenChat:focus()
  if api.nvim_buf_is_valid(self.chat_buf) and api.nvim_win_is_valid(self.chat_win) then
    Logger:log("chat:focus - focusing", { buf = self.chat_buf, win = self.chat_win })
    api.nvim_set_current_win(self.chat_win)
    api.nvim_win_set_buf(self.chat_win, self.chat_buf)
  end
end

-- Submit the user question for a response. The user and assistant markers
-- will also be added to the buffer in the appropriate places.
function EnlightenChat:submit()
  if
    api.nvim_buf_is_valid(self.chat_buf)
    and api.nvim_win_is_valid(self.chat_win)
    and api.nvim_buf_is_valid(self.target_buf)
  then
    self:_add_assistant()

    local function on_complete()
      self:_add_user()
      self.history:update()
    end

    local prompt = self:_build_prompt()
    local count = api.nvim_buf_line_count(self.chat_buf)
    local writer = Writer:new(self.chat_win, self.chat_buf, { count, 0 }, on_complete)
    self.ai:chat(prompt, writer)
  end
end

-- Create the chat buffer and popup window
---@param settings EnlightenChatSettings
---@return { bufnr: number, win_id: number }
function EnlightenChat._create_chat_window(settings)
  Logger:log("prompt:_create_chat_window - creating window")

  if settings.split == "left" then
    vim.cmd("leftabove vsplit")
  else
    vim.cmd("vsplit")
  end

  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_width(win, settings.width)

  api.nvim_set_option_value("number", false, { win = win })
  api.nvim_set_option_value("signcolumn", "no", { win = win })
  api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  api.nvim_buf_set_name(buf, "enlighten-chat")
  api.nvim_set_option_value("filetype", "enlighten", { buf = buf })
  api.nvim_set_option_value("wrap", true, { win = win })

  Logger:log("chat:_create_chat_window - window and buffer", { win = win, buf = buf })

  return {
    bufnr = buf,
    win_id = win,
  }
end

-- Set all keymaps for the chat buffer needed for user interactions. This
-- is the primary UX for the prompt feature.
--
-- - q        : close the prompt buffer
-- - <cr>     : submit prompt for generation
-- - <C-o>    : scroll back in history
-- - <C-i>    : scroll forward in history
function EnlightenChat:_set_chat_keymaps()
  api.nvim_buf_set_keymap(
    self.chat_buf,
    "n",
    "<CR>",
    "<Cmd>lua require('enlighten').chat:submit()<CR>",
    {}
  )
  api.nvim_buf_set_keymap(
    self.chat_buf,
    "n",
    "q",
    "<Cmd>lua require('enlighten'):close_chat()<CR>",
    {}
  )
  api.nvim_buf_set_keymap(
    self.chat_buf,
    "n",
    "<C-o>",
    "<Cmd>lua require('enlighten').chat:scroll_back()<CR>",
    {}
  )
  api.nvim_buf_set_keymap(
    self.chat_buf,
    "n",
    "<C-i>",
    "<Cmd>lua require('enlighten').chat:scroll_forward()<CR>",
    {}
  )
end

-- Format the prompt for generating a response. The conversation is not broken up
-- into user/assistant roles when passed to the AI provider for completion. Instead the buffer,
-- with user/assistant markers, donote the conversation history.
---@return string
function EnlightenChat:_build_prompt()
  local prompt = buffer.get_content(self.chat_buf)
  return "Continue this conversation. Be concise. Most recent message is at the bottom...\n\n"
    .. prompt
end

-- Insert the content at the end of the buffer with the specified highlight.
---@param buf number
---@param content string
---@param highlight? string
local function insert_line(buf, content, highlight)
  api.nvim_buf_set_lines(buf, -1, -1, true, { content })
  if highlight ~= nil then
    local line = api.nvim_buf_line_count(buf)
    api.nvim_buf_add_highlight(buf, -1, highlight, line - 1, 0, -1)
  end
end

-- Add the "User" role to the buffer and prepopulate the prompt
-- with the provided snippet (if any).
---@param snippet? string[]
function EnlightenChat:_add_user(snippet)
  local count = api.nvim_buf_line_count(self.chat_buf)

  if count == 1 then
    insert_line(self.chat_buf, ">>> Developer", "Function")
    insert_line(self.chat_buf, "")
    if snippet ~= nil then
      for _, l in pairs(snippet) do
        insert_line(self.chat_buf, l)
      end
      insert_line(self.chat_buf, "")
    end
    insert_line(self.chat_buf, "")
  else
    insert_line(self.chat_buf, "")
    insert_line(self.chat_buf, ">>> Developer", "Function")
    insert_line(self.chat_buf, "")
    insert_line(self.chat_buf, "")
  end

  count = api.nvim_buf_line_count(self.chat_buf)
  vim.api.nvim_win_set_cursor(self.chat_win, { count, 0 })
  vim.cmd("startinsert")
end

-- Add the "Assistant" role to the buffer.
function EnlightenChat:_add_assistant()
  insert_line(self.chat_buf, "")
  insert_line(self.chat_buf, ">>> Assistant", "Function")
  insert_line(self.chat_buf, "")
  insert_line(self.chat_buf, "")
end

-- Scroll back in history
function EnlightenChat:scroll_back()
  self.history:scroll_back()
end

-- Scroll forward in history
function EnlightenChat:scroll_forward()
  self.history:scroll_forward()
end

return EnlightenChat
