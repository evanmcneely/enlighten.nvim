local api = vim.api
local Logger = require("enlighten/logger")
local utils = require("enlighten/utils")

---@class Writer
---@field buffer number
---@field on_complete fun(self: DiffWriter, err: string?): nil
---@field on_data fun(self: DiffWriter, data: OpenAIStreamingResponse): nil
---@field on_done fun(): nil

---@class DiffWriter: Writer
---@field range Range
---@field accumulated_text string -- stores all accumulated text
---@field accumulated_line string -- stores text of the current line before it added to the buffer
---@field focused_line number -- the current line in the buffer we are ready to write too
---@field ns_id number
DiffWriter = {}

---@class Range
---@field col_start number
---@field row_start number
---@field col_end number
---@field row_end number

---@param buffer number
---@param range Range
---@param on_done? fun():nil
---@return DiffWriter
function DiffWriter:new(buffer, range, on_done)
	local ns_id = api.nvim_create_namespace("Enlighten")
	Logger:log("diff:new", { buffer = buffer, range = range, ns_id = ns_id })

	self.__index = self
	return setmetatable({
		buffer = buffer,
		range = range,
		accumulated_text = "",
		accumulated_line = "",
		focused_line = range.row_start,
		ns_id = ns_id,
		on_done = on_done,
	}, self)
end

---@param data OpenAIStreamingResponse
function DiffWriter:on_data(data)
	local completion = data.choices[1]

	if completion.finish_reason == vim.NIL then
		local text = completion.delta.content
		self.accumulated_line = self.accumulated_line .. text
		self.accumulated_text = self.accumulated_text .. text

		local lines = utils.split(self.accumulated_line, "\n")

		-- Lines having a length greater than 1 indicates that there are
		-- complete lines ready to be set in the buffer. We set all of them
		-- before resetting our current accumulated_line to the last line
		-- in the table._by_new_line(self.accumulated_line)
		if #lines > 1 then
			-- Skip last line as it is not complete yet
			for i = 1, #lines - 1 do
				self:set_line(lines[i])
				self.focused_line = self.focused_line + 1
			end
			self.accumulated_line = lines[#lines]
		end
	end
end

function DiffWriter:on_complete(err)
	if err then
		Logger:log("diff:on_complete - error", err)
		api.nvim_err_writeln("Enlighten: " .. err)
		return
	end

	self:set_line(self.accumulated_line)
	self.accumulated_line = ""
	self:finish()
	if self.on_done ~= nil then
		self:on_done()
	end

	Logger:log("diff:on_complete - ai completion", self.accumulated_text)
end

---@param line string
function DiffWriter:set_line(line)
	-- We want to replace existing text at the focused line if the command is run on
	-- a selection and fewer lines have been written than than the selection. The
	-- behaviour of nvim_buf_set_lines is controlled in this case by incrementing the
	-- focused line number by one to trigger replacement instead of insertion.
	local set_lines = self.focused_line - self.range.row_start
	local selected_lines = self.range.row_end - self.range.row_start
	local replace_focused_line = self:is_selection() and set_lines <= selected_lines
	local end_line = self.focused_line + (replace_focused_line and 1 or 0)

	Logger:log(
		"diff:set_line - setting line",
		{ line = line, num = self.focused_line, replacing = replace_focused_line }
	)

	api.nvim_buf_set_lines(self.buffer, self.focused_line, end_line, false, { line })
end

function DiffWriter:finish()
	if self:is_selection() then
		-- If we set fewer lines were in the original selection
		-- we need to delete the remaining lines so only the set ones remain.
		local set_lines = self.focused_line - self.range.row_start
		local selected_lines = self.range.row_end - self.range.row_start
		if set_lines < selected_lines then
			Logger:log("diff:finish - removing lines", { first = self.focused_line + 1, last = self.range.row_end + 1 })
			api.nvim_buf_set_lines(self.buffer, self.focused_line + 1, self.range.row_end + 1, false, {})
		end
	end
end

---@return boolean
function DiffWriter:is_selection()
	-- Only consider selections over multiple lines
	return self.range.row_start ~= self.range.row_end
end

return DiffWriter
