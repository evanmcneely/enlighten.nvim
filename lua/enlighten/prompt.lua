local api = vim.api
local utils = require("enlighten/utils")
local buffer = require("enlighten/buffer")
local Writer = require("enlighten/writer/diff")
local group = require("enlighten/autocmd")
local Logger = require("enlighten/logger")

---@class EnlightenPrompt
---@field settings EnlightenPromptSettings
---@field prompt_buf number
---@field prompt_win number
---@field target_buf number
---@field target_range Range
local EnlightenPrompt = {}

---@param ai AI
---@param settings EnlightenPromptSettings
---@return EnlightenPrompt
function EnlightenPrompt:new(ai, settings)
	self.__index = self

	local buf = api.nvim_get_current_buf()
	local range = buffer.get_range()
	local prompt_win = self:_create_window(range, settings)

	self.ai = ai
	self.settings = settings
	self.prompt_win = prompt_win.win_id
	self.prompt_buf = prompt_win.bufnr
	self.target_buf = buf
	self.target_range = range

	self:_set_prompt_keymaps()
	vim.cmd("startinsert")

	return self
end

function EnlightenPrompt:close()
	if api.nvim_win_is_valid(self.prompt_win) then
		Logger:log("prompt:close - closing window", { prompt_win = self.prompt_win })
		api.nvim_win_close(self.prompt_win, true)
	end

	if api.nvim_buf_is_valid(self.prompt_buf) then
		Logger:log("prompt:close - deleting buffer", { prompt_buf = self.prompt_buf })
		api.nvim_buf_delete(self.prompt_buf, { force = true })
	end
end

---@param range Range
---@param settings EnlightenPromptSettings
---@return { bufnr:number, win_id:number }
function EnlightenPrompt:_create_window(range, settings)
	Logger:log("prompt:_create_window - creating window", { range = range })

	local buf = api.nvim_create_buf(false, true)
	local win = api.nvim_open_win(buf, true, {
		relative = "win",
		width = settings.width,
		height = settings.height,
		bufpos = { range.row_start, 0 },
		anchor = "SW",
		border = "single",
		title = "Prompt",
	})

	api.nvim_set_option_value("number", false, { win = win })
	api.nvim_set_option_value("signcolumn", "no", { win = win })
	api.nvim_buf_set_option(buf, "buftype", "nofile")
	api.nvim_buf_set_name(buf, "enlighten-prompt")
	api.nvim_buf_set_option(buf, "filetype", "enlighten")
	api.nvim_buf_set_option(buf, "wrap", true)

	Logger:log("prompt:_create_window - window and buffer", { win = win, buf = buf })

	return {
		bufnr = buf,
		win_id = win,
	}
end

function EnlightenPrompt:focus()
	if api.nvim_buf_is_valid(self.prompt_buf) and api.nvim_win_is_valid(self.prompt_win) then
		Logger:log("prompt:focus - focusing", { prompt_buf = self.prompt_buf, prompt_win = self.prompt_win })
		api.nvim_set_current_win(self.prompt_win)
		api.nvim_win_set_buf(self.prompt_win, self.prompt_buf)
	end
end

function EnlightenPrompt:_set_prompt_keymaps()
	api.nvim_buf_set_keymap(self.prompt_buf, "n", "<CR>", "<Cmd>lua require('enlighten').prompt:submit()<CR>", {})
	api.nvim_buf_set_keymap(self.prompt_buf, "n", "q", "<Cmd>lua require('enlighten'):close_prompt()<CR>", {})
	api.nvim_buf_set_keymap(self.prompt_buf, "n", "<ESC>", "<Cmd>lua require('enlighten'):close_prompt()<CR>", {})
	api.nvim_create_autocmd({ "BufWinEnter", "BufWinLeave" }, {
		callback = function()
			utils.sticky_buffer(self.prompt_buf, self.prompt_win)
		end,
		group = group,
	})
end

---@return string
function EnlightenPrompt:_build_prompt()
	local prompt = buffer.get_content(self.prompt_buf)
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
		api.nvim_buf_is_valid(self.prompt_buf)
		and api.nvim_win_is_valid(self.prompt_win)
		and api.nvim_buf_is_valid(self.target_buf)
	then
		Logger:log("prompt:submit - let's go")
		local prompt = self:_build_prompt()
		local writer = Writer:new(self.target_buf, self.target_range)
		self.ai:complete(prompt, writer)
	end
end

return EnlightenPrompt
