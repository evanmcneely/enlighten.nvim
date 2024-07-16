local ai = require("enlighten/ai")
local utils = require("enlighten/utils")
local Writer = require("enlighten/writer")
local group = require("enlighten/autocmd")
local Logger = require("enlighten/logger")

---@class EnlightenUI
---@field prompt_buf number
---@field prompt_win number
---@field target_buf number
---@field target_range Range
local EnlightenUI = {}

---@return EnlightenUI
function EnlightenUI:new()
	self.__index = self
	return setmetatable({
		prompt_win = nil,
		prompt_buf = nil,
		target_buf = nil,
		target_range = nil,
	}, self)
end

function EnlightenUI:close_prompt()
	if self.prompt_win ~= nil and vim.api.nvim_win_is_valid(self.prompt_win) then
		Logger:log("ui:close_prompt - closing window", { prompt_win = self.prompt_win })
		vim.api.nvim_win_close(self.prompt_win, true)
	end

	if self.prompt_buf ~= nil and vim.api.nvim_buf_is_valid(self.prompt_buf) then
		Logger:log("ui:close_prompt - deleting buffer", { prompt_buf = self.prompt_buf })
		vim.api.nvim_buf_delete(self.prompt_buf, { force = true })
	end

	self.prompt_win = nil
	self.prompt_buf = nil
	self.target_buf = nil
	self.target_range = nil
end

---@param range Range
---@return { bufnr:number, win_id:number }
function EnlightenUI:_create_window(range)
	Logger:log("ui:_create_window - creating window", { range = range })

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

	Logger:log("ui:_create_window - window and buffer", { win = win, buf = buf })

	return {
		bufnr = buf,
		win_id = win,
	}
end

function EnlightenUI:focus_prompt()
	if self.prompt_win and self.prompt_buf then
		Logger:log("ui:focus_prompt - focusing", { prompt_buf = self.prompt_buf, prompt_win = self.prompt_win })
		vim.api.nvim_set_current_win(self.prompt_win)
		vim.api.nvim_win_set_buf(self.prompt_win, self.prompt_buf)
	end
end

function EnlightenUI:toggle_prompt()
	if self.prompt_win ~= nil and vim.api.nvim_win_is_valid(self.prompt_win) then
		Logger:log("ui:toggle_prompt - closing window", { prompt_win = self.prompt_win })
		self:close_prompt()
		return
	end

	Logger:log("ui:toggle_prompt - creating window", { visual_mode = utils.is_visual_mode() })
	local buffer = vim.api.nvim_get_current_buf()
	local range = utils.get_range()
	local prompt_win = self:_create_window(range)

	self.target_buf = buffer
	self.target_range = range
	self.prompt_win = prompt_win.win_id
	self.prompt_buf = prompt_win.bufnr

	vim.api.nvim_buf_set_keymap(self.prompt_buf, "n", "<CR>", "<Cmd>lua require('enlighten').ui:submit()<CR>", {})
	vim.api.nvim_buf_set_keymap(self.prompt_buf, "n", "q", "<Cmd>lua require('enlighten').ui:close_prompt()<CR>", {})
	vim.api.nvim_buf_set_keymap(
		self.prompt_buf,
		"n",
		"<ESC>",
		"<Cmd>lua require('enlighten').ui:close_prompt()<CR>",
		{}
	)
	vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWinLeave" }, {
		callback = function()
			if self.prompt_win and self.prompt_buf then
				-- pcall necessary to avoid erroring with `mark not set` although no mark are set
				-- this avoid other issues
				-- TODO: error persists...
				pcall(vim.api.nvim_win_set_buf, self.prompt_win, self.prompt_buf)
			end
		end,
		group = group,
	})
	vim.cmd("startinsert")

	Logger:log("ui:toggle_prompt - done", {
		prompt_win = self.prompt_win,
		prompt_buf = self.prompt_buf,
		target_buf = self.target_buf,
		target_range = self.target_range,
	})
end

function EnlightenUI:build_prompt()
	if self.target_buf == nil or self.target_range == nil or self.prompt_buf == nil then
		Logger:log(
			"ui:build_prompt - invalid state",
			{ target_buf = self.target_buf, target_range = self.target_range, prompt_buf = self.prompt_buf }
		)
		return ""
	end

	local prompt = table.concat(vim.api.nvim_buf_get_lines(self.prompt_buf, 0, -1, false), "\n")
	local text = table.concat(
		vim.api.nvim_buf_get_lines(self.target_buf, self.target_range.row_start, self.target_range.row_end + 1, false),
		"\n"
	)
	local file_ext = utils.get_file_extension(self.target_buf)
	return "File extension of the buffer is "
		.. file_ext
		.. "\n"
		.. "Rewrite this code following these instructions: "
		.. prompt
		.. "\n"
		.. "\n"
		.. text
end

function EnlightenUI:submit()
	if self.target_buf == nil or self.target_range == nil then
		Logger:log("ui:submit - invalid state", { target_buf = self.target_buf, target_range = self.target_range })
		return
	end

	local writer = Writer:new(self.target_buf, self.target_range)
	local prompt = self:build_prompt()
	ai.complete(prompt, writer)
end

return EnlightenUI
