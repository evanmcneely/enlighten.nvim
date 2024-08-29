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
---@field edit EnlightenAiProviderConfig
---@field timeout number
---@field provider string -- AI model provider
---@field model string -- model used for completions
---@field temperature number
---@field tokens number -- token limit for completions

---@class EnlightenPartialAiConfig
---@field chat? EnlightenPartialAiProviderConfig
---@field edit? EnlightenPartialAiProviderConfig
---@field timeout? number
---@field provider? string
---@field model? string
---@field temperature? number
---@field tokens? number

---@class EnlightenEditSettings
---@field width number -- edit window width (number of columns)
---@field height number -- edit window height (number of rows)
---@field showTitle boolean -- whether to render a title in the edit UI
---@field showHelp boolean -- whether to render help footer in the edit UI
---@field context number
---@field border string
---@field diff_mode string

---@class EnlightenChatSettings
---@field width number -- chat pane width (number of columns)
---@field split string -- side to vsplit that into (default right)

---@class EnlightenPartialEditSettings
---@field width? number
---@field height? number
---@field showTitle? boolean
---@field showHelp? boolean
---@field context? number
---@field border? string
---@field diff_mode? string

---@class EnlightenPartialChatSettings
---@field width? number
---@field split? string

---@class EnlightenSettings
---@field edit EnlightenEditSettings
---@field chat EnlightenChatSettings

---@class EnlightenPartialSettings
---@field edit? EnlightenPartialEditSettings
---@field chat? EnlightenPartialChatSettings

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
      edit = {
        width = 80,
        height = 5,
        showTitle = true,
        showHelp = true,
        context = 500,
        border = "═",
        diff_mode = "diff",
      },
      chat = {
        width = 80,
        split = "right",
      },
    },
  }
end

M.config = M.get_default_config()

---@return boolean
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
    M.warn("Enlighten: Curl is not installed. Install curl to use this plugin.")
    return false
  end

  if vim.fn.has("nvim-0.10.0") == 0 then
    Logger:log("config.validate_environment - neovim not v0.10.0+")
    M.warn("Enlighten: Need nvim >= 0.10.0.")
    return false
  end

  return true
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
function M.build_config(partial_config, latest_config)
  partial_config = partial_config or {}
  local config = latest_config or M.get_default_config()

  Logger:log("config.merge_config - user", partial_config)

  config.ai = vim.tbl_deep_extend("force", config.ai, partial_config.ai or {})

  local base_provider_config = {
    provider = config.ai.provider,
    timeout = config.ai.timeout,
    model = config.ai.model,
    tokens = config.ai.tokens,
    temperature = config.ai.temperature,
  }

  config.ai.edit = vim.tbl_deep_extend("force", base_provider_config, config.ai.edit or {})
  config.ai.chat = vim.tbl_deep_extend("force", base_provider_config, config.ai.chat or {})

  if not M.is_valid_ai_provider(config.ai.edit.provider) then
    M.warn(
      "Enlighten: Invalid provider "
        .. config.ai.edit.provider
        .. " for edit. Using default openai."
    )
    config.ai.edit.provider = "openai"
  end

  if not M.is_valid_ai_provider(config.ai.chat.provider) then
    M.warn(
      "Enlighten: Invalid provider "
        .. config.ai.chat.provider
        .. " for chat. Using default openai."
    )
    config.ai.chat.provider = "openai"
  end

  if partial_config.settings then
    config.settings.edit =
      vim.tbl_deep_extend("force", config.settings.edit, partial_config.settings.edit or {})
    config.settings.chat =
      vim.tbl_deep_extend("force", config.settings.chat, partial_config.settings.chat or {})
  end

  -- set border to " " if title or footer is true
  if
    config.settings.edit.border == ""
    and (config.settings.edit.showHelp == true or config.settings.edit.showTitle == true)
  then
    config.settings.edit.border = " "
  end

  Logger:log("config.merge_config - final", config)

  return config
end

return M
