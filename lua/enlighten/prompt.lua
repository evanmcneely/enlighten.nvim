local api = vim.api
local buffer = require("enlighten/buffer")
local Writer = require("enlighten/writer/diff")
local group = require("enlighten/autocmd")
local Logger = require("enlighten/logger")

---@class EnlightenPrompt
---@field settings EnlightenPromptSettings
---@field prompt_buf number
---@field prompt_win number
---@field target_buf number
---@field target_range Range
---@field writer DiffWriter
local EnlightenPrompt = {}

-- Initial gateway into the "prompt" feature. Initialize all data, windows,
-- keymaps and autocammonds that the feature depends on.
---@param ai AI
---@param settings EnlightenPromptSettings
---@return EnlightenPrompt
function EnlightenPrompt:new(ai, settings)
  self.__index = self

  local buf = api.nvim_get_current_buf()
  local range = buffer.get_range()
  local prompt_win = self._create_window(range, settings)

  self.ai = ai
  self.settings = settings
  self.prompt_win = prompt_win.win_id
  self.prompt_buf = prompt_win.bufnr
  self.target_buf = buf
  self.target_range = range
  self.writer = Writer:new(buf, range)

  self:_set_keymaps()
  self:_set_autocmds()

  vim.cmd("startinsert")

  return self
end

-- Reset the buffer to the state it was in before AI content was generated (if any)
-- and close the popup window.
function EnlightenPrompt:close()
  self.writer:reset()

  if api.nvim_win_is_valid(self.prompt_win) then
    Logger:log("prompt:close - closing window", { prompt_win = self.prompt_win })
    api.nvim_win_close(self.prompt_win, true)
  end

  if api.nvim_buf_is_valid(self.prompt_buf) then
    Logger:log("prompt:close - deleting buffer", { prompt_buf = self.prompt_buf })
    api.nvim_buf_delete(self.prompt_buf, { force = true })
  end
end

-- Focus the popup window
function EnlightenPrompt:focus()
  if api.nvim_buf_is_valid(self.prompt_buf) and api.nvim_win_is_valid(self.prompt_win) then
    Logger:log(
      "prompt:focus - focusing",
      { prompt_buf = self.prompt_buf, prompt_win = self.prompt_win }
    )
    api.nvim_set_current_win(self.prompt_win)
    api.nvim_win_set_buf(self.prompt_win, self.prompt_buf)
  end
end

-- Submit the current prompt for generation. Any previously generated content
-- will be cleared. This is mapped to a key on the prompt buffer.
function EnlightenPrompt:submit()
  if
    api.nvim_buf_is_valid(self.prompt_buf)
    and api.nvim_win_is_valid(self.prompt_win)
    and api.nvim_buf_is_valid(self.target_buf)
  then
    Logger:log("prompt:submit - let's go")

    self.writer:reset()

    local prompt = self:_build_prompt()

    self.ai:complete(prompt, self.writer)
  end
end

-- Keep (approve) AI generated content and close the buffer. If no content
-- has been generated, this will do nothing. this is mapped to a key on the prompt buffer.
function EnlightenPrompt:keep()
  if self.writer.accumulated_text ~= "" then
    Logger:log("prompt:keep - confirmed")
    self.writer:keep()
    vim.cmd("lua require('enlighten'):close_prompt()")
  end
end

-- Create the prompt buffer and popup window
---@param range Range
---@param settings EnlightenPromptSettings
---@return { bufnr:number, win_id:number }
function EnlightenPrompt._create_window(range, settings)
  Logger:log("prompt:_create_window - creating window", { range = range })

  local buf = api.nvim_create_buf(false, true)
  local win = api.nvim_open_win(buf, true, {
    relative = "win",
    width = settings.width,
    height = settings.height,
    -- Open he window one line above the current one so that removed
    -- lines shown as virtual text are still visible below the popup.
    bufpos = { range.row_start - 1, 0 },
    -- Set so that code will be visible at least by most formatters standards.
    col = 80,
    anchor = "SW",
    border = "single",
  })

  -- nvim 0.8.0+ get's a title
  if vim.version().minor > 8 or vim.version().major > 0 then
    api.nvim_win_set_config(win, { title = "Prompt" })
  end

  api.nvim_set_option_value("number", false, { win = win })
  api.nvim_set_option_value("signcolumn", "no", { win = win })
  api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  api.nvim_buf_set_name(buf, "enlighten-prompt")
  api.nvim_set_option_value("filetype", "enlighten", { buf = buf })
  api.nvim_set_option_value("wrap", true, { win = win })

  Logger:log("prompt:_create_window - window and buffer", { win = win, buf = buf })

  return {
    bufnr = buf,
    win_id = win,
  }
end

-- Set all keymaps for the prompt buffer needed for user interactions. This
-- is the primary UX for the prompt feature.
--
-- - q         : close the prompt buffer
-- - <cr>      : submit prompt for generation
-- - <C-y>     : approve generated content
function EnlightenPrompt:_set_keymaps()
  api.nvim_buf_set_keymap(
    self.prompt_buf,
    "n",
    "q",
    "<Cmd>lua require('enlighten'):close_prompt()<CR>",
    {}
  )
  api.nvim_buf_set_keymap(
    self.prompt_buf,
    "n",
    "<CR>",
    "<Cmd>lua require('enlighten').prompt:submit()<CR>",
    {}
  )
  api.nvim_buf_set_keymap(
    self.prompt_buf,
    "n",
    "<C-y>",
    "<Cmd>lua require('enlighten').prompt:keep()<CR>",
    {}
  )
end

-- Set all autocmds for the prompt buffer
function EnlightenPrompt:_set_autocmds()
  api.nvim_create_autocmd({ "BufWinEnter", "BufWinLeave" }, {
    callback = function()
      buffer.sticky_buffer(self.prompt_buf, self.prompt_win)
    end,
    group = group,
  })
end

-- Format the prompt generating content. The prompt includes the prompt buffer
-- content (user command), code snippet that was selected when engaging with this
-- feature (if any) as well as the current file name so that the model can know what
-- file type this is and what language to write code in.
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

return EnlightenPrompt
