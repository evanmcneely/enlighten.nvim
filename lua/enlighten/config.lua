local M = {}

---@class EnlightenAiConfig
---@field model string
---@field temperature number
---@field context_before number
---@field context_after number
---@field timeout number
---@field tokens number

---@class EnlightPartialAiConfig
---@field model? string
---@field temperature? number
---@field context_before? number
---@field context_after? number
---@field timeout? number
---@field tokens? number

---@class EnlightenConfig
---@field ai EnlightenAiConfig

---@class EnlightenPartialConfig
---@field ai EnlightPartialAiConfig

---@return EnlightenConfig
function M.get_default_config()
	return {
		ai = {
			-- chat model from OpenAI to use for completions
			model = "gpt-4o",
			-- temperature to use for completions
			temperature = 0,
			-- context from buffer (before and after selection) to use for completions
			context_before = 100,
			context_after = 100,
			-- timeout for completion request
			timeout = 60,
			-- max response tokens for completions
			tokens = 4096,
		},
	}
end
M.config = M.get_default_config()

---@param partial_config EnlightenPartialConfig?
---@param latest_config EnlightenConfig?
---@return EnlightenConfig
function M.merge_config(partial_config, latest_config)
	partial_config = partial_config or {}
	local config = latest_config or M.get_default_config()
	for k, v in pairs(partial_config) do
		if k == "ai" then
			config.ai = vim.tbl_extend("force", config.ai, v)
		else
			config[k] = vim.tbl_extend("force", config[k] or {}, v)
		end
	end
	return config
end

return M
