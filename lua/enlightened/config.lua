local M = {}

---@param name string
---@param default_value unknown
---@return unknown
local function get_var(name, default_value)
	local value = vim.g[name]
	if value == nil then
		return default_value
	end
	return value
end

M.completions_model = get_var("ai_completions_model", "gpt-3.5-turbo-instruct")
M.edits_model = get_var("ai_edits_model", "text-davinci-edit-001")
M.temperature = get_var("ai_temperature", 0)
M.context_before = get_var("ai_context_before", 20)
M.context_after = get_var("ai_context_after", 20)
M.timeout = get_var("ai_timeout", 60)

return M
