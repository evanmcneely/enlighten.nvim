local api = vim.api
local buffer = require("enlighten/buffer")
local Writer = require("enlighten/writer/diff")
local Logger = require("enlighten/logger")
local History = require("enlighten/history")

---@class EnlightenPrompt
---@field settings EnlightenPromptSettings
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
--- prompt window is display'd.
---@field prompt_ext_id number
local EnlightenPrompt = {}

--- Initial gateway into the "prompt" feature. Initialize all data, windows,
--- keymaps and autocammonds that the feature depends on.
---@param ai AI
---@param settings EnlightenPromptSettings
---@param history string[][]
---@return EnlightenPrompt
function EnlightenPrompt:new(ai, settings, history)
  self.__index = self

  local buf = api.nvim_get_current_buf()
  local range = buffer.get_range()
  local prompt_win = self._create_window(buf, range, settings)

  self.ai = ai
  self.settings = settings
  self.prompt_win = prompt_win.win_id
  self.prompt_buf = prompt_win.bufnr
  self.target_buf = buf
  self.target_range = range
  self.history = History:new(prompt_win.bufnr, history)
  self.prompt_ns_id = prompt_win.ns_id
  self.prompt_ext_id = prompt_win.ext_id

  local function on_done()
    self.history:update()
  end
  self.writer = Writer:new(buf, range, on_done)

  self:_set_keymaps()

  vim.cmd("startinsert")

  Logger:log("prompt:new", {
    prompt_win = prompt_win.win_id,
    prompt_buf = prompt_win.bufnr,
    target_buf = buf,
    target_range = range,
  })

  return self
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

  -- Reset the buffer to it's previous state
  self.writer:reset()

  if api.nvim_win_is_valid(self.prompt_win) then
    Logger:log("prompt:close - closing window", { prompt_win = self.prompt_win })
    api.nvim_win_close(self.prompt_win, true)
  end

  if api.nvim_buf_is_valid(self.prompt_buf) then
    Logger:log("prompt:close - deleting buffer", { prompt_buf = self.prompt_buf })
    api.nvim_buf_delete(self.prompt_buf, { force = true })
  end

  api.nvim_buf_del_extmark(self.target_buf, self.prompt_ns_id, self.prompt_ext_id)
end

--- Focus the popup window
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

--- Submit the current prompt for generation. Any previously generated content
--- will be cleared. This is mapped to a key on the prompt buffer.
function EnlightenPrompt:submit()
  if
    api.nvim_buf_is_valid(self.prompt_buf)
    and api.nvim_win_is_valid(self.prompt_win)
    and api.nvim_buf_is_valid(self.target_buf)
  then
    -- Prevent trying to write two completions to the same range of
    -- text at the same time.
    if self.writer.active then
      return
    end

    self.writer:reset()

    local prompt = self:_build_prompt()
    self.ai:complete(prompt, self.writer)
  end
end

--- Keep (approve) AI generated content and close the buffer. If no content
--- has been generated, this will do nothing. This is mapped to a key on the prompt buffer.
function EnlightenPrompt:keep()
  if self.writer.accumulated_text ~= "" then
    Logger:log("prompt:keep - confirmed")
    self.writer:keep()
    vim.cmd("lua require('enlighten'):close_prompt()")
  end
end

--- Create the prompt buffer and popup window.
---@param target_buf number
---@param range Range
---@param settings EnlightenPromptSettings
---@return { bufnr:number, win_id:number, ns_id:number, ext_id:number }
function EnlightenPrompt._create_window(target_buf, range, settings)
  Logger:log("prompt:_create_window - creating window", { range = range })

  local current_win = api.nvim_get_current_win()
  local ns_id = api.nvim_create_namespace("EnlightenPrompt")

  local height = settings.height
  local border =  { "", "", "", "", "", "", "", "" }

  if settings.showTitle then
    height = height + 1
    border[2] = " "
  end
  if settings.showHelp then
    height = height + 1
    border[6] = " "
  end

  -- We don't want the prompt to cover any code. Virtual lines are injected into the
  -- buffer and the prompt window is position over top of it.
  local virt_lines = {}
  for i = 1, height do
    virt_lines[i] = { { "", "normal" } }
  end

  local rendertop = range.row_start == 0
  local row = rendertop and 0 or range.row_start - 1
  local extmark = api.nvim_buf_set_extmark(target_buf, ns_id, row, 0, {
    virt_lines = virt_lines,
    virt_lines_above = rendertop,
  })

  -- scroll to make virtual lines above visible
  if rendertop then
    api.nvim_win_call(current_win, function()
      vim.cmd("normal " .. vim.api.nvim_replace_termcodes("<C-b>", true, false, true))
      vim.cmd("normal " .. "gg")
    end)
  end

  local buf = api.nvim_create_buf(false, true)
  local win = api.nvim_open_win(buf, true, {
    relative = "win",
    width = settings.width,
    height = settings.height,
    bufpos = { range.row_start, 0 },
    anchor = "SW",
    border = border,
    style = "minimal",
    title = settings.showTitle and "Enlighten" or nil,
    footer = settings.showHelp and {
      -- help info in the footer
      { "submit ", "EnlightenPromptHelpMsg" },
      { "<cr>  ", "EnlightenPromptHelpKey" },
      { "close ", "EnlightenPromptHelpMsg" },
      { "q  ", "EnlightenPromptHelpKey" },
      { "history ", "EnlightenPromptHelpMsg" },
      { "<c-o>/<c-i>  ", "EnlightenPromptHelpKey" },
    } or nil,
    footer_pos = settings.showHelp and "right" or nil,
  })

  api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  api.nvim_buf_set_name(buf, "enlighten-prompt")
  api.nvim_set_option_value("filetype", "enlighten", { buf = buf })
  api.nvim_set_option_value("wrap", true, { win = win })
  api.nvim_set_option_value("winhl", "FloatTitle:EnlightenPromptTitle", { win = win })

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
  api.nvim_buf_set_keymap(
    self.prompt_buf,
    "n",
    "<C-o>",
    "<Cmd>lua require('enlighten').prompt:_scroll_back()<CR>",
    {}
  )
  api.nvim_buf_set_keymap(
    self.prompt_buf,
    "n",
    "<C-i>",
    "<Cmd>lua require('enlighten').prompt:_scroll_forward()<CR>",
    {}
  )
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
function EnlightenPrompt:_scroll_back()
  self.history:scroll_back()
end

--- Scroll forward in history. This is mapped to a key on the prompt buffer.
function EnlightenPrompt:_scroll_forward()
  self.history:scroll_forward()
end

return EnlightenPrompt
