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

M.indicator_style = get_var("ai_indicator_style", "sign")
M.indicator_text = get_var("ai_indicator_text", "🤖")
M.completions_model = get_var("ai_completions_model", "gpt-4o")
M.temperature = get_var("ai_temperature", 0)
M.context_before = get_var("ai_context_before", 20)
M.context_after = get_var("ai_context_after", 20)
M.timeout = get_var("ai_timeout", 60)
M.tokens = get_var("ai_tokens", 4096)

return M
