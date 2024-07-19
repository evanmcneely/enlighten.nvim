local ai = require("enlighten/ai")
local buffer = require("enlighten/buffer")
local Writer = require("enlighten/writer/stream")
local group = require("enlighten/autocmd")
local Logger = require("enlighten/logger")
local utils = require("enlighten/utils")

---@class EnlightenChat
---@field prompt_buf number
---@field prompt_win number
---@field chat_buf number
---@field chat_win number
---@field target_buf number
---@field target_range Range
local EnlightenChat = {}

---@return EnlightenChat
function EnlightenChat:new()
	self.__index = self

	local buf = vim.api.nvim_get_current_buf()
	local range = buffer.get_range()
	local snippet = buffer.get_content(buf, range.row_start, range.row_end + 1)
	local chat_win = self:_create_chat_window()
	local prompt_win = self:_create_prompt_window(chat_win.win_id, snippet)

	self.prompt_win = prompt_win.win_id
	self.prompt_buf = prompt_win.bufnr
	self.chat_buf = chat_win.bufnr
	self.chat_win = chat_win.win_id
	self.target_buf = buf

	self:_set_prompt_keymaps()
	self:_set_chat_keymaps()
	vim.cmd("startinsert")

	return self
end

function EnlightenChat:close()
	if vim.api.nvim_win_is_valid(self.prompt_win) then
		Logger:log("chat:close - closing window", { prompt_win = self.prompt_win })
		vim.api.nvim_win_close(self.prompt_win, true)
	end

	if vim.api.nvim_buf_is_valid(self.prompt_buf) then
		Logger:log("chat:close - deleting buffer", { prompt_buf = self.prompt_buf })
		vim.api.nvim_buf_delete(self.prompt_buf, { force = true })
	end

	if vim.api.nvim_win_is_valid(self.chat_win) then
		Logger:log("chat:close - closing window", { chat_win = self.chat_win })
		vim.api.nvim_win_close(self.chat_win, true)
	end

	if vim.api.nvim_buf_is_valid(self.chat_buf) then
		Logger:log("chat:close - deleting buffer", { chat_buf = self.chat_buf })
		vim.api.nvim_buf_delete(self.chat_buf, { force = true })
	end
end

---@param snippet string
---@return { bufnr:number, win_id:number }
function EnlightenChat:_create_prompt_window(chat_win, snippet)
	Logger:log("prompt:_create_prompt_window - creating window")

	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "win",
		win = chat_win,
		width = vim.api.nvim_win_get_width(chat_win),
		height = 6,
		row = vim.api.nvim_win_get_height(chat_win) - 6,
		col = 0,
		anchor = "NW",
		border = "single",
		title = "Prompt",
	})

	vim.api.nvim_set_option_value("number", false, { win = win })
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_name(buf, "enlighten-prompt")
	vim.api.nvim_buf_set_option(buf, "filetype", "enlighten")
	vim.api.nvim_buf_set_option(buf, "wrap", true)

	-- Prepopulate the prompt with the snippet text and pad the
	-- bottom with new lines. Reposition the cursor to last line.
	local lines = utils.split(snippet, "\n")
	table.insert(lines, "")
	table.insert(lines, "")
	vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
	vim.api.nvim_win_set_cursor(win, { #lines, 1 })

	Logger:log("chat:_create_prompt_window - window and buffer", { win = win, buf = buf })

	return {
		bufnr = buf,
		win_id = win,
	}
end

---@return { bufnr:number, win_id:number }
function EnlightenChat:_create_chat_window()
	Logger:log("prompt:_create_chat_window - creating window")

	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		width = 70,
		vertical = true,
		split = "right",
		style = "minimal",
	})

	vim.api.nvim_set_option_value("number", false, { win = win })
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_name(buf, "enlighten-chat")
	vim.api.nvim_buf_set_option(buf, "filetype", "enlighten")
	vim.api.nvim_buf_set_option(buf, "wrap", true)

	Logger:log("chat:_create_chat_window - window and buffer", { win = win, buf = buf })

	return {
		bufnr = buf,
		win_id = win,
	}
end

function EnlightenChat:focus()
	if vim.api.nvim_buf_is_valid(self.prompt_buf) and vim.api.nvim_win_is_valid(self.prompt_win) then
		Logger:log("chat:focus - focusing", { prompt_buf = self.prompt_buf, prompt_win = self.prompt_win })
		vim.api.nvim_set_current_win(self.prompt_win)
		vim.api.nvim_win_set_buf(self.prompt_win, self.prompt_buf)
	end
end

function EnlightenChat:_set_prompt_keymaps()
	vim.api.nvim_buf_set_keymap(self.prompt_buf, "n", "<CR>", "<Cmd>lua require('enlighten').chat:submit()<CR>", {})
	vim.api.nvim_buf_set_keymap(self.prompt_buf, "n", "q", "<Cmd>lua require('enlighten'):close_chat()<CR>", {})
	vim.api.nvim_buf_set_keymap(self.prompt_buf, "n", "<ESC>", "<Cmd>lua require('enlighten'):close_chat()<CR>", {})
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

function EnlightenChat:_set_chat_keymaps()
	vim.api.nvim_buf_set_keymap(self.chat_buf, "n", "q", "<Cmd>lua require('enlighten'):close_chat()<CR>", {})
	vim.api.nvim_buf_set_keymap(self.chat_buf, "n", "<ESC>", "<Cmd>lua require('enlighten'):close_chat()<CR>", {})
	vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWinLeave" }, {
		callback = function()
			if vim.api.nvim_buf_is_valid(self.chat_buf) and vim.api.nvim_win_is_valid(self.chat_win) then
				-- pcall necessary to avoid erroring with `mark not set` although no mark are set
				-- this avoid other issues
				-- TODO: error persists...
				pcall(vim.api.nvim_win_set_buf, self.chat_win, self.chat_buf)
			end
		end,
		group = group,
	})
end

---@return string
function EnlightenChat:_build_prompt()
	local prompt = buffer.get_content(self.chat_buf, 0, -1)
	return "Continue this conversation. Be concise Most recent message is at the bottom...\n\n" .. prompt
end

---@param from number
---@param to number
function EnlightenChat:_move_content(from, to)
	local prompt = buffer.get_lines(from, 0, -1)
	vim.api.nvim_buf_set_lines(from, 0, #prompt + 1, false, {})
	vim.api.nvim_buf_set_lines(to, -1, -1, false, prompt)
end

function EnlightenChat:_add_chat_break()
	vim.api.nvim_buf_set_lines(self.chat_buf, -1, -1, true, { "", "---", "" })
end

function EnlightenChat:_add_user()
	vim.api.nvim_buf_set_lines(self.chat_buf, -1, -1, true, { "Developer:", "" })
end

function EnlightenChat:_add_assistant()
	vim.api.nvim_buf_set_lines(self.chat_buf, -1, -1, true, { "Assistant:", "" })
end

function EnlightenChat:_on_line(line)
	if vim.api.nvim_buf_is_valid(self.chat_buf) then
		vim.api.nvim_buf_set_lines(self.chat_buf, -1, -1, false, { line })
	end
end

function EnlightenChat:submit()
	if
		vim.api.nvim_buf_is_valid(self.prompt_buf)
		and vim.api.nvim_win_is_valid(self.prompt_win)
		and vim.api.nvim_buf_is_valid(self.target_buf)
	then
		Logger:log("chat:submit - let's go")
		self:_add_user()
		self:_move_content(self.prompt_buf, self.chat_buf)
		self:_add_chat_break()
		self:_add_assistant()

		local chat_lines = buffer.get_lines(self.chat_buf, 0, -1)
		local writer = Writer:new(self.chat_buf, { #chat_lines, 0 })
		local prompt = self:_build_prompt()

		ai.chat(prompt, writer)
	end
end

return EnlightenChat
