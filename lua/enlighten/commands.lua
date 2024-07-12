local M = {}

local openai = require("enlighten/openai")
local config = require("enlighten/config")
local Writer = require("enlighten/writer")

---@param buffer number
---@return Position
local function get_selection_range(buffer)
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

---@return Position
local function get_cursor_position(buffer)
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

---@return string
local function get_file_extension()
	local filename = vim.api.nvim_buf_get_name(0)
	return filename:match("^.+(%..+)$")
end

---@param args { args: string, range: integer }
function M.ai(args)
	local prompt = args.args
	local selection = args.range > 0
	local buffer = vim.api.nvim_get_current_buf()

	local range

	if selection then
		range = get_selection_range(buffer)
	else
		range = get_cursor_position(buffer)
	end

	local writer = Writer:new(buffer, range)
	local file = get_file_extension()

	if selection then
		local selected_text = table.concat(
			vim.api.nvim_buf_get_text(buffer, range.row_start, range.col_start, range.row_end, range.col_end, {}),
			"\n"
		)
		if prompt == "" then
			-- Replace the selected text, also using it as a prompt
			openai.completions(
				"File extension of the buffer is "
					.. file
					.. ". Rewrite this code for simplicity and clarity:"
					.. selected_text,
				writer
			)
		else
			-- Edit selected text
			openai.completions(
				"File extension is of the buffer is "
					.. file
					.. ". Rewrite this code following these instructions: "
					.. prompt
					.. "\n\n"
					.. selected_text,
				writer
			)
		end
	else
		if prompt == "" then
			-- Insert some text generated using surrounding context
			local prefix = table.concat(
				vim.api.nvim_buf_get_text(
					buffer,
					math.max(0, range.row_start - config.context_before),
					0,
					range.row_start,
					range.col_start,
					{}
				),
				"\n"
			)

			local line_count = vim.api.nvim_buf_line_count(buffer)
			local suffix = table.concat(
				vim.api.nvim_buf_get_text(
					buffer,
					range.row_end,
					range.col_end,
					math.min(range.row_end + config.context_after, line_count - 1),
					99999999,
					{}
				),
				"\n"
			)

			openai.completions(
				prefix
					.. "\nWrite code here that completes the snippet."
					.. "File extension of the buffer is "
					.. file
					.. "\n"
					.. suffix,
				writer
			)
		else
			-- Insert some text generated using the given prompt
			openai.completions(
				"File extension of the buffer is " .. file .. ". Write the code for these instructions: " .. prompt,
				writer
			)
		end
	end
end

return M
