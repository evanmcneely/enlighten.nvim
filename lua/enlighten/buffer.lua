local api = vim.api

local M = {}

--- Get the selected range (start and end column and row) regardless of
--- whether the user has text text selected. The users cursor position is
--- represented as a range if no text is currently selected.
---@return SelectionRange
function M.get_range()
  if M.is_visual_mode() then
    return M.get_selection_range()
  end
  return M.get_cursor_position()
end

---@return boolean
function M.is_visual_mode()
  local mode = api.nvim_get_mode()
  return string.lower(mode.mode) == "v"
end

---@return SelectionRange
function M.get_selection_range()
  -- Get column and row from for the start of the selection range.
  local start_pos = vim.fn.getpos("v")
  local row_start = start_pos[2] - 1 -- adjust for lua's 1 based indexing
  local col_start = start_pos[3]

  -- Get the column and row for the end of the selection range.
  local end_pos = vim.fn.getpos(".")
  local row_end = end_pos[2] - 1 -- adjust for lua's 1 based indexing
  local col_end = end_pos[3]

  -- Selection range should be the same whether from top-to-bottom or bottom-to-top
  if row_end < row_start or (row_start == row_end and col_end < col_start) then
    local temp_col_end = col_end
    local temp_row_end = row_end
    row_end = row_start
    col_end = col_start
    row_start = temp_row_end
    col_start = temp_col_end
  end

  return {
    col_start = col_start,
    col_end = col_end,
    row_start = row_start,
    row_end = row_end,
  }
end

---@return SelectionRange
function M.get_cursor_position()
  -- Get column and row from for the cursor position.
  local start_pos = api.nvim_win_get_cursor(0)
  local row_start = start_pos[1] - 1 -- adjust for lua's 1 based indexing
  local col_start = start_pos[2]

  -- Start and end values are the same.
  local col_end = col_start
  local row_end = row_start

  return {
    col_start = col_start,
    col_end = col_end,
    row_start = row_start,
    row_end = row_end,
  }
end

---@param buffer number
---@param start? number
---@param finish? number
---@return string[]
function M.get_lines(buffer, start, finish)
  if not start then
    start = 0
  end
  if not finish then
    finish = -1
  end
  return api.nvim_buf_get_lines(buffer, start, finish, false)
end

---@param buffer number
---@param start? number
---@param finish? number
---@return string
function M.get_content(buffer, start, finish)
  return table.concat(M.get_lines(buffer, start, finish), "\n")
end

return M
