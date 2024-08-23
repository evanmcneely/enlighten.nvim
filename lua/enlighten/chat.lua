local api = vim.api
local ai = require("enlighten/ai")
local augroup = require("enlighten/autocmd")
local buffer = require("enlighten/buffer")
local Writer = require("enlighten/writer/stream")
local Logger = require("enlighten/logger")
local History = require("enlighten/history")

---@class EnlightenChat
---@field id string
---@field settings EnlightenChatSettings
---@field aiConfig EnlightenAiProviderConfig
--- The id of the chat buffer
---@field chat_buf number
--- The id of the window that hosts the chat buffer
---@field chat_win number
--- The id of the buffer that the cursor was when the chat was opened
---@field target_buf number
--- A class that helps manage history of past conversations.
---@field history History
--- A class responsible for writing text to a buffer. This feature uses the
--- streaming writer to stream AI completions into the chat buffer.
---@field writer Writer
--- A list of ids of all autocommands that have been created for this feature.
---@field autocommands number[]
---@field messages AiMessages
---@field messages_nsid number
local EnlightenChat = {}
EnlightenChat.__index = EnlightenChat

local USER = " > User"
local ASSISTANT = " > Assistant"
local USER_SIGN = " "
local ASSISTANT_SIGN = "ﮧ "

---@param tbl string[]
local function trim_empty_lines(tbl)
  while tbl[1] == "" do
    table.remove(tbl, 1)
  end
  while tbl[#tbl] == "" do
    table.remove(tbl)
  end

  return tbl
end

--- Create the chat buffer and popup window
---@param id string
---@param settings EnlightenChatSettings
---@return { bufnr: number, win_id: number }
local function create_window(id, settings)
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
  api.nvim_set_option_value("cursorline", false, { win = win })
  api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  api.nvim_buf_set_name(buf, "enlighten-chat" .. id)
  api.nvim_set_option_value("filetype", "enlighten", { buf = buf })
  api.nvim_set_option_value("wrap", true, { win = win })

  return {
    bufnr = buf,
    win_id = win,
  }
end

--- Set all keymaps for the chat buffer needed for user interactions. This
--- is the primary UX for the chat feature.
---
--- - q        : close the prompt buffer
--- - <cr>     : submit prompt for generation
--- - <C-o>    : scroll back in history
--- - <C-i>    : scroll forward in history
--- - <C-x>    : stop AI generation
---@param context EnlightenChat
local function set_keymaps(context)
  api.nvim_buf_set_keymap(context.chat_buf, "n", "<CR>", "", {
    noremap = true,
    silent = true,
    callback = function()
      context:submit()
    end,
  })
  api.nvim_buf_set_keymap(context.chat_buf, "n", "q", "", {
    noremap = true,
    silent = true,
    callback = function()
      context:close()
    end,
  })
  api.nvim_buf_set_keymap(context.chat_buf, "n", "<C-o>", "", {
    noremap = true,
    silent = true,
    callback = function()
      context:scroll_back()
    end,
  })
  api.nvim_buf_set_keymap(context.chat_buf, "n", "<C-i>", "", {
    noremap = true,
    silent = true,
    callback = function()
      context:scroll_forward()
    end,
  })
  api.nvim_buf_set_keymap(context.chat_buf, "n", "<C-x>", "", {
    noremap = true,
    silent = true,
    callback = function()
      context:stop()
    end,
  })
end

--- Insert the content at the end of the buffer with the specified highlight.
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

--- Set all autocommands that the feature is dependant on
---@param context EnlightenChat
---@return number[]
local function set_autocmds(context)
  local autocmd_ids = {
    -- When the prompt window is closed with :q -> cleanup
    api.nvim_create_autocmd("BufHidden", {
      group = augroup,
      buffer = context.chat_buf,
      callback = function()
        context:stop()
        context:cleanup()
      end,
    }),
  }

  context.autocommands = autocmd_ids
  return autocmd_ids
end

--- Clean up all autocommands that have been created
---@param context EnlightenChat
local function delete_autocmds(context)
  for _, id in ipairs(context.autocommands or {}) do
    local status, err = pcall(api.nvim_del_autocmd, id)
    if not status then
      Logger:log("delete_autocmds - error", { id = context.id, autocmd_id = id, error = err })
    end
  end
end
--- Initial gateway into the chat feature. Initialize all data, windows, keymaps
--- and autocommands that the feature depend on.
---@param aiConfig EnlightenAiProviderConfig
---@param settings EnlightenChatSettings
---@param history string[][]
---@return EnlightenChat
function EnlightenChat:new(aiConfig, settings, history)
  local id = tostring(math.random(10000))
  local buf = api.nvim_get_current_buf()
  local range = buffer.get_range()

  --- Getting the current snippet must occur before we create the buffers
  ---@type string[] | nil
  local snippet
  if buffer.is_visual_mode() then
    snippet = buffer.get_lines(buf, range.row_start, range.row_end + 1)
  end

  local chat_win = create_window(id, settings)

  local context = setmetatable({}, self)
  context.id = id
  context.messages_nsid = api.nvim_create_namespace("EnlightenChatMessages")
  context.aiConfig = aiConfig
  context.settings = settings
  context.chat_buf = chat_win.bufnr
  context.chat_win = chat_win.win_id
  context.target_buf = buf
  context.history = History:new(history)
  context.writer = Writer:new(chat_win.win_id, chat_win.bufnr, function()
    context:_add_user()
    -- context.history:update(context:_build_messages())
  end)

  set_keymaps(context)
  set_autocmds(context)

  context:_add_user(snippet)
  api.nvim_command("startinsert")

  Logger:log(
    "chat:new",
    { id = id, chat_buf = chat_win.bufnr, chat_win = chat_win.win_id, target_buf = buf }
  )

  return context
end

--- Close the chat buffer. Any content that is currently being writen to the
--- buffer will be lost.
function EnlightenChat:close()
  if self.writer.active then
    self.writer:stop()
  end

  if api.nvim_win_is_valid(self.chat_win) then
    api.nvim_win_close(self.chat_win, true)
  end

  if api.nvim_buf_is_valid(self.chat_buf) then
    api.nvim_buf_delete(self.chat_buf, { force = true })
  end

  Logger:log("chat:close", { id = self.id })
end

function EnlightenChat:cleanup()
  delete_autocmds(self)
end

--- Submit the user question for a response.
function EnlightenChat:submit()
  if
    api.nvim_buf_is_valid(self.chat_buf)
    and api.nvim_win_is_valid(self.chat_win)
    and api.nvim_buf_is_valid(self.target_buf)
  then
    if self.writer.active then
      return
    end

    self.writer:reset()

    local prompt = self:_build_messages()

    self:_add_assistant()

    local opts = {
      provider = self.aiConfig.provider,
      model = self.aiConfig.model,
      tokens = self.aiConfig.tokens,
      timeout = self.aiConfig.timeout,
      temperature = self.aiConfig.temperature,
      feature = "chat",
      stream = true,
    }
    ai.complete(prompt, self.writer, opts)
  end
end

--- Format the prompt for generating a response. The conversation is not broken up
--- into user/assistant roles when passed to the AI provider for completion.
---@return AiMessages
function EnlightenChat:_build_messages()
  local message_marks =
    api.nvim_buf_get_extmarks(self.chat_buf, self.messages_nsid, 0, -1, { details = true })
  local messages = {} ---@type AiMessages

  for i = 1, #message_marks do
    local mark = message_marks[i]
    local next_mark = message_marks[i + 1]
    local role = mark[4].sign_text == USER_SIGN and "user" or "assistant"
    local start = mark[1]
    local finish = next_mark and next_mark[1] - 1 or -1
    local content =
      table.concat(trim_empty_lines(buffer.get_lines(self.chat_buf, start, finish)), "\n")
    table.insert(messages, { role = role, content = content })
  end

  return messages
end

--- Add the "User" role to the buffer and prepopulate the prompt
--- with the provided snippet (if any).
---@param snippet? string[]
function EnlightenChat:_add_user(snippet)
  insert_line(self.chat_buf, "")
  insert_line(self.chat_buf, "")

  local count = api.nvim_buf_line_count(self.chat_buf)
  api.nvim_buf_set_extmark(self.chat_buf, self.messages_nsid, count - 1, 0, {
    virt_text = { { USER, "EnlightenChatRoleUser" } },
    sign_hl_group = "EnlightenChatRoleSign",
    line_hl_group = "EnlightenChatRoleUser",
    virt_text_pos = "overlay",
    sign_text = USER_SIGN,
  })

  insert_line(self.chat_buf, "")

  if snippet then
    local file_extension = vim.fn.expand("#" .. self.target_buf .. ":e")
    if file_extension ~= "" then
      insert_line(self.chat_buf, "```" .. file_extension)
    end
    for _, l in pairs(snippet) do
      insert_line(self.chat_buf, l)
    end
    insert_line(self.chat_buf, "")
    if file_extension ~= "" then
      insert_line(self.chat_buf, "```")
    end
  end
  insert_line(self.chat_buf, "")

  count = api.nvim_buf_line_count(self.chat_buf)
  vim.api.nvim_win_set_cursor(self.chat_win, { count, 0 })
  vim.cmd("startinsert")
end

--- Add the "Assistant" role to the buffer.
function EnlightenChat:_add_assistant()
  insert_line(self.chat_buf, "")
  insert_line(self.chat_buf, "")

  local count = api.nvim_buf_line_count(self.chat_buf)
  api.nvim_buf_set_extmark(self.chat_buf, self.messages_nsid, count - 1, 0, {
    virt_text = { { ASSISTANT, "EnlightenChatRoleAssistant" } },
    sign_hl_group = "EnlightenChatRoleSign",
    line_hl_group = "EnlightenChatRoleAssistant",
    virt_text_pos = "overlay",
    sign_text = ASSISTANT_SIGN,
  })

  insert_line(self.chat_buf, "")
  insert_line(self.chat_buf, "")
end

-- Highlight the chat user/assistant markers
---@param data HistoryItem
function EnlightenChat:_write_messages(data)
  -- local lines = vim.api.nvim_buf_get_lines(self.chat_buf, 0, -1, false)
  -- for i, line in ipairs(lines) do
  --   if line:match("^" .. ROLE_PREFIX) then
  --     vim.api.nvim_buf_add_highlight(self.chat_buf, -1, "EnlightenChatRole", i - 1, 0, -1)
  --   end
  -- end
end

--- If text content is currently being written to the buffer... stop doing that
function EnlightenChat:stop()
  if self.writer.active then
    self.writer:stop()
    self:_add_user()
  end
end

--- Scroll back in history
function EnlightenChat:scroll_back()
  if not self.writer.active then
    local data = self.history:scroll_back()
    if data and data == -1 then
      -- use current
    elseif data then
      -- self:_write_messages(data)
    end
  end
end

--- Scroll forward in history
function EnlightenChat:scroll_forward()
  if not self.writer.active then
    local data = self.history:scroll_forward()
    if data and data == -1 then
      -- use current
    elseif data then
      -- self:_write_messages(data)
    end
  end
end

return EnlightenChat
