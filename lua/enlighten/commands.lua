local M = {}

local ai = require("enlighten/ai")
local config = require("enlighten/config")
local Writer = require("enlighten/writer")
local utils = require("enlighten/utils")

---@param args { args: string, range: integer }
function M.ai(args)
	local prompt = args.args
	local selection = args.range > 0
	local buffer = vim.api.nvim_get_current_buf()

	local range

	if selection then
		range = utils.get_selection_range(buffer)
	else
		range = utils.get_cursor_position(buffer)
	end

	local writer = Writer:new(buffer, range)
	local file = utils.get_file_extension(buffer)

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

	if selection then
		local selected_text = table.concat(
			vim.api.nvim_buf_get_text(buffer, range.row_start, range.col_start, range.row_end, range.col_end, {}),
			"\n"
		)
		if prompt == "" then
			-- Replace the selected text, also using it as a prompt
			ai.complete(
				"File extension of the buffer is "
					.. file
					.. ". Rewrite this code for simplicity and clarity:\n\n"
					.. selected_text,
				writer
			)
		else
			-- Edit selected text
			ai.complete(
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
			-- Insert some text to complete surrounding text
			ai.complete(
				"File extension of the buffer is "
					.. file
					.. ". Write the code that completes the snippet below at the line -- insert here --. Don't repeat the code before or after this line.\n\n"
					.. prefix
					.. "\n-- insert here --\n"
					.. suffix,
				writer
			)
		else
			-- Insert some text generated using the given prompt
			ai.complete(
				"File extension of the buffer is "
					.. file
					.. ". Write the code for these instructions: "
					.. prompt
					.. "\n\nHere is the code before the cursor\n"
					.. prefix
					.. "\n\n...and here is the code after the cursor\n"
					.. suffix,
				writer
			)
		end
	end
end

return M
