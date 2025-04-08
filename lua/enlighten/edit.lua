local api = vim.api
local ai = require("enlighten.ai")
local buffer = require("enlighten.buffer")
local augroup = require("enlighten.autocmd")
local Writer = require("enlighten.writer.diff")
local Logger = require("enlighten.logger")
local History = require("enlighten.history")
local mentions = require("enlighten.mentions")
local FilePicker = require("enlighten.file_picker")

---@class EnlightenPrompt
--- Settings injected into this class from the plugin config.
---@field settings EnlightenEditSettings
--- AI config injected into this class from the plugin config.
---@field aiConfig EnlightenAiProviderConfig
--- Unique 4 diget number to this session.
---@field id string
--- The id of the prompt buffer.
---@field prompt_buf number
--- The id of the popup window that hosts the prompt buffer.
---@field prompt_win number
--- The id of the buffer that the cursor was in when the prompt window was opened.
--- This is also the buffer that generated text will be written to.
---@field target_buf number
--- The start/end lines and columns of the selected text or cursor position. This is
--- the code that will be replaced when text is generated.
---@field target_range SelectionRange
--- A class responsible for writing text to the target buffer. This feature uses the
--- diff writer to highlight changes as code is generated by the AI provider.
---@field writer DiffWriter
--- A class that helps manage history of past conversations.
---@field history History
--- The namespace id of the prompt window virtual lines
---@field prompt_ns_id number
--- The extmark id of the injected virtual lines in the target buffer over which the
--- prompt window is display'd. This will be nil if the prompt window is opened at the
--- top line of the buffer. In this case we don't use virtual lines.
---@field prompt_ext_id number|nil
--- A list of ids of all autocommands that have been created for this session.
---@field autocommands number[]
--- The current prompt buffer text. Stored here when the prompt is built for AI completion
--- so that prompt history can be scrolled.
---@field prompt string
--- A flag for whether or the not the user has generated text this session.
---@field has_generated boolean
---@field file_picker FilePicker
---@field files filepaths
local EnlightenEdit = {}
EnlightenEdit.__index = EnlightenEdit

-- luacheck: push ignore 631
local FOLDTEXT =
  "[[substitute(getline(v:foldstart),'\\t',repeat('\\ ',&tabstop),'g').'...'.trim(getline(v:foldend)) . ' (' . (v:foldend - v:foldstart + 1) . ' lines)']]"
-- luacheck: pop

--- Create the prompt buffer and popup window.
---
--- The prompt popup window is rendered in one of two ways.
--- 1. Embedded into the buffer between lines.
--- 2. Positioned at some column indentation, out of the way of buffer content.
---
--- We prefer (1) but this approach complicates things when the prompt
--- is opened from the top of a buffer. In this case we do (2).
---@param id string
---@param target_buf number
---@param range SelectionRange
---@param settings EnlightenEditSettings
---@return { bufnr:number, win_id:number, ns_id:number, ext_id:number|nil }
local function create_window(id, target_buf, range, settings)
  local ns_id = api.nvim_create_namespace("EnlightenPrompt-" .. id)
  local buf = api.nvim_create_buf(false, true)
  local open_at_top = range.row_start <= 1
  local extmark
  local win_opts = {
    relative = "win",
    width = settings.width,
    height = settings.height,
    bufpos = { range.row_start - 1, 0 },
    anchor = "SW",
    border = { "", settings.border, "", "", "", settings.border, "", "" },
    style = "minimal",
  }

  if settings.showTitle then
    win_opts.title = { { " Enlighten Edit ", "EnlightenPromptTitle" } }
  end

  if settings.showHelp then
    -- Help info in the footer.
    win_opts.footer = {
      { " submit ", "EnlightenPromptHelpMsg" },
      { "<cr>  ", "EnlightenPromptHelpKey" },
      { "close ", "EnlightenPromptHelpMsg" },
      { "q  ", "EnlightenPromptHelpKey" },
      { "confirm ", "EnlightenPromptHelpMsg" },
      { "<c-y>  ", "EnlightenPromptHelpKey" },
      { "history ", "EnlightenPromptHelpMsg" },
      { "<c-o>/<c-i>  ", "EnlightenPromptHelpKey" },
    }
    win_opts.footer_pos = "right"
  end

  if open_at_top then
    win_opts.col = 80
  else
    -- If there is a border, add to the height to fit the border
    local height = settings.border == "" and settings.height or settings.height + 2
    local virt_lines = {}
    for i = 1, height do
      virt_lines[i] = { { "", "normal" } }
    end
    -- We need to position the window 1 line above the target range so that other virtual
    -- text we want to add to that line (such as removed line highlights) work without any hassle.
    local row = range.row_start - 2
    extmark = api.nvim_buf_set_extmark(target_buf, ns_id, row, 0, {
      virt_lines = virt_lines,
    })
  end

  local win = api.nvim_open_win(buf, true, win_opts)
  api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  api.nvim_buf_set_name(buf, "enlighten-edit-" .. id)
  api.nvim_set_option_value("filetype", "enlighten", { buf = buf })
  api.nvim_set_option_value("wrap", true, { win = win })
  api.nvim_set_option_value("winhl", "FloatBorder:EnlightenPromptBorder", { win = win })
  api.nvim_set_option_value("foldmethod", "manual", { win = win })
  api.nvim_set_option_value("foldtext", FOLDTEXT, { win = win })

  return {
    bufnr = buf,
    win_id = win,
    ns_id = ns_id,
    ext_id = extmark,
  }
end

--- Set all keymaps for the prompt buffer needed for user interactions. This
--- is the primary UX for the prompt feature.
---
--- - q         : close the prompt buffer
--- - <cr>      : submit prompt for generation
--- - <C-y>     : approve generated content
--- - <C-o>    : scroll back in history
--- - <C-i>    : scroll forward in history
---@param context EnlightenPrompt
local function set_keymaps(context)
  api.nvim_buf_set_keymap(context.prompt_buf, "n", "q", "", {
    noremap = true,
    silent = true,
    callback = function()
      context:close()
    end,
  })
  api.nvim_buf_set_keymap(context.prompt_buf, "n", "<CR>", "", {
    noremap = true,
    silent = true,
    callback = function()
      context:submit()
    end,
  })
  api.nvim_buf_set_keymap(context.prompt_buf, "n", "<C-y>", "", {
    noremap = true,
    silent = true,
    callback = function()
      context:confirm()
    end,
  })
  api.nvim_buf_set_keymap(context.prompt_buf, "n", "<C-o>", "", {
    noremap = true,
    silent = true,
    callback = function()
      context:scroll_back()
    end,
  })
  api.nvim_buf_set_keymap(context.prompt_buf, "n", "<C-i>", "", {
    noremap = true,
    silent = true,
    callback = function()
      context:scroll_forward()
    end,
  })
end

--- Set all autocommands that the feature is dependant on
---@param context EnlightenPrompt
---@return number[]
local function set_autocmds(context)
  local autocmd_ids = {
    -- When the target buffer is not in any window -> close the prompt
    api.nvim_create_autocmd("BufWinLeave", {
      group = augroup,
      buffer = context.target_buf,
      callback = function()
        context:close()
      end,
    }),
    -- When the prompt window is closed with :q -> cleanup
    api.nvim_create_autocmd("BufHidden", {
      group = augroup,
      buffer = context.prompt_buf,
      callback = function()
        context:cleanup()
      end,
    }),
    -- Add completion sources
    api.nvim_create_autocmd("InsertEnter", {
      group = augroup,
      buffer = context.prompt_buf,
      once = true,
      desc = "Setup the completion of helpers in the input buffer",
      callback = function()
        local has_cmp, cmp = pcall(require, "cmp")
        if has_cmp then
          cmp.register_source(
            "enlighten_commands",
            require("enlighten.cmp").new(mentions.get(context), context.prompt_buf)
          )
          cmp.setup.buffer({
            enabled = true,
            sources = {
              { name = "enlighten_commands" },
            },
          })
        end
      end,
    }),
  }

  context.autocommands = autocmd_ids
  return autocmd_ids
end

--- Clean up all autocommands that have been created
---@param context EnlightenPrompt
local function delete_autocmds(context)
  for _, id in ipairs(context.autocommands or {}) do
    local status, err = pcall(api.nvim_del_autocmd, id)
    if not status then
      Logger:log("delete_autocmds - error", { id = context.id, autocmd_id = id, error = err })
    end
  end
end

--- Format the prompt text in the universal "messages" format
---@param prompt string
---@return AiMessages
local function build_messages(prompt)
  return { { role = "user", content = prompt } }
end

--- Initial gateway into the "prompt" feature. Initialize all data, windows,
--- keymaps and autocommands that the feature depends on.
---@param aiConfig EnlightenAiProviderConfig
---@param settings EnlightenEditSettings
---@return EnlightenPrompt
function EnlightenEdit:new(aiConfig, settings)
  local id = tostring(math.random(10000))
  local buf = api.nvim_get_current_buf()
  local range = buffer.get_range()
  local prompt_win = create_window(id, buf, range, settings)

  local context = setmetatable({}, self)
  context.id = id
  context.prompt_win = prompt_win.win_id
  context.prompt_buf = prompt_win.bufnr
  context.target_buf = buf
  context.target_range = range
  context.prompt_ns_id = prompt_win.ns_id
  context.prompt_ext_id = prompt_win.ext_id
  context.settings = settings
  context.aiConfig = aiConfig
  context.history = History:new("edit")
  context.prompt = ""
  context.has_generated = false
  context.files = {}
  context.writer = Writer:new(buf, range, {
    mode = settings.diff_mode,
    on_done = function()
      context.has_generated = true
    end,
  })
  context.file_picker = FilePicker:new(id, function(path, content)
    table.insert(context.files, path)
    context:_add_file_path(path, content)
  end)

  set_keymaps(context)
  set_autocmds(context)

  api.nvim_command("startinsert")

  Logger:log("edit:new", {
    id = id,
    prompt_win = prompt_win.win_id,
    prompt_buf = prompt_win.bufnr,
    target_buf = buf,
    target_range = range,
    autocmds = context.autocommands,
  })

  return context
end

--- Reset the buffer to the state it was in before AI content was generated (if any)
--- and close the popup window.
function EnlightenEdit:close()
  -- We prevent the prompt window from being closed if text is being written to the
  -- buffer. The prompt window has all the keymaps to clear the text and highlights
  -- but is dependant on the writer being "done" to behave as expected.
  if self.writer.active then
    return
  end

  if self.has_generated then
    self.history:update(build_messages(buffer.get_content(self.prompt_buf)), self.files)
  end

  Logger:log("edit:close", { id = self.id })

  if api.nvim_win_is_valid(self.prompt_win) then
    api.nvim_win_close(self.prompt_win, true)
  end

  if api.nvim_buf_is_valid(self.prompt_buf) then
    api.nvim_buf_delete(self.prompt_buf, { force = true })
  end

  self:cleanup()
end

-- Clean side effects like autocommands, highlights, extmarks, etc. that
-- not related to the prompt buffer on window
function EnlightenEdit:cleanup()
  self.writer:stop()
  self.writer:reset()

  if api.nvim_buf_is_valid(self.target_buf) and self.prompt_ext_id then
    api.nvim_buf_del_extmark(self.target_buf, self.prompt_ns_id, self.prompt_ext_id)
  end

  delete_autocmds(self)
end

--- Submit the current prompt for generation. Any previously generated content
--- will be cleared. This is mapped to a key on the prompt buffer.
function EnlightenEdit:submit()
  if
    api.nvim_buf_is_valid(self.prompt_buf)
    and api.nvim_win_is_valid(self.prompt_win)
    and api.nvim_buf_is_valid(self.target_buf)
    and not self.writer.active
  then
    Logger:log("edit:submit", { id = self.id })

    self.writer:reset()
    local prompt = self:_build_prompt()

    local opts = {
      provider = self.aiConfig.provider,
      model = self.aiConfig.model,
      tokens = self.aiConfig.tokens,
      timeout = self.aiConfig.timeout,
      temperature = self.aiConfig.temperature,
      feature = "edit",
      stream = true,
    }
    ai.complete(prompt, self.writer, opts)
  end
end

--- Keep (approve) AI generated content and close the buffer. If no content
--- has been generated, this will do nothing. This is mapped to a key on the prompt buffer.
function EnlightenEdit:confirm()
  if not self.writer.active then
    Logger:log("edit:confirm", { id = self.id })
    self.writer:keep()
    self:close()
  end
end

--- Format the prompt for generating content. The prompt includes the prompt buffer
--- content (user command), code snippet that was selected when engaging with this
--- feature (if any) as well as the current file name so that the model can know what
--- file type this is and what language to write code in.
---@return string
function EnlightenEdit:_build_prompt()
  local buf = self.target_buf
  local lines = api.nvim_buf_line_count(buf)
  local snippet_start = self.target_range.row_start
  local snippet_finish = self.target_range.row_end
  local context_start = snippet_start - self.settings.context < 0 and 0
    or snippet_start - self.settings.context
  local context_finish = snippet_finish + self.settings.context > lines and -1
    or snippet_finish + self.settings.context

  local file_name = api.nvim_buf_get_name(buf)
  local indent = vim.api.nvim_get_option_value("tabstop", { buf = buf })
  local user_prompt = buffer.get_content(self.prompt_buf)

  local context_above = buffer.get_content(buf, context_start, snippet_start)
  local context_below = buffer.get_content(buf, snippet_finish + 1, context_finish)
  local snippet = buffer.get_content(buf, snippet_start, snippet_finish + 1)

  if vim.trim(context_above) ~= "" then
    context_above = "Context above:\n" .. context_above .. "\n\n"
  end
  if vim.trim(context_below) ~= "" then
    context_below = "Context below:\n" .. context_below .. "\n\n"
  end

  self.prompt = user_prompt

  local prompt = "File name of the file in the buffer is "
    .. file_name
    .. " with indentation (tabstop) of "
    .. indent
    .. ".\n\n"
    .. context_above
    .. "Snippet:\n"
    .. snippet
    .. "\n\n"
    .. context_below
    .. "Instructions:\n"
    .. user_prompt

  return prompt
end

--- Scroll back in history. This is mapped to a key on the prompt buffer.
function EnlightenEdit:scroll_back()
  local data = self.history:scroll_back()
  if data then
    self.files = data.files or {}
    -- Only one message is expected
    api.nvim_buf_set_lines(self.prompt_buf, 0, -1, false, vim.split(data.messages[1].content, "\n"))
  end
end

--- Scroll forward in history. This is mapped to a key on the prompt buffer.
function EnlightenEdit:scroll_forward()
  local data = self.history:scroll_forward()
  if data then
    self.files = data.files or {}
    -- Only one message is expected
    api.nvim_buf_set_lines(self.prompt_buf, 0, -1, false, vim.split(data.messages[1].content, "\n"))
  else
    -- Use the prompt from this session when no data is returned
    api.nvim_buf_set_lines(self.prompt_buf, 0, -1, false, vim.split(self.prompt, "\n"))
  end
end

--- Inject file content into the buffer with folds
---@param path string
---@param content string[]
function EnlightenEdit:_add_file_path(path, content)
  api.nvim_buf_set_lines(self.prompt_buf, -1, -1, true, { "" })

  local start_row = api.nvim_buf_line_count(self.prompt_buf)

  -- Append file path and content to the chat
  local lines = { "", "```" .. path }
  vim.list_extend(lines, content)
  table.insert(lines, "```")

  buffer.insert_with_fold(self.target_buf, start_row, lines)
end

return EnlightenEdit
