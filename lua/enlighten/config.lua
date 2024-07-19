local Logger = require("enlighten/logger")

local M = {}

---@class EnlightenAiConfig
---@field provider string
---@field model string
---@field temperature number
---@field timeout number
---@field tokens number

---@class EnlightenPartialAiConfig
---@field provider? string
---@field model? string
---@field temperature? number
---@field timeout? number
---@field tokens? number

---@class EnlightenPromptSettings

---@class EnlightenChatSettings

---@class EnlightenPartialPromptSettings

---@class EnlightenPartialChatSettings

---@class EnlightenConfig
---@field ai { prompt: EnlightenAiConfig, chat: EnlightenAiConfig }
---@field settings { prompt: EnlightenPromptSettings, chat: EnlightenChatSettings }

---@class EnlightenPartialConfig
---@field ai { prompt: EnlightenPartialAiConfig, chat: EnlightenPartialAiConfig }
---@field settings { prompt: EnlightenPartialPromptSettings, chat: EnlightenPartialChatSettings }

---@return EnlightenConfig
function M.get_default_config()
	return {
		ai = {
			prompt = {
				provider = "openai",
				model = "gpt-4o",
				temperature = 0,
				timeout = 60,
				tokens = 4096,
			},
			chat = {
				provider = "openai",
				model = "gpt-4o",
				temperature = 0,
				timeout = 60,
				tokens = 4096,
			},
		},
		settings = {
			prompt = {},
			chat = {},
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

	Logger:log("config.merge_config - config", config)
	M.config = config

	return config
end

return M
