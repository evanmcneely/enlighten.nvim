local Logger = require("enlighten/logger")
local utils = require("enlighten/utils")

---@class StreamWriter: Writer
---@field pos number[]
---@field ns_id number
StreamWriter = {}

---@param buffer number
---@param pos number[]
---@return StreamWriter
function StreamWriter:new(buffer, pos)
	local ns_id = vim.api.nvim_create_namespace("Enlighten")
	Logger:log("stream:new", { buffer = buffer, ns_id = ns_id, pos = pos })

	self.__index = self
	return setmetatable({
		buffer = buffer,
		pos = pos,
		accumulated_text = "",
		ns_id = ns_id,
	}, self)
end

---@param data OpenAIStreamingResponse
function StreamWriter:on_data(data)
	local completion = data.choices[1]
	if completion.finish_reason == vim.NIL then
		local text = completion.delta.content
		self.accumulated_text = self.accumulated_text .. text

		local lines = utils.split(text, "\n")

		-- Insert a new line into the buffer and update the position
		local function new_line()
			vim.api.nvim_buf_set_lines(self.buffer, -1, -1, false, { "" })
			self.pos[1] = self.pos[1] + 1
			self.pos[2] = 0
		end

		-- Set the text at the position and update the position
		---@param t string
		local function set_text(t)
			vim.api.nvim_buf_set_text(self.buffer, self.pos[1] - 1, self.pos[2], self.pos[1] - 1, self.pos[2], { t })
			self.pos[2] = self.pos[2] + #t
		end

		-- If there is only one line we can set and move on. Multiple lines
		-- indicate newline characters are in the text and need to be handled
		-- by inserting new lines into the buffer for every line after the one
		if #lines > 1 then
			for i = 1, #lines do
				if i ~= 1 then
					new_line()
				end
				set_text(lines[i])
			end
		elseif lines[1] ~= nil then
			set_text(lines[1])
		end
	end
end

---@param err? string
function StreamWriter:on_complete(err)
	if err then
		Logger:log("stream:on_complete - error", err)
		vim.api.nvim_err_writeln("enlighten :" .. err)
		return
	end

	Logger:log("stream:on_complete - ai completion", self.accumulated_text)
end

return StreamWriter
