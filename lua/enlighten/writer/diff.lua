local api = vim.api
local buffer = require("enlighten/buffer")
local differ = require("enlighten/diff")
local Logger = require("enlighten/logger")
local utils = require("enlighten/utils")

---@class Writer
--- A flag for whether the writer is actively reciveing streamed text to be processed.
---@field active boolean
--- A flag for whether writing to buffer should be stopped.
---@field shortcircuit boolean
--- The buffer text will be written to.
---@field buffer number
---@field on_complete fun(self: Writer, err: string?): nil
---@field on_data fun(self: Writer, data: string): nil
---@field on_done fun(): nil
---@field start fun(): nil
---@field stop fun(): nil
---@field reset fun(): nil

---@class DiffWriter: Writer
---@field opts DiffWriterOpts
---@field window number
--- The start and end rows of a range of text in the buffer (end inclusive). ex: [1, 3]
--- At a minimum the range covers one line, so one line can always be replaced. This
--- is for simplicity, only one case where a range of text is being written to, rather
--- than trying to write to no line (in-between lines).
---@field orig_range {[1]: number, [2]: number}
--- The text content for the `orig_range` in the buffer. This is the text we diff generated content against.
---@field orig_lines string[]
--- All text that has been generated.
---@field accumulated_text string
--- The text of the current line (from the last \n) that has been generated. Only complete lines are
--- writen to the buffer, so this can be considered a staging area for the next line to be written.
---@field accumulated_line string
--- All lines of text that have been written to the buffer.
---@field accumulated_lines string[]
--- The line in the buffer that will be written to next.
---@field focused_line number
--- The extmark id for the focused line highlight. The highlight is never on the focused line, as the focused
--- line could be outside the buffer. The highlighted line is line we have most recently written text too.
---@field focused_line_id number
--- The namespace id for the focused line highlight.
---@field line_ns_id number
--- The namespace id for diff highlights.
---@field diff_ns_id number
--- The most recent line diff that has been computed.
---@field diff LineDiff
local DiffWriter = {}

---@class DiffWriterOpts
--- Can be "diff", "change" or "smart"
--- - "diff" will show added and removed lines with highlights
--- - "change" will show only added lines with change highlights
--- - "smart" will act like "diff" unless the total number of changed lines exceeds 3/4 the buffer hight
---@field mode string
--- A callback for when streaming content is complete
---@field on_done? fun():nil

---@param buf number
---@param win number
---@param range Range
---@param opts DiffWriterOpts
---@return DiffWriter
function DiffWriter:new(buf, win, range, opts)
  local diff_ns_id = api.nvim_create_namespace("EnlightenDiffHighlights")
  local line_ns_id = api.nvim_create_namespace("EnlightenLineHighlights")
  Logger:log("diff:new", { buffer = buf, range = range, ns_id = diff_ns_id })

  self.__index = self
  return setmetatable({
    active = false,
    shortcircuit = false,
    show_diff = false,
    buffer = buf,
    window = win,
    on_done = opts.on_done or function() end,
    orig_lines = vim.api.nvim_buf_get_lines(buf, range.row_start, range.row_end + 1, false),
    orig_range = { range.row_start, range.row_end }, -- end inclusive
    accumulated_text = "",
    accumulated_line = "",
    accumulated_lines = {},
    focused_line = range.row_start,
    focused_line_id = nil,
    line_ns_id = line_ns_id,
    diff_ns_id = diff_ns_id,
    diff = {},
    opts = opts,
  }, self)
end

---@param text string
function DiffWriter:on_data(text)
  if self.shortcircuit then
    return
  end

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
  self.active = false

  if err then
    Logger:log("diff:on_complete - error", err)
    api.nvim_err_writeln("Enlighten: " .. err)
    return
  end

  if self.shortcircuit then
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
  Logger:log("diff:on_complete - diff", self.diff)
end

---@param line string
---@return boolean -- true if line was set
function DiffWriter:_set_line(line)
  table.insert(self.accumulated_lines, line)

  -- We want to replace existing text at the focused line if the command is run on
  -- a selection and fewer lines have been written than are in the selection.
  local set_lines = self.focused_line - self.orig_range[1]
  local selected_lines = self.orig_range[2] - self.orig_range[1]
  local replace_focused_line = set_lines <= selected_lines

  -- Short circuit if the line we would write is unchanged from the current line (always write new lines "").
  -- This has cascading performance improvements (syntax highlighting, recomputing diff and highlights)
  local orig_line = buffer.get_content(self.buffer, self.focused_line, self.focused_line + 1)
  if line ~= "" and orig_line == line and replace_focused_line == true then
    return false
  end

  local end_line = self.focused_line + (replace_focused_line and 1 or 0)
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

  local function add(row, hunk)
    -- Has the potential to error when writing/highlighting content at the end of the buffer.
    pcall(function()
      api.nvim_buf_set_extmark(self.buffer, self.diff_ns_id, row, 0, {
        end_row = row + #hunk.add,
        hl_group = "EnlightenDiffAdd",
        hl_eol = true,
        priority = 1000,
      })
    end)
  end

  local function remove(row, hunk)
    local virt_lines = {} --- @type {[1]: string, [2]: string}[][]

    for _, line in pairs(hunk.remove) do
      table.insert(
        virt_lines,
        { { line .. string.rep(" ", vim.o.columns), "EnlightenDiffDelete" } }
      )
    end

    api.nvim_buf_set_extmark(self.buffer, self.diff_ns_id, row, -1, {
      virt_lines = virt_lines,
      -- TODO: virt_lines_above doesn't work on row 0 neovim/neovim#16166
      virt_lines_above = true,
    })
  end

  local function change(row, hunk)
    -- Has the potential to error when writing/highlighting content at the end of the buffer.
    pcall(function()
      api.nvim_buf_set_extmark(self.buffer, self.diff_ns_id, row, 0, {
        end_row = row + #hunk.add,
        hl_group = "EnlightenDiffChange",
        hl_eol = true,
        priority = 1000,
      })
    end)
  end

  local show_diff = self.opts.mode ~= "change"
  local lines_changed = 0
  local win_height = vim.api.nvim_win_get_height(self.window)
  for row, hunk in pairs(hunks) do
    lines_changed = lines_changed + #hunk.add
    lines_changed = lines_changed + #hunk.remove

    if lines_changed > (win_height * 3 / 4) and self.opts.mode == "smart" then
      show_diff = false
    end

    if show_diff == true then
      if #hunk.add then
        add(row, hunk)
      end
      if #hunk.remove then
        remove(row, hunk)
      end
    elseif #hunk.add > 0 and #hunk.remove == 0 then
      add(row, hunk)
    elseif #hunk.remove > 0 and #hunk.add == 0 then
      remove(row, hunk)
    else
      change(row, hunk)
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
  self.shortcircuit = false
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

function DiffWriter:start()
  self.active = true
  self.shortcircuit = false
end

function DiffWriter:stop()
  self.shortcircuit = true
end

return DiffWriter
