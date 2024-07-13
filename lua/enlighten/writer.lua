Writer = {}

---@class Writer
---@field buffer number
---@field col_start number
---@field row_start number
---@field col_end number
---@field row_end number
---@field accumulated_text string -- stores all accumulated text
---@field accumulated_line string -- stores text of the current line before it added to the buffer
---@field focused_line number -- the current line in the buffer we are ready to write too
---@field ns_id number
---@field on_complete fun(self: Writer, err: string?): nil
---@field on_data fun(self: Writer, data: OpenAIStreamingResponse): nil

---@class Position
---@field col_start number
---@field row_start number
---@field col_end number
---@field row_end number

---@param buffer number
---@param range Position
---@return Writer
function Writer:new(buffer, range)
	local ns_id = vim.api.nvim_create_namespace("Enlighten")

	self.__index = self
	return setmetatable({
		buffer = buffer,
		col_start = range.col_start,
		row_start = range.row_start,
		col_end = range.col_end,
		row_end = range.row_end,
		accumulated_text = "",
		accumulated_line = "",
		focused_line = range.row_start,
		ns_id = ns_id,
	}, self)
end

---@param data OpenAIStreamingResponse
function Writer:on_data(data)
	local completion = data.choices[1]
	if completion.finish_reason == vim.NIL then
		local text = completion.delta.content
		self.accumulated_line = self.accumulated_line .. text
		self.accumulated_text = self.accumulated_text .. text
		local lines = self.split_by_new_line(self.accumulated_line)
		-- Lines having a length greater than 1 indicates that there are
		-- complete lines ready to be set in the buffer. We set all of them
		-- before resetting our current accumulated_line to the last line
		-- in the table.
		if #lines > 1 then
			for i, line in ipairs(lines) do
				if i ~= #lines then -- skip last line, it is not yet complete
					self:set_line(line)
					self.focused_line = self.focused_line + 1
				end
			end
			self.accumulated_line = lines[#lines]
		end
	end
end

---@param input string
---@return string[]
function Writer.split_by_new_line(input)
	local result = {}
	-- Matches zero or more characters that are not newline characters optionally
	-- followed by a newline character.
	for line in input:gmatch("([^\n]*)\n?") do
		table.insert(result, line)
	end
	table.remove(result) -- Remove the last element, it's always an empty string
	return result
end

function Writer:on_complete(err)
	if err then
		vim.api.nvim_err_writeln("enlighten.nvim :" .. err)
	else
		-- Set the remaining line before finishing
		self:set_line(self.accumulated_line)
		self.accumulated_line = ""
		self:finish()
	end
end

---@param line string
function Writer:set_line(line)
	-- We want to replace existing text if the command is run on a selection
	-- and insert new text otherwise. The behaviour of nvim_buf_set_lines is
	-- controlled in this case by incrementing the focused line number by one
	-- to trigger replacement instead of insertion.
	local end_line
	if self:is_selection() then
		end_line = self.focused_line + 1
	else
		end_line = self.focused_line
	end
	vim.api.nvim_buf_set_lines(self.buffer, self.focused_line, end_line, false, { line })
end

function Writer:finish()
	if not self:is_selection() then
		return
	end

	-- For selections, if we set fewer lines were in the original selection
	-- we need to delete the remaining lines so only the set ones remain.
	local selection_range = self.row_end - self.row_start
	local set_lines = self.focused_line - self.row_start
	if set_lines < selection_range then
		vim.api.nvim_buf_set_lines(self.buffer, self.focused_line + 1, self.row_end + 1, false, {})
	end
end

---@return boolean
function Writer:is_selection()
	-- Only consider selections over multiple lines
	return self.row_start ~= self.row_end
end

return Writer
