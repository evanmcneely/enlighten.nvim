local ai = require("enlighten/ai")
local utils = require("enlighten/utils")
local Writer = require("enlighten/writer")

---@type number | nil
Enlighten_buf_id = nil
---@type number | nil
Enlighten_win_id = nil
---@type number | nil
Enlighten_target_buf_id = nil
---@type Range | nil
Enlighten_target_range = nil

local M = {}

local function close_window()
	if Enlighten_win_id then
		vim.api.nvim_win_close(Enlighten_win_id, true)
	end
	if Enlighten_buf_id then
		vim.api.nvim_buf_delete(Enlighten_buf_id, {})
	end
	Enlighten_win_id = nil
	Enlighten_buf_id = nil
	Enlighten_target_buf_id = nil
	Enlighten_target_range = nil
end

---@param range Range
---@return { bufnr:number, win_id:number }
local function create_window(range)
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "win",
		width = 70,
		height = 3,
		bufpos = { range.row_start, 0 }, -- setting column position here was not effective
		col = 70, -- trial-and-error getting the window out of the sign column
		anchor = "SE",
		border = "single",
		title = "Prompt",
	})
	vim.api.nvim_set_option_value("number", false, { win = win })
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_name(buf, "enlighten-prompt")
	vim.api.nvim_buf_set_option(buf, "filetype", "enlighten")

	return {
		bufnr = buf,
		win_id = win,
	}
end

function M.focus_prompt_window()
	if Enlighten_win_id and Enlighten_buf_id then
		vim.api.nvim_set_current_win(Enlighten_win_id)
		vim.api.nvim_win_set_buf(Enlighten_win_id, Enlighten_buf_id)
		vim.cmd("startinsert")
	end
end

local function sticky_buffer()
	if Enlighten_win_id and Enlighten_buf_id then
		-- pcall necessary to avoid erroring with `mark not set` although no mark are set
		-- this avoid other issues
		-- TODO: error persists...
		pcall(vim.api.nvim_win_set_buf, Enlighten_win_id, Enlighten_buf_id)
	end
end

function M.toggle_prompt_window()
	if Enlighten_win_id ~= nil and vim.api.nvim_win_is_valid(Enlighten_win_id) then
		close_window()
		return
	end

	local buffer = vim.api.nvim_get_current_buf()
	local range = utils.get_range()
	local prompt_win = create_window(range)

	Enlighten_target_buf_id = buffer
	Enlighten_target_range = range
	Enlighten_win_id = prompt_win.win_id
	Enlighten_buf_id = prompt_win.bufnr

	vim.api.nvim_buf_set_keymap(Enlighten_buf_id, "n", "<CR>", "<Cmd>lua require('enlighten.ui').submit()<CR>", {})
	vim.api.nvim_buf_set_keymap(
		Enlighten_buf_id,
		"n",
		"q",
		"<Cmd>lua require('enlighten.ui').toggle_prompt_window()<CR>",
		{}
	)
	vim.api.nvim_buf_set_keymap(
		Enlighten_buf_id,
		"n",
		"<ESC>",
		"<Cmd>lua require('enlighten.ui').toggle_prompt_window()<CR>",
		{}
	)
	local group = vim.api.nvim_create_augroup("EnlightenPromptBuffer", {})
	vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWinLeave" }, {
		callback = function()
			sticky_buffer()
		end,
		group = group,
	})
	vim.cmd("startinsert")
end

local function build_prompt()
	if Enlighten_target_buf_id == nil or Enlighten_target_range == nil or Enlighten_buf_id == nil then
		return
	end

	local prompt = table.concat(vim.api.nvim_buf_get_lines(Enlighten_buf_id, 0, -1, false), "\n")
	local text = table.concat(
		vim.api.nvim_buf_get_lines(
			Enlighten_target_buf_id,
			Enlighten_target_range.row_start,
			Enlighten_target_range.row_end + 1,
			false
		),
		"\n"
	)
	local file_ext = utils.get_file_extension(Enlighten_target_buf_id)
	return "File extension of the buffer is "
		.. file_ext
		.. "\n"
		.. "Rewrite this code following these instructions: "
		.. prompt
		.. "\n"
		.. "\n"
		.. text
end

function M.submit()
	if Enlighten_target_buf_id == nil or Enlighten_target_range == nil then
		return
	end
	local writer = Writer:new(Enlighten_target_buf_id, Enlighten_target_range)
	local prompt = build_prompt()
	print("prompt:\n", prompt)
	if prompt then
		ai.complete(prompt, writer)
	end
end

return M
