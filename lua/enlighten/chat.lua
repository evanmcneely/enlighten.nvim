local api = vim.api
local ai = require("enlighten.ai")
local augroup = require("enlighten.autocmd")
local buffer = require("enlighten.buffer")
local StreamWriter = require("enlighten.writer.stream")
local SelfWriter = require("enlighten.writer.self")
local DiffWriter = require("enlighten.writer.diff")
local Logger = require("enlighten.logger")
local History = require("enlighten.history")
local utils = require("enlighten.utils")
local diff_hl = require("enlighten.diff.highlights")

---@class EnlightenChat
--- Settings injected into this class from the plugin config
---@field settings EnlightenChatSettings
--- AI config injected into this class from the plugin config
---@field aiConfig EnlightenAiProviderConfig
--- Unique 4 diget number to this chat session
---@field id string
--- The id of the chat buffer
---@field chat_buf number
--- The id of the window that hosts the chat buffer
---@field chat_win number
--- The id of the title popup buffer
---@field title_buf number
--- The id of the window that hosts the title buffer
---@field title_win number
--- The id of the buffer that the cursor was in when the chat was opened
---@field target_buf number
--- A class that helps manage history of past conversations.
---@field history History
--- A class responsible for writing text to a buffer. This feature uses the
--- streaming writer to stream AI completions into the chat buffer.
---@field writer StreamWriter
--- A list of ids of all autocommands that have been created for this chat session.
---@field autocommands number[]
--- A list of the current chat sessions messages. Used for scrolling chat history.
---@field messages AiMessages
--- The namespace id of the chat role highlights
---@field messages_nsid number
--- A flag for whether or not the user has generated completions this session.
---@field has_generated boolean
local EnlightenChat = {}
EnlightenChat.__index = EnlightenChat

local TITLE = "💬 Enlighten Chat"
local USER = " User"
local ASSISTANT = " Assistant"
local USER_SIGN = " "
local ASSISTANT_SIGN = "󰚩 " -- must be different from user sign

--- Create the chat buffer and popup window
---@param id string
---@param settings EnlightenChatSettings
---@return { bufnr: number, win_id: number, title_win: number, title_buf: number }
local function create_window(id, settings)
  if settings.split == "left" then
    vim.cmd("leftabove vsplit")
  else
    vim.cmd("vsplit")
  end

  -- Chat window and buffer
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

  -- Title window and buffer, positioned in a popup at the top of the window
  local title_buf = api.nvim_create_buf(false, true)
  local title_win = api.nvim_open_win(title_buf, false, {
    relative = "win",
    win = win,
    width = settings.width,
    height = 1,
    row = 0,
    col = 0,
    style = "minimal",
    focusable = false,
  })

  api.nvim_set_option_value("modifiable", false, { buf = title_buf })

  local title_ns = api.nvim_create_namespace("ChatTitle")
  api.nvim_buf_set_extmark(title_buf, title_ns, 0, 0, {
    virt_text = { { TITLE, "Function" } },
    virt_text_pos = "overlay",
    -- ensure that the value of is always an even, whole number
    virt_text_win_col = math.floor(((settings.width - #TITLE - 1) / 2) / 2) * 2,
  })

  return {
    bufnr = buf,
    win_id = win,
    title_win = title_win,
    title_buf = title_buf,
  }
end

--- Set all keymaps for the chat buffer needed for user interactions. This
--- is the primary UX for the chat feature.
--- - q        : close the prompt buffer
--- - <cr>     : submit prompt for generation
--- - <C-cr>   : write to buffer with context from chat
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
  api.nvim_buf_set_keymap(context.chat_buf, "n", "<C-CR>", "", {
    noremap = true,
    silent = true,
    callback = function()
      context:write_to_buffer()
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

---@param context EnlightenChat
---@return EnlightenMention[]
local function get_directives(context)
  return {
    {
      details = "Update buffer from chat context",
      description = "Update buffer from chat context",
      command = "edit",
      callback = function()
        context:write_to_buffer()
      end,
    },
  }
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
        context:_close_title_win()
      end,
    }),

    -- TODO add @mentions
    -- Add completion sources
    -- api.nvim_create_autocmd("InsertEnter", {
    --   group = augroup,
    --   buffer = context.chat_buf,
    --   -- once = true,
    --   desc = "Setup the completion of helpers in the input buffer",
    --   callback = function()
    --     local has_cmp, cmp = pcall(require, "cmp")
    --     if has_cmp then
    --       cmp.register_source(
    --         "enlighten_commands",
    --         require("enlighten.cmp").new(get_directives(context), context.chat_buf)
    --       )
    --       cmp.setup.buffer({
    --         enabled = true,
    --         sources = {
    --           { name = "enlighten_commands" },
    --         },
    --       })
    --     end
    --   end,
    -- }),
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
---@return EnlightenChat
function EnlightenChat:new(aiConfig, settings)
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
  context.title_win = chat_win.title_win
  context.title_buf = chat_win.title_buf
  context.target_buf = buf
  context.history = History:new("chat")
  context.has_generated = false
  context.writer = StreamWriter:new(chat_win.win_id, chat_win.bufnr, function()
    context.has_generated = true
    context:_add_user()
    context.messages = context:_build_messages()
    vim.cmd("startinsert")
  end)

  set_keymaps(context)
  set_autocmds(context)

  context:_add_user(snippet)
  api.nvim_command("startinsert")

  context.messages = context:_build_messages()

  Logger:log(
    "chat:new",
    { id = id, chat_buf = chat_win.bufnr, chat_win = chat_win.win_id, target_buf = buf }
  )

  return context
end

function EnlightenChat:close()
  if self.writer.active then
    self.writer:stop()
  end

  if self.has_generated then
    self.history:update(self.messages)
  end

  self:_close_chat_win()
  self:_close_title_win()

  Logger:log("chat:close", { id = self.id })
end

function EnlightenChat:_close_chat_win()
  if api.nvim_win_is_valid(self.chat_win) then
    api.nvim_win_close(self.chat_win, true)
  end

  if api.nvim_buf_is_valid(self.chat_buf) then
    api.nvim_buf_delete(self.chat_buf, { force = true })
  end
end

function EnlightenChat:_close_title_win()
  if api.nvim_win_is_valid(self.title_win) then
    api.nvim_win_close(self.title_win, true)
  end

  if api.nvim_buf_is_valid(self.title_buf) then
    api.nvim_buf_delete(self.title_buf, { force = true })
  end
end

function EnlightenChat:cleanup()
  delete_autocmds(self)
end

--- Submit the user question for a response.
function EnlightenChat:submit()
  if api.nvim_buf_is_valid(self.chat_buf) and api.nvim_win_is_valid(self.chat_win) then
    if self.writer.active then
      return
    end

    self.writer:reset()
    local messages = self:_build_messages()
    self.messages = messages

    Logger:log("chat:submit - messages", messages)

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
    ai.complete(messages, self.writer, opts)
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
    local start = mark[2] + 1
    local finish = next_mark and next_mark[2] - 1 or api.nvim_buf_line_count(self.chat_buf)
    local content =
      table.concat(utils.trim_empty_lines(buffer.get_lines(self.chat_buf, start, finish)), "\n")
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
    -- Remove extmark when deleted
    invalidate = true,
    undo_restore = false,
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
    -- Remove extmark when deleted
    invalidate = true,
    undo_restore = false,
  })

  insert_line(self.chat_buf, "")
  insert_line(self.chat_buf, "")
end

-- Highlight the chat user/assistant markers
---@param messages AiMessages
function EnlightenChat:_write_messages(messages)
  -- Clear buffer content
  api.nvim_buf_clear_namespace(self.chat_buf, self.messages_nsid, 0, -1)
  api.nvim_buf_set_lines(self.chat_buf, 0, -1, false, {})

  -- Then write the content from messages
  for _, message in pairs(messages) do
    if message.role == "user" then
      self:_add_user()
    else
      self:_add_assistant()
    end

    api.nvim_buf_set_lines(self.chat_buf, -1, -1, false, vim.split(message.content, "\n"))
  end
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
    if data then
      self:_write_messages(data.messages)
    end
  end
end

--- Scroll forward in history
function EnlightenChat:scroll_forward()
  if not self.writer.active then
    local data = self.history:scroll_forward()
    if data then
      self:_write_messages(data.messages)
    else
      self:_write_messages(self.messages)
    end
  end
end

--- Format the prompt for generating content. The prompt includes the prompt buffer
--- content (user command), code snippet that was selected when engaging with this
--- feature (if any) as well as the current file name so that the model can know what
--- file type this is and what language to write code in.
---@return string
function EnlightenChat:_build_prompt(messages, range)
  local buf = self.target_buf
  local lines = api.nvim_buf_line_count(buf)
  local snippet_start = range.row_start
  local snippet_finish = range.row_end
  local context = 100
  local context_start = snippet_start - context < 0 and 0 or snippet_start - context
  local context_finish = snippet_finish + context > lines and -1 or snippet_finish + context

  local file_name = api.nvim_buf_get_name(buf)
  local indent = vim.api.nvim_get_option_value("tabstop", { buf = buf })

  local context_above = buffer.get_content(buf, context_start, snippet_start)
  local context_below = buffer.get_content(buf, snippet_finish + 1, context_finish)
  local snippet = buffer.get_content(buf, snippet_start, snippet_finish + 1)

  -- Wrap the above and below context with backticks if they actually exist
  if vim.trim(context_above) ~= "" then
    context_above = "Context above:\n" .. context_above .. "\n"
  end
  if vim.trim(context_below) ~= "" then
    context_below = "Context below\n" .. context_below .. "\n"
  end

  return "File name of the file in the buffer is "
    .. file_name
    .. " with indentation (tabstop) of "
    .. indent
    .. ".\n\n"
    .. context_above
    .. "Snippet:\n"
    .. snippet
    .. "\n\n"
    .. context_below
    .. "\n\nConversation:\n"
    .. messages
end

function EnlightenChat:write_to_buffer()
  local messages = vim.fn.json_encode(self:_build_messages())

  --- This function runs after the LLM call to get lines that should be edited
  ---@param response string
  local function on_done(response)
    -- response should parse to { start_row = number, end_row = number }
    local success, json = pcall(vim.fn.json_decode, response)
    if not success then
      vim.notify("Failed to edit buffer", vim.log.levels.ERROR)
      return
    end

    if json.start_row == -1 then
      vim.notify("There is nothing in the buffer to edit", vim.log.levels.INFO)
      return
    end

    local range = {
      row_start = json.start_row,
      row_end = json.end_row,
      col_start = 0,
      col_end = 0,
    }

    -- clear highlights in range before adding more to them
    diff_hl.reset_hunk(self.target_buf, diff_hl.get_hunk_in_range(self.target_buf, range))

    local prompt = self:_build_prompt(messages, range)
    local opts = {
      provider = self.aiConfig.provider,
      model = self.aiConfig.model,
      tokens = self.aiConfig.tokens,
      timeout = self.aiConfig.timeout,
      temperature = self.aiConfig.temperature,
      feature = "edit", -- simulate editing content from the edit feature
      stream = true,
    }
    ai.complete(prompt, DiffWriter:new(self.target_buf, range, { mode = "diff" }), opts)
  end

  local content = buffer.get_content_with_lines(self.target_buf)
  local prompt = "For the following chat conversation and buffer content, return the `start_row` and `end_row` (inclusive) from the buffer that would need to be edited to make the changes discussed in the conversation a reality. Return yor response as JSON. If the buffer should not be edited, retrun `-1` for the value of `start_row'\n\nConversation\n\n"
    .. messages
    .. "\n\n\nBuffer:\n"
    .. content

  local opts = {
    provider = self.aiConfig.provider,
    model = self.aiConfig.model,
    tokens = self.aiConfig.tokens,
    timeout = self.aiConfig.timeout,
    temperature = self.aiConfig.temperature,
    feature = "get_range",
    stream = false,
    json = true,
  }
  ai.complete(prompt, SelfWriter:new(on_done), opts)
end

return EnlightenChat
