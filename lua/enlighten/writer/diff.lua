local api = vim.api
local buffer = require("enlighten/buffer")
local differ = require("enlighten/diff")
local Logger = require("enlighten/logger")
local utils = require("enlighten/utils")

---@class DiffWriter: Writer
---@field orig_range number[] -- original start and end rows selected (minimum being the line the cursor is on)
---@field orig_lines string[] -- original lines of text selected (minimum being the line the cursor is on)
---@field accumulated_text string -- stores all accumulated text
---@field accumulated_line string -- stores text of the current line before it added to the buffer
---@field accumulated_lines string[] -- stores all complete lines that have been generated
---@field focused_line number -- stores the current line text will be written to
---@field focused_line_id number -- extmark id for the focused line highlight
---@field line_ns_id number -- namespace id for the focused line highlight
---@field diff LineDiff -- stores the most recent line diff computed
---@field diff_ns_id number -- namespace id for diff highlights
local DiffWriter = {}

---@param buf number
---@param range Range
---@param on_done? fun():nil
---@return DiffWriter
function DiffWriter:new(buf, range, on_done)
  local diff_ns_id = api.nvim_create_namespace("EnlightenDiffHighlights")
  local line_ns_id = api.nvim_create_namespace("EnlightenLineHighlights")
  Logger:log("diff:new", { buffer = buf, range = range, ns_id = diff_ns_id })

  self.__index = self
  return setmetatable({
    buffer = buf,
    -- Note: The first line is always considered to be selected and can be potentially replaced. This
    -- is for simplicity - only one case where lines are selected and by default the first one is.
    orig_lines = vim.api.nvim_buf_get_lines(buf, range.row_start, range.row_end + 1, false),
    orig_range = { range.row_start, range.row_end }, -- end inclusive
    accumulated_text = "",
    accumulated_line = "",
    accumulated_lines = {},
    diff = {},
    focused_line = range.row_start,
    diff_ns_id = diff_ns_id,
    line_ns_id = line_ns_id,
    focuseed_line_id = nil,
    on_done = on_done or function() end,
  }, self)
end

---@param text string
function DiffWriter:on_data(text)
  self.accumulated_line = self.accumulated_line .. text
  self.accumulated_text = self.accumulated_text .. text

  local lines = vim.split(self.accumulated_line, "\n")
  local needs_diff_update = false

  -- Lines having a length greater than 1 indicates that there are complete
  -- lines ready to be set in the buffer. We set all of them before resetting
  -- our current accumulated_line to the last line in the table.
  if #lines > 1 then
    -- Skip last line as it is not complete yet
    for i = 1, #lines - 1 do
      local was_set = self:_set_line(lines[i])
      if was_set then
        needs_diff_update = true
      end
      self:_inc_focused_line()
    end
    self.accumulated_line = lines[#lines]

    if needs_diff_update then
      local right = self.accumulated_lines
      local left = utils.slice(self.orig_lines, 1, #right)
      self:_highlight_diff(left, right)
    end
  end
end

function DiffWriter:on_complete(err)
  if err then
    Logger:log("diff:on_complete - error", err)
    api.nvim_err_writeln("Enlighten: " .. err)
    return
  end

  if #self.accumulated_line > 0 then
    self:_set_line(self.accumulated_line)
    self.accumulated_line = ""
    self:_inc_focused_line()
  end
  self:_clear_focused_line_highlight()
  self:_remove_remaining_selected_lines()
  self:_highlight_diff(self.orig_lines, self.accumulated_lines)
  self:on_done()

  Logger:log("diff:on_complete - ai completion", self.accumulated_text)
end

---@param line string
---@return boolean -- whether or not the line was set
function DiffWriter:_set_line(line)
  table.insert(self.accumulated_lines, line)

  -- Short circuit if the line we would write is unchanged from the current line (always write new lines "").
  -- This has cascading performance improvements (syntax highlighting, recomputing diff and highlights)
  local orig_line = buffer.get_content(self.buffer, self.focused_line, self.focused_line + 1)
  if line ~= "" and orig_line == line then
    return false
  end

  -- We want to replace existing text at the focused line if the command is run on
  -- a selection and fewer lines have been written than than the selection. The
  -- behaviour of nvim_buf_set_lines is controlled in this case by incrementing the
  -- focused line number by one to trigger replacement instead of insertion.
  local set_lines = self.focused_line - self.orig_range[1]
  local selected_lines = self.orig_range[2] - self.orig_range[1]
  local replace_focused_line = set_lines <= selected_lines
  local end_line = self.focused_line + (replace_focused_line and 1 or 0)

  Logger:log(
    "diff:_set_line - setting line",
    { line = line, num = self.focused_line, replacing = replace_focused_line }
  )

  api.nvim_buf_set_lines(self.buffer, self.focused_line, end_line, false, { line })

  return true
end

function DiffWriter:_inc_focused_line()
  local opts = {
    end_row = self.focused_line + 1,
    hl_group = "CursorLine",
    hl_eol = true,
  }
  if self.focused_line_id then
    opts.id = self.focused_line_id
  end

  -- Has the potential to error when writing content at the end of the buffer.
  local success, result = pcall(function()
    return api.nvim_buf_set_extmark(self.buffer, self.line_ns_id, self.focused_line, 0, opts)
  end)
  if success then
    self.focused_line_id = result
  end

  self.focused_line = self.focused_line + 1
end

function DiffWriter:_clear_focused_line_highlight()
  if self.focused_line_id then
    api.nvim_buf_del_extmark(self.buffer, self.line_ns_id, self.focused_line_id)
    self.focused_line_id = nil
  end
end

---@param left string[]
---@param right string[]
function DiffWriter:_highlight_diff(left, right)
  self:_clear_diff_highlights()

  local diff_new = differ.diff(left, right)
  local hunks = differ.extract_hunks(self.orig_range[1], diff_new)

  for row, hunk in pairs(hunks) do
    if #hunk.add then
      -- Has the potential to error when writing/highlighting content at the end of the buffer.
      pcall(function()
        api.nvim_buf_set_extmark(self.buffer, self.diff_ns_id, row, 0, {
          end_row = row + #hunk.add,
          hl_group = "DiffAdd",
          hl_eol = true,
          priority = 1000,
        })
      end)
    end

    if #hunk.remove then
      local virt_lines = {} --- @type {[1]: string, [2]: string}[][]

      for _, line in pairs(hunk.remove) do
        table.insert(virt_lines, { { line .. string.rep(" ", vim.o.columns), "DiffDelete" } })
      end

      api.nvim_buf_set_extmark(self.buffer, self.diff_ns_id, row, -1, {
        virt_lines = virt_lines,
        -- TODO: virt_lines_above doesn't work on row 0 neovim/neovim#16166
        virt_lines_above = true,
      })
    end
  end

  self.diff = diff_new
end

function DiffWriter:_remove_remaining_selected_lines()
  if self.focused_line <= self.orig_range[2] then
    Logger:log(
      "diff:_remove_remaining_selected_lines - removing lines",
      { first = self.focused_line, last = self.orig_range[2] }
    )
    api.nvim_buf_set_lines(self.buffer, self.focused_line, self.orig_range[2] + 1, false, {})
  end
end

function DiffWriter:_clear_diff_highlights()
  api.nvim_buf_clear_namespace(self.buffer, self.diff_ns_id, 0, -1)
end

function DiffWriter:_clear_lines()
  api.nvim_buf_set_lines(self.buffer, self.orig_range[1], self.focused_line, false, self.orig_lines)
end

function DiffWriter:_clear_state()
  self.focused_line = self.orig_range[1]
  self.accumulated_text = ""
  self.accumulated_line = ""
  self.accumulated_lines = {}
  self.diff = {}
end

function DiffWriter:reset()
  if self.accumulated_text ~= "" then
    Logger:log("diff:reset - clearing highlights and lines")
    self:_clear_diff_highlights()
    self:_clear_lines()
  end

  self:_clear_state()
end

function DiffWriter:keep()
  Logger:log("diff:keep")
  self:_clear_diff_highlights()
  self:_clear_state()
end

return DiffWriter
