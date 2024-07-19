local api = vim.api
local buffer = require("enlighten/buffer")
local Writer = require("enlighten/writer/stream")
local group = require("enlighten/autocmd")
local Logger = require("enlighten/logger")
local utils = require("enlighten/utils")

---@class EnlightenChat
---@field settings EnlightenConfig
---@field prompt_buf number
---@field prompt_win number
---@field chat_buf number
---@field chat_win number
---@field target_buf number
---@field target_range Range
local EnlightenChat = {}

---@param ai AI
---@param settings EnlightenConfig
---@return EnlightenChat
function EnlightenChat:new(ai, settings)
	self.__index = self

	local buf = api.nvim_get_current_buf()
	local range = buffer.get_range()

	-- Getting the current snippet must occur before we create the buffers
	local snippet
	if buffer.is_visual_mode() then
		snippet = buffer.get_content(buf, range.row_start, range.row_end + 1)
	end

	local chat_win = self:_create_chat_window()
	local prompt_win = self:_create_prompt_window(chat_win.win_id, snippet)

	self.ai = ai
	self.settings = settings
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
	if api.nvim_win_is_valid(self.prompt_win) then
		Logger:log("chat:close - closing window", { prompt_win = self.prompt_win })
		api.nvim_win_close(self.prompt_win, true)
	end

	if api.nvim_buf_is_valid(self.prompt_buf) then
		Logger:log("chat:close - deleting buffer", { prompt_buf = self.prompt_buf })
		api.nvim_buf_delete(self.prompt_buf, { force = true })
	end

	if api.nvim_win_is_valid(self.chat_win) then
		Logger:log("chat:close - closing window", { chat_win = self.chat_win })
		api.nvim_win_close(self.chat_win, true)
	end

	if api.nvim_buf_is_valid(self.chat_buf) then
		Logger:log("chat:close - deleting buffer", { chat_buf = self.chat_buf })
		api.nvim_buf_delete(self.chat_buf, { force = true })
	end
end

---@param chat_win number
---@param snippet? string
---@return { bufnr: number, win_id: number }
function EnlightenChat:_create_prompt_window(chat_win, snippet)
	Logger:log("prompt:_create_prompt_window - creating window")

	local buf = api.nvim_create_buf(false, true)
	local win = api.nvim_open_win(buf, true, {
		relative = "win",
		win = chat_win,
		width = api.nvim_win_get_width(chat_win),
		height = 6,
		row = api.nvim_win_get_height(chat_win) - 6,
		col = 0,
		anchor = "NW",
		border = "single",
		title = "Prompt",
	})

	api.nvim_set_option_value("number", false, { win = win })
	api.nvim_set_option_value("signcolumn", "no", { win = win })
	api.nvim_buf_set_option(buf, "buftype", "nofile")
	api.nvim_buf_set_name(buf, "enlighten-prompt")
	api.nvim_buf_set_option(buf, "filetype", "enlighten")
	api.nvim_buf_set_option(buf, "wrap", true)

	if snippet ~= nil then
		-- Prepopulate the prompt with the snippet text and pad the
		-- bottom with new lines. Reposition the cursor to last line.
		local lines = utils.split(snippet, "\n")
		table.insert(lines, "")
		table.insert(lines, "")
		api.nvim_buf_set_lines(buf, 0, -1, true, lines)
		api.nvim_win_set_cursor(win, { #lines, 1 })
	end

	Logger:log("chat:_create_prompt_window - window and buffer", { win = win, buf = buf })

	return {
		bufnr = buf,
		win_id = win,
	}
end

---@return { bufnr: number, win_id: number }
function EnlightenChat:_create_chat_window()
	Logger:log("prompt:_create_chat_window - creating window")

	local buf = api.nvim_create_buf(false, true)
	local win = api.nvim_open_win(buf, true, {
		width = 70,
		vertical = true,
		split = "right",
		style = "minimal",
	})

	api.nvim_set_option_value("number", false, { win = win })
	api.nvim_set_option_value("signcolumn", "no", { win = win })
	api.nvim_buf_set_option(buf, "buftype", "nofile")
	api.nvim_buf_set_name(buf, "enlighten-chat")
	api.nvim_buf_set_option(buf, "filetype", "enlighten")
	api.nvim_buf_set_option(buf, "wrap", true)

	Logger:log("chat:_create_chat_window - window and buffer", { win = win, buf = buf })

	return {
		bufnr = buf,
		win_id = win,
	}
end

function EnlightenChat:focus()
	if api.nvim_buf_is_valid(self.prompt_buf) and api.nvim_win_is_valid(self.prompt_win) then
		Logger:log("chat:focus - focusing", { prompt_buf = self.prompt_buf, prompt_win = self.prompt_win })
		api.nvim_set_current_win(self.prompt_win)
		api.nvim_win_set_buf(self.prompt_win, self.prompt_buf)
	end
end

function EnlightenChat:_set_prompt_keymaps()
	api.nvim_buf_set_keymap(self.prompt_buf, "n", "<CR>", "<Cmd>lua require('enlighten').chat:submit()<CR>", {})
	api.nvim_buf_set_keymap(self.prompt_buf, "n", "q", "<Cmd>lua require('enlighten'):close_chat()<CR>", {})
	api.nvim_buf_set_keymap(self.prompt_buf, "n", "<ESC>", "<Cmd>lua require('enlighten'):close_chat()<CR>", {})
	api.nvim_create_autocmd({ "BufWinEnter", "BufWinLeave" }, {
		callback = function()
			utils.sticky_buffer(self.prompt_buf, self.prompt_win)
		end,
		group = group,
	})
end

function EnlightenChat:_set_chat_keymaps()
	api.nvim_buf_set_keymap(self.chat_buf, "n", "q", "<Cmd>lua require('enlighten'):close_chat()<CR>", {})
	api.nvim_buf_set_keymap(self.chat_buf, "n", "<ESC>", "<Cmd>lua require('enlighten'):close_chat()<CR>", {})
	api.nvim_create_autocmd({ "BufWinEnter", "BufWinLeave" }, {
		callback = function()
			utils.sticky_buffer(self.chat_buf, self.chat_win)
		end,
		group = group,
	})
end

---@return string
function EnlightenChat:_build_prompt()
	local prompt = buffer.get_content(self.chat_buf)
	return "Continue this conversation. Be concise Most recent message is at the bottom...\n\n" .. prompt
end

---@param from number
---@param to number
function EnlightenChat:_move_content(from, to)
	local prompt = buffer.get_lines(from)
	api.nvim_buf_set_lines(from, 0, #prompt + 1, false, {})
	api.nvim_buf_set_lines(to, -1, -1, false, prompt)
end

function EnlightenChat:_add_chat_break()
	api.nvim_buf_set_lines(self.chat_buf, -1, -1, true, { "", "---", "" })
end

function EnlightenChat:_add_user()
	local lines = buffer.get_lines(self.chat_buf)
	if #lines > 1 then
		self:_add_chat_break()
	end
	api.nvim_buf_set_lines(self.chat_buf, -1, -1, true, { "Developer:", "", "" })
end

function EnlightenChat:_add_assistant()
	api.nvim_buf_set_lines(self.chat_buf, -1, -1, true, { "Assistant:", "", "" })
end

function EnlightenChat:_on_line(line)
	if api.nvim_buf_is_valid(self.chat_buf) then
		api.nvim_buf_set_lines(self.chat_buf, -1, -1, false, { line })
	end
end

function EnlightenChat:submit()
	if
		api.nvim_buf_is_valid(self.prompt_buf)
		and api.nvim_win_is_valid(self.prompt_win)
		and api.nvim_buf_is_valid(self.target_buf)
	then
		Logger:log("chat:submit - let's go")
		self:_add_user()
		self:_move_content(self.prompt_buf, self.chat_buf)
		self:_add_chat_break()
		self:_add_assistant()

		local prompt = self:_build_prompt()
		local chat_lines = buffer.get_lines(self.chat_buf)
		local writer = Writer:new(self.chat_buf, { #chat_lines, 0 })
		self.ai:complete(prompt, writer)
	end
end

return EnlightenChat
