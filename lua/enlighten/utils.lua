local M = {}

---@return boolean
local function is_visual_mode()
	local mode = vim.api.nvim_get_mode()
	return string.lower(mode.mode) == "v"
end

---@return Range
function M.get_range()
	if is_visual_mode() then
		return M.get_selection_range()
	end
	return M.get_cursor_position()
end

---@return Range
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

	return { col_start = col_start, col_end = col_end, row_start = row_start, row_end = row_end }
end

---@return Range
function M.get_cursor_position()
	-- Get column and row from for the cursor position.
	local start_pos = vim.api.nvim_win_get_cursor(0)
	local row_start = start_pos[1] - 1 -- adjust for lua's 1 based indexing
	local col_start = start_pos[2]

	-- Start and end values are the same.
	local col_end = col_start
	local row_end = row_start

	return { col_start = col_start, col_end = col_end, row_start = row_start, row_end = row_end }
end

---@param buffer number
---@return string
function M.get_file_extension(buffer)
	local filename = vim.api.nvim_buf_get_name(buffer)
	return filename:match("^.+(%..+)$")
end

---@param str string
function M.trim(str)
	return str:gsub("^%s+", ""):gsub("%s+$", "")
end
function M.remove_duplicate_whitespace(str)
	return str:gsub("%s+", " ")
end

---@param str string
---@param sep string
function M.split(str, sep)
	if sep == nil then
		sep = "%s"
	end
	local t = {}
	for s in string.gmatch(str, "([^" .. sep .. "]+)") do
		table.insert(t, s)
	end
	return t
end

---@param str string
function M.is_white_space(str)
	return str:gsub("%s", "") == ""
end

return M
