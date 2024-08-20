local api = vim.api
local buffer = require("enlighten/buffer")
local augroup = require("enlighten/autocmd")
local Writer = require("enlighten/writer/diff")
local Logger = require("enlighten/logger")
local History = require("enlighten/history")

---@class EnlightenPrompt
---@field settings EnlightenPromptSettings
--- A random id to distinguish this instance from others
---@field id string
--- The id of the prompt buffer
---@field prompt_buf number
--- The id of the popup window that hosts the prompt buffer
---@field prompt_win number
--- The id of the buffer that the cursor was in when the prompt was opened. This
--- is also the buffer that generated text will be written to.
---@field target_buf number
--- The start/end lines and columns of the selected text or cursor position. This is
--- the code that will be replaced when text is generated.
---@field target_range Range
--- A class responsible for writing text to the target buffer. This feature uses the
--- diff writer to highlight changes as code is generated by the AI provider.
---@field writer DiffWriter
--- A class responsible for interacting with supported AI providers.
---@field history History
--- A class responsible for interacting with supported AI providers.
---@field ai AI
--- The namespace id of the prompt window virtual lines
---@field prompt_ns_id number
--- The extmark id of the injected virtual lines in the target buffer over which the
--- prompt window is display'd. This will be nil if the prompt window is opened at the
--- top line of the buffer. In this case we don't use virtual lines.
---@field prompt_ext_id number|nil
--- A list of ids of all autocommands that have been created for this feature.
---@field autocommands number[]
local EnlightenPrompt = {}
EnlightenPrompt.__index = EnlightenPrompt

--- Create the prompt buffer and popup window.
---
--- The prompt popup window is rendered in one of two ways.
--- 1. Embedded into the buffer between lines.
--- 2. Positioned at some column out of the way of buffer content.
---
--- We prefer (1) but this approach complicates things when the prompt
--- is opened from the top of a buffer. In this case we do (2).
---@param id string
---@param target_buf number
---@param range Range
---@param settings EnlightenPromptSettings
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
    border = { "", "═", "", "", "", "═", "", "" },
    style = "minimal",
  }

  if open_at_top then
    win_opts.col = 80
  else
    local virt_lines = {}
    for i = 1, settings.height + 2 do
      virt_lines[i] = { { "", "normal" } }
    end
    -- We need to position the window 1 line above the target range so that other virtual
    -- text we want to add to that line (such as removed line highlights) work without any hassel.
    local row = range.row_start - 2
    extmark = api.nvim_buf_set_extmark(target_buf, ns_id, row, 0, {
      virt_lines = virt_lines,
    })
  end

  if settings.showTitle then
    win_opts.title = { { " Prompt ", "EnlightenPromptTitle" } }
  end

  if settings.showHelp and vim.fn.has("nvim-0.10.0") == 1 then
    -- help info in the footer
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

  local win = api.nvim_open_win(buf, true, win_opts)
  api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  api.nvim_buf_set_name(buf, "enlighten-prompt-" .. id)
  api.nvim_set_option_value("filetype", "enlighten", { buf = buf })
  api.nvim_set_option_value("wrap", true, { win = win })
  api.nvim_set_option_value("winhl", "FloatBorder:EnlightenPromptBorder", { win = win })

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
  local autocmd_ids = {}

  -- When the target buffer is not in any window -> close the prompt
  local id = api.nvim_create_autocmd("BufWinLeave", {
    group = augroup,
    buffer = context.target_buf,
    callback = function()
      context:close()
      return true
    end,
  })
  table.insert(autocmd_ids, id)

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

--- Initial gateway into the "prompt" feature. Initialize all data, windows,
--- keymaps and autocommands that the feature depends on.
---@param ai AI
---@param settings EnlightenPromptSettings
---@param history string[][]
---@return EnlightenPrompt
function EnlightenPrompt:new(ai, settings, history)
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
  context.ai = ai
  context.history = History:new(prompt_win.bufnr, history)
  context.writer = Writer:new(buf, range, function()
    context.history:update()
  end)

  set_keymaps(context)
  set_autocmds(context)

  api.nvim_command("startinsert")

  Logger:log("prompt:new", {
    id = id,
    prompt_win = prompt_win.win_id,
    prompt_buf = prompt_win.bufnr,
    target_buf = buf,
    target_range = range,
    autocmd = context.autocommands,
  })

  return context
end

--- Reset the buffer to the state it was in before AI content was generated (if any)
--- and close the popup window.
function EnlightenPrompt:close()
  -- We prevent the prompt window from being closed if text is being written to the
  -- buffer. The prompt window has all the keymaps to clear the text and highlights
  -- but is dependant on the writer being "done" to behave as expected.
  if self.writer.active then
    return
  end

  Logger:log("prompt:close", { buf = self.prompt_buf, win = self.prompt_win, id = self.id })

  -- Reset the buffer to it's previous state
  self.writer:reset()

  if api.nvim_win_is_valid(self.prompt_win) then
    api.nvim_win_close(self.prompt_win, true)
  end

  if api.nvim_buf_is_valid(self.prompt_buf) then
    api.nvim_buf_delete(self.prompt_buf, { force = true })
  end

  if api.nvim_buf_is_valid(self.target_buf) and self.prompt_ext_id then
    api.nvim_buf_del_extmark(self.target_buf, self.prompt_ns_id, self.prompt_ext_id)
  end

  delete_autocmds(self.autocommands or {})
end

--- Submit the current prompt for generation. Any previously generated content
--- will be cleared. This is mapped to a key on the prompt buffer.
function EnlightenPrompt:submit()
  if
    api.nvim_buf_is_valid(self.prompt_buf)
    and api.nvim_win_is_valid(self.prompt_win)
    and api.nvim_buf_is_valid(self.target_buf)
    and not self.writer.active
  then
    self.writer:reset()
    local prompt = self:_build_prompt()
    self.ai:complete(prompt, self.writer)
  end
end

--- Keep (approve) AI generated content and close the buffer. If no content
--- has been generated, this will do nothing. This is mapped to a key on the prompt buffer.
function EnlightenPrompt:confirm()
  if self.writer.accumulated_text ~= "" then
    Logger:log("prompt:keep - confirmed")
    self.writer:keep()
    self:close()
  end
end

--- Format the prompt for generating content. The prompt includes the prompt buffer
--- content (user command), code snippet that was selected when engaging with this
--- feature (if any) as well as the current file name so that the model can know what
--- file type this is and what language to write code in.
---@return string
function EnlightenPrompt:_build_prompt()
  local prompt = buffer.get_content(self.prompt_buf)
  local snippet =
    buffer.get_content(self.target_buf, self.target_range.row_start, self.target_range.row_end + 1)
  local file_name = api.nvim_buf_get_name(self.target_buf)

  return "File name of the file in the buffer is "
    .. file_name
    .. "\n"
    .. "Rewrite the following code snippet following these instructions: "
    .. prompt
    .. "\n"
    .. "\n"
    .. snippet
end

--- Scroll back in history. This is mapped to a key on the prompt buffer.
function EnlightenPrompt:scroll_back()
  self.history:scroll_back()
end

--- Scroll forward in history. This is mapped to a key on the prompt buffer.
function EnlightenPrompt:scroll_forward()
  self.history:scroll_forward()
end

return EnlightenPrompt
