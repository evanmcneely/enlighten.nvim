local M = {}

---@param buffer number
---@return Position
function M.get_selection_range(buffer)
	-- Get column and row from for the start of the selection range.
	local start_pos = vim.api.nvim_buf_get_mark(buffer, "<")
	local row_start = start_pos[1] - 1 -- adjust for lua's 1 based indexing
	local col_start = start_pos[2]

	-- Get the column and row for the end of the selection range.
	local end_pos = vim.api.nvim_buf_get_mark(buffer, ">")
	local row_end = end_pos[1] - 1 -- adjust for lua's 1 based indexing
	-- Look at the actual content of the line at the end row.
	-- If the line is empty, set col_end to zero. Otherwise, compute
	-- col_end via the byte index in the string, considering any multi-byte
	-- characters if present.
	local line = vim.fn.getline(end_pos[1])
	local col_end
	if line == "" then
		col_end = 0
	else
		col_end = vim.fn.byteidx(line, vim.fn.charcol("'>"))
	end

	-- Adjustments to ensure column start and end do not exceed the actual length of the line.
	local start_line_length = vim.api.nvim_buf_get_lines(buffer, row_start, row_start + 1, true)[1]:len()
	col_start = math.min(col_start, start_line_length)
	local end_line_length = vim.api.nvim_buf_get_lines(buffer, row_end, row_end + 1, true)[1]:len()
	col_end = math.min(col_end, end_line_length)

	return { col_start = col_start, col_end = col_end, row_start = row_start, row_end = row_end }
end

---@param buffer number
---@return Position
function M.get_cursor_position(buffer)
	-- Get column and row from for the cursor position.
	local start_pos = vim.api.nvim_win_get_cursor(0)
	local row_start = start_pos[1] - 1 -- adjust for lua's 1 based indexing
	-- Look at the actual content of the line at start position.
	-- If the line is empty, set col_end to zero. Otherwise, compute
	-- col_end via the byte index in the string, considering any multi-byte
	-- characters if present.
	local line = vim.fn.getline(start_pos[1])
	local col_start
	if line == "" then
		col_start = 0
	else
		col_start = vim.fn.byteidx(line, vim.fn.charcol("."))
	end

	-- Start and end values are the same.
	local col_end = col_start
	local row_end = row_start

	-- Adjustments to ensure column start and end do not exceed the actual length of the line.
	local start_line_length = vim.api.nvim_buf_get_lines(buffer, row_start, row_start + 1, true)[1]:len()
	col_start = math.min(col_start, start_line_length)
	local end_line_length = vim.api.nvim_buf_get_lines(buffer, row_end, row_end + 1, true)[1]:len()
	col_end = math.min(col_end, end_line_length)

	return { col_start = col_start, col_end = col_end, row_start = row_start, row_end = row_end }
end

---@param buffer number
---@return string
function M.get_file_extension(buffer)
	local filename = vim.api.nvim_buf_get_name(buffer)
	return filename:match("^.+(%..+)$")
end

return M
