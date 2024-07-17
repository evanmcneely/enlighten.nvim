local ai = require("enlighten/ai")
local buffer = require("enlighten/buffer")
local Writer = require("enlighten/writer")
local group = require("enlighten/autocmd")
local Logger = require("enlighten/logger")

---@class EnlightenPrompt
---@field prompt_buf number
---@field prompt_win number
---@field target_buf number
---@field target_range Range
local EnlightenPrompt = {}

---@return EnlightenPrompt
function EnlightenPrompt:new()
	self.__index = self

	local buf = vim.api.nvim_get_current_buf()
	local range = buffer.get_range()
	local prompt_win = self:_create_window(range)

	self.prompt_win = prompt_win.win_id
	self.prompt_buf = prompt_win.bufnr
	self.target_buf = buf
	self.target_range = range

	self:_set_prompt_keymaps()
	vim.cmd("startinsert")

	return self
end

function EnlightenPrompt:close()
	if vim.api.nvim_win_is_valid(self.prompt_win) then
		Logger:log("prompt:close - closing window", { prompt_win = self.prompt_win })
		vim.api.nvim_win_close(self.prompt_win, true)
	end

	if vim.api.nvim_buf_is_valid(self.prompt_buf) then
		Logger:log("prompt:close - deleting buffer", { prompt_buf = self.prompt_buf })
		vim.api.nvim_buf_delete(self.prompt_buf, { force = true })
	end
end

---@param range Range
---@return { bufnr:number, win_id:number }
function EnlightenPrompt:_create_window(range)
	Logger:log("prompt:_create_window - creating window", { range = range })

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
	vim.api.nvim_buf_set_option(buf, "wrap", true)

	Logger:log("prompt:_create_window - window and buffer", { win = win, buf = buf })

	return {
		bufnr = buf,
		win_id = win,
	}
end

function EnlightenPrompt:focus()
	if vim.api.nvim_buf_is_valid(self.prompt_buf) and vim.api.nvim_win_is_valid(self.prompt_win) then
		Logger:log("prompt:focus - focusing", { prompt_buf = self.prompt_buf, prompt_win = self.prompt_win })
		vim.api.nvim_set_current_win(self.prompt_win)
		vim.api.nvim_win_set_buf(self.prompt_win, self.prompt_buf)
	end
end

function EnlightenPrompt:_set_prompt_keymaps()
	vim.api.nvim_buf_set_keymap(self.prompt_buf, "n", "<CR>", "<Cmd>lua require('enlighten').prompt:submit()<CR>", {})
	vim.api.nvim_buf_set_keymap(self.prompt_buf, "n", "q", "<Cmd>lua require('enlighten'):close_prompt()<CR>", {})
	vim.api.nvim_buf_set_keymap(self.prompt_buf, "n", "<ESC>", "<Cmd>lua require('enlighten'):close_prompt()<CR>", {})
	vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWinLeave" }, {
		callback = function()
			if vim.api.nvim_buf_is_valid(self.prompt_buf) and vim.api.nvim_win_is_valid(self.prompt_win) then
				-- pcall necessary to avoid erroring with `mark not set` although no mark are set
				-- this avoid other issues
				-- TODO: error persists...
				pcall(vim.api.nvim_win_set_buf, self.prompt_win, self.prompt_buf)
			end
		end,
		group = group,
	})
end

---@return string
function EnlightenPrompt:_build_prompt()
	local prompt = buffer.get_content(self.prompt_buf, 0, -1)
	local snippet = buffer.get_content(self.target_buf, self.target_range.row_start, self.target_range.row_end + 1)
	local file_ext = buffer.get_file_extension(self.target_buf)

	return "File extension of the buffer is "
		.. file_ext
		.. "\n"
		.. "Rewrite the following code snippet following these instructions: "
		.. prompt
		.. "\n"
		.. "\n"
		.. snippet
end

function EnlightenPrompt:submit()
	if
		vim.api.nvim_buf_is_valid(self.prompt_buf)
		and vim.api.nvim_win_is_valid(self.prompt_win)
		and vim.api.nvim_buf_is_valid(self.target_buf)
	then
		Logger:log("prompt:submit - let's go")
		local writer = Writer:new(self.target_buf, self.target_range)
		local prompt = self:_build_prompt()
		ai.complete(prompt, writer)
	end
end

return EnlightenPrompt
