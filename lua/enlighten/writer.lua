Writer = {}

---@class Writer
---@field buffer number
---@field col_start number
---@field row_start number
---@field col_end number
---@field row_end number
---@field accumulated_text string
---@field ns_id number
---@field extmark_id number
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

	local extmark_opts = { hl_group = "AIHighlight" }
	if range.row_end ~= range.row_start or range.col_end ~= range.col_start then
		extmark_opts.end_row = range.row_end
		extmark_opts.end_col = range.col_end
	end
	local extmark_id = vim.api.nvim_buf_set_extmark(buffer, ns_id, range.row_start, range.col_start, extmark_opts)

	self.__index = self
	return setmetatable({
		buffer = buffer,
		col_start = range.col_start,
		row_start = range.row_start,
		col_end = range.col_end,
		row_end = range.row_end,
		accumulated_text = "", -- stores text for the current line before it is added to the buffer
		ns_id = ns_id,
		extmark_id = extmark_id,
	}, self)
end

---@param data OpenAIStreamingResponse
function Writer:on_data(data)
	local completion = data.choices[1]
	if completion.finish_reason == vim.NIL then
		print(vim.inspect(completion.delta.content))
		self.accumulated_text = self.accumulated_text .. completion.delta.content
		self:set_preview_text()
	end
end

---@param err string
function Writer:on_complete(err)
	if err then
		vim.api.nvim_err_writeln("enlighten.nvim :" .. err)
	elseif #self.accumulated_text > 0 then
		self:set_buffer_text()
	end
	self:finish()
end

function Writer:set_preview_text()
	local extmark = vim.api.nvim_buf_get_extmark_by_id(self.buffer, self.ns_id, self.extmark_id, { details = true })
	local start_row = extmark[1]
	local start_col = extmark[2]

	if extmark[3].end_row or extmark[3].end_col then
		return -- We don't support preview text over a range
	end

	local extmark_opts = { hl_group = "AIHighlight" }
	extmark_opts.id = self.extmark_id
	extmark_opts.virt_text_pos = "overlay"

	local lines = vim.split(self.accumulated_text, "\n")
	extmark_opts.virt_text = { { lines[1], "Comment" } }

	if #lines > 1 then
		extmark_opts.virt_lines = vim.tbl_map(function(line)
			return { { line, "Comment" } }
		end, vim.list_slice(lines, 2))
	end

	vim.api.nvim_buf_set_extmark(self.buffer, self.ns_id, start_row, start_col, extmark_opts)
end

function Writer:set_buffer_text()
	local extmark = vim.api.nvim_buf_get_extmark_by_id(self.buffer, self.ns_id, self.extmark_id, { details = true })
	local start_row = extmark[1]
	local start_col = extmark[2]

	local end_row = extmark[3].end_row
	if not end_row then
		end_row = start_row
	end

	local end_col = extmark[3].end_col
	if not end_col then
		end_col = start_col
	end

	local lines = vim.split(self.accumulated_text, "\n")
	vim.api.nvim_buf_set_text(self.buffer, start_row, start_col, end_row, end_col, lines)
end

function Writer:finish()
	vim.api.nvim_buf_del_extmark(self.buffer, self.ns_id, self.extmark_id)
end

return Writer
