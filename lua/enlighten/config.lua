local Logger = require("enlighten/logger")

local M = {}

---@class EnlightenAiProviderConfig
---@field provider string -- AI model provider
---@field model string -- model used for completions
---@field temperature number
---@field tokens number -- token limit for completions
---@field timeout number

---@class EnlightenPartialAiProviderConfig
---@field provider? string
---@field model? string
---@field temperature? number
---@field tokens? number
---@field timeout? number

---@class EnlightenAiConfig
---@field chat EnlightenAiProviderConfig
---@field prompt EnlightenAiProviderConfig
---@field timeout number
---@field provider string -- AI model provider
---@field model string -- model used for completions
---@field temperature number
---@field tokens number -- token limit for completions

---@class EnlightenPartialAiConfig
---@field chat? EnlightenPartialAiProviderConfig
---@field prompt? EnlightenPartialAiProviderConfig
---@field timeout? number
---@field provider? string
---@field model? string
---@field temperature? number
---@field tokens? number

---@class EnlightenPromptSettings
---@field width number -- prompt window width (number of columns)
---@field height number -- prompt window height (number of rows)

---@class EnlightenChatSettings
---@field width number -- chat pane width (number of columns)
---@field split string -- side to vsplit that into (default right)

---@class EnlightenPartialPromptSettings
---@field width? number
---@field height? number

---@class EnlightenPartialChatSettings
---@field width? number
---@field split? string

---@class EnlightenSettings
---@field prompt EnlightenPromptSettings
---@field chat EnlightenChatSettings

---@class EnlightenPartialSettings
---@field prompt? EnlightenPromptSettings
---@field chat? EnlightenChatSettings

---@class EnlightenConfig
---@field ai EnlightenAiConfig
---@field settings EnlightenSettings

---@class EnlightenPartialConfig
---@field ai? EnlightenPartialAiConfig
---@field settings? EnlightenPartialSettings

---@return EnlightenConfig
function M.get_default_config()
  return {
    ai = {
      provider = "openai",
      model = "gpt-4o",
      temperature = 0,
      tokens = 4096,
      timeout = 60,
    },
    settings = {
      prompt = {
        width = 80,
        height = 5,
      },
      chat = {
        width = 80,
        split = "right",
      },
    },
  }
end

M.config = M.get_default_config()

function M.validate_environment()
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
    M.warn("Enlighten: Curl is not installed. Please install curl to use this plugin.")
    return
  end
end

---@param p string
---@return boolean
function M.is_valid_ai_provider(p)
  local accepted = { "openai", "anthropic" }
  return vim.tbl_contains(accepted, p)
end

---@param message string
function M.warn(message)
  vim.api.nvim_notify(message, vim.log.levels.WARN, {})
end

---@param partial_config EnlightenPartialConfig?
---@param latest_config EnlightenConfig?
---@return EnlightenConfig
function M.merge_config(partial_config, latest_config)
  partial_config = partial_config or {}
  local config = latest_config or M.get_default_config()

  Logger:log("config.merge_config - user config", partial_config)

  config.ai = vim.tbl_deep_extend("force", config.ai, partial_config.ai or {})

  local base_provider_config = {
    provider = config.ai.provider,
    timeout = config.ai.timeout,
    model = config.ai.model,
    tokens = config.ai.tokens,
    temperature = config.ai.temperature,
  }

  config.ai.prompt = vim.tbl_deep_extend("force", base_provider_config, config.ai.prompt or {})
  config.ai.chat = vim.tbl_deep_extend("force", base_provider_config, config.ai.chat or {})

  if not M.is_valid_ai_provider(config.ai.prompt.provider) then
    M.warn("Invalid provider " .. config.ai.prompt.provider .. " for prompt, using default openai")
    config.ai.prompt.provider = "openai"
  end

  if not M.is_valid_ai_provider(config.ai.chat.provider) then
    M.warn("Invalid provider " .. config.ai.chat.provider .. " for chat, using default openai")
    config.ai.chat.provider = "openai"
  end

  if partial_config.settings then
    config.settings.prompt =
      vim.tbl_deep_extend("force", config.settings.prompt, partial_config.settings.prompt or {})
    config.settings.chat =
      vim.tbl_deep_extend("force", config.settings.chat, partial_config.settings.chat or {})
  end

  Logger:log("config.merge_config - final config", config)

  return config
end

return M
