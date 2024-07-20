local api = vim.api
local buffer = require("enlighten/buffer")
local Writer = require("enlighten/writer/stream")
local group = require("enlighten/autocmd")
local Logger = require("enlighten/logger")
local utils = require("enlighten/utils")

---@class EnlightenChat
---@field settings EnlightenChatSettings
---@field chat_buf number
---@field chat_win number
---@field target_buf number
---@field target_range Range
local EnlightenChat = {}

---@param ai AI
---@param settings EnlightenChatSettings
---@return EnlightenChat
function EnlightenChat:new(ai, settings)
	self.__index = self

	local buf = api.nvim_get_current_buf()
	local range = buffer.get_range()

	-- Getting the current snippet must occur before we create the buffers
	local snippet
	if buffer.is_visual_mode() then
		snippet = buffer.get_lines(buf, range.row_start, range.row_end + 1)
	end

	local chat_win = self:_create_chat_window(settings)

	self.ai = ai
	self.settings = settings
	self.chat_buf = chat_win.bufnr
	self.chat_win = chat_win.win_id
	self.target_buf = buf

	self:_set_chat_keymaps()
	self:_add_user(snippet)

	vim.cmd("startinsert")

	return self
end

function EnlightenChat:close()
	if api.nvim_win_is_valid(self.chat_win) then
		Logger:log("chat:close - closing window", { chat_win = self.chat_win })
		api.nvim_win_close(self.chat_win, true)
	end

	if api.nvim_buf_is_valid(self.chat_buf) then
		Logger:log("chat:close - deleting buffer", { chat_buf = self.chat_buf })
		api.nvim_buf_delete(self.chat_buf, { force = true })
	end
end

---@param settings EnlightenChatSettings
---@return { bufnr: number, win_id: number }
function EnlightenChat:_create_chat_window(settings)
	Logger:log("prompt:_create_chat_window - creating window")

	local buf = api.nvim_create_buf(false, true)
	local win = api.nvim_open_win(buf, true, {
		width = settings.width,
		vertical = true,
		split = "left",
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
	if api.nvim_buf_is_valid(self.chat_buf) and api.nvim_win_is_valid(self.chat_win) then
		Logger:log("chat:focus - focusing", { buf = self.chat_buf, win = self.chat_win })
		api.nvim_set_current_win(self.chat_win)
		api.nvim_win_set_buf(self.chat_win, self.chat_buf)
	end
end

function EnlightenChat:_set_chat_keymaps()
	api.nvim_buf_set_keymap(self.chat_buf, "n", "<CR>", "<Cmd>lua require('enlighten').chat:submit()<CR>", {})
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
	return "Continue this conversation. Be concise. Most recent message is at the bottom...\n\n" .. prompt
end

---@param from number
---@param to number
function EnlightenChat:_move_content(from, to)
	local prompt = buffer.get_lines(from)
	api.nvim_buf_set_lines(from, 0, #prompt + 1, false, {})
	api.nvim_buf_set_lines(to, -1, -1, false, prompt)
end

---@param snippet? string[]
function EnlightenChat:_add_user(snippet)
	local count = api.nvim_buf_line_count(self.chat_buf)

	if count == 1 then
		local lines = { ">>> Developer", "" }
		if snippet then
			for _, l in pairs(snippet) do
				table.insert(lines, l)
			end
			table.insert(lines, "")
			table.insert(lines, "")
		else
			table.insert(lines, "")
		end
		api.nvim_buf_set_lines(self.chat_buf, -2, -1, true, lines)
	else
		api.nvim_buf_set_lines(self.chat_buf, -1, -1, true, { "", ">>> Developer", "", "" })
	end

	count = api.nvim_buf_line_count(self.chat_buf)
	vim.api.nvim_win_set_cursor(self.chat_win, { count, 0 })
	vim.cmd("startinsert")
end

function EnlightenChat:_add_assistant()
	api.nvim_buf_set_lines(self.chat_buf, -1, -1, true, { "", ">>> Assistant", "", "" })
end

function EnlightenChat:_on_line(line)
	if api.nvim_buf_is_valid(self.chat_buf) then
		api.nvim_buf_set_lines(self.chat_buf, -1, -1, false, { line })
	end
end

function EnlightenChat:submit()
	if
		api.nvim_buf_is_valid(self.chat_buf)
		and api.nvim_win_is_valid(self.chat_win)
		and api.nvim_buf_is_valid(self.target_buf)
	then
		Logger:log("chat:submit - let's go")
		self:_add_assistant()

		local function on_complete()
			self:_add_user()
		end

		local prompt = self:_build_prompt()
		local count = api.nvim_buf_line_count(self.chat_buf)
		local writer = Writer:new(self.chat_buf, { count, 0 }, on_complete)
		self.ai:chat(prompt, writer)
	end
end

return EnlightenChat
