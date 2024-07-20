local Logger = require("enlighten/logger")

local M = {}

---@class EnlightenAiConfig
---@field provider string -- AI model provider
---@field model string -- model used for completions
---@field temperature number
---@field timeout number
---@field tokens number -- token limit for completions

---@class EnlightenPartialAiConfig
---@field provider? string
---@field model? string
---@field temperature? number
---@field timeout? number
---@field tokens? number

---@class EnlightenPromptSettings
---@field width number -- prompt window width (number of columns)
---@field height number -- prompt window height (number of rows)

---@class EnlightenChatSettings
---@field width number -- chat pane width (number of columns)
---@field height number -- chat input pnompt window height (number of lines)

---@class EnlightenPartialPromptSettings
---@field width? number
---@field height? number

---@class EnlightenPartialChatSettings
---@field width? number
---@field height? number

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
			prompt = {
				width = 70,
				height = 3,
			},
			chat = {
				width = 80,
				height = 6,
			},
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
		if k == "ai" or k == "settings" then
			for j, w in pairs(v) do
				if j == "prompt" or j == "chat" then
					config[k][j] = vim.tbl_extend("force", config[k][j], w)
				end
			end
		end
	end

	Logger:log("config.merge_config - config", config)
	M.config = config

	return config
end

return M
