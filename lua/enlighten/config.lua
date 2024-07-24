local Logger = require("enlighten/logger")

local M = {}

---@class EnlightenAiProviderConfig
---@field provider string -- AI model provider
---@field model string -- model used for completions
---@field temperature number
---@field tokens number -- token limit for completions

---@class EnlightenPartialAiProviderConfig
---@field provider? string
---@field model? string
---@field temperature? number
---@field tokens? number

---@class EnlightenAiConfig
---@field chat EnlightenAiProviderConfig
---@field prompt EnlightenAiProviderConfig
---@field timeout number

---@class EnlightenPartialAiConfig
---@field chat? EnlightenPartialAiProviderConfig
---@field prompt? EnlightenPartialAiProviderConfig
---@field timeout? number

---@class EnlightenPromptSettings
---@field width number -- prompt window width (number of columns)
---@field height number -- prompt window height (number of rows)

---@class EnlightenChatSettings
---@field width number -- chat pane width (number of columns)

---@class EnlightenPartialPromptSettings
---@field width? number
---@field height? number

---@class EnlightenPartialChatSettings
---@field width? number

---@class EnlightenConfig
---@field ai EnlightenAiConfig
---@field settings { prompt: EnlightenPromptSettings, chat: EnlightenChatSettings }

---@class EnlightenPartialConfig
---@field ai EnlightenPartialAiConfig
---@field settings { prompt: EnlightenPartialPromptSettings, chat: EnlightenPartialChatSettings }

---@return EnlightenConfig
function M.get_default_config()
  return {
    ai = {
      prompt = {
        provider = "openai",
        model = "gpt-4o",
        temperature = 0,
        tokens = 4096,
      },
      chat = {
        provider = "openai",
        model = "gpt-4o",
        temperature = 0,
        tokens = 4096,
      },
      timeout = 60,
    },
    settings = {
      prompt = {
        width = 70,
        height = 3,
      },
      chat = {
        width = 60,
      },
    },
  }
end

M.config = M.get_default_config()

function M.validate_environment()
  if vim.fn.getenv("OPENAI_API_KEY") == nil then
    Logger:log("config.validate_environment - no API key is set")
    vim.api.nvim_notify(
      "Enlighten: No 'OPENAI_API_KEY' environment variable is not set",
      vim.log.levels.WARN,
      {}
    )
  end

  local function is_curl_installed()
    local handle = io.popen("command -v curl")
    local result = ""
    if handle ~= nil then
      result = handle:read("*a")
      handle:close()
    end
    return result ~= ""
  end

  if not is_curl_installed() then
    Logger:log("config.validate_environment - curl not installed")
    vim.api.nvim_notify(
      "Enlighten: Curl is not installed. Please install curl to use this plugin.",
      vim.log.levels.WARN,
      {}
    )
    return
  end
end

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
