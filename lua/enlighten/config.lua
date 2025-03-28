local Logger = require("enlighten.logger")

local M = {}

---@alias diffmode 'diff' | 'change'

---@class EnlightenConfig
---@field ai EnlightenAiConfig
---@field settings EnlightenSettings

---@class EnlightenPartialConfig
---@field context? number
---@field diff_mode? diffmode
---@field ai? EnlightenPartialAiConfig
---@field settings? EnlightenPartialSettings
---
---@class EnlightenSettings
---@field context number
---@field diff_mode diffmode
---@field edit EnlightenEditSettings
---@field chat EnlightenChatSettings

---@class EnlightenPartialSettings
---@field edit? EnlightenPartialEditSettings
---@field chat? EnlightenPartialChatSettings

---@class EnlightenAiConfig
---@field chat? EnlightenAiProviderConfig
---@field edit? EnlightenAiProviderConfig
---@field timeout number Completion timeout in seconds
---@field provider string AI model provider
---@field model string Model used for completions
---@field temperature number Model temperature (used only when provider API permits)
---@field tokens number Token limit for completions (used only when provider API permits)

---@class EnlightenPartialAiConfig
---@field chat? EnlightenPartialAiProviderConfig
---@field edit? EnlightenPartialAiProviderConfig
---@field timeout? number
---@field provider? string
---@field model? string
---@field temperature? number
---@field tokens? number

---@class EnlightenAiProviderConfig
---@field provider string
---@field model string
---@field temperature number
---@field tokens number
---@field timeout number

---@class EnlightenPartialAiProviderConfig
---@field provider? string
---@field model? string
---@field temperature? number
---@field tokens? number
---@field timeout? number

---@class EnlightenEditSettings
---@field width number Edit popup window width (number of columns)
---@field height number Edit popup window height (number of rows)
---@field showTitle boolean Whether to render a title in the edit UI
---@field showHelp boolean Whether to render help footer in the edit UI
---@field context? number Number of lines above and below selection to use as context in completion
---@field border string Character used as top and bottomm border in popup window
---@field diff_mode? diffmode Whether to show added/removed lines or only changes (diff or change)

---@class EnlightenPartialEditSettings
---@field width? number
---@field height? number
---@field showTitle? boolean
---@field showHelp? boolean
---@field context? number
---@field border? string
---@field diff_mode? diffmode

---@class EnlightenChatSettings
---@field width number Chat pane width (number of columns)
---@field split string Side that the chat pane opens on (left or right)
---@field diff_mode? diffmode
---@field context? number

---@class EnlightenPartialChatSettings
---@field width? number
---@field split? string
---@field diff_mode? diffmode
---@field context? number

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
      diff_mode = "diff",
      context = 500,
      edit = {
        width = 80,
        height = 5,
        showTitle = true,
        showHelp = true,
        border = "═",
      },
      chat = {
        width = 80,
        split = "right",
      },
    },
  } ---@type EnlightenConfig
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
  -- TODO revisit these warning messages to ensure they bubble up to the user properly
  vim.api.nvim_notify(message, vim.log.levels.WARN, {})
end

---@param partial_config EnlightenPartialConfig?
---@return EnlightenConfig
-- TODO fail and return early if config is invalid
function M.build_config(partial_config)
  partial_config = partial_config or {}
  local config = M.get_default_config()

  Logger:log("config.build_config - user provided", partial_config)

  config.ai = vim.tbl_deep_extend("force", config.ai, partial_config.ai or {})

  ---@diagnostic disable-next-line: missing-fields
  if config.ai.edit == nil then
    config.ai.edit = {}
  end
  ---@diagnostic disable-next-line: missing-fields
  if config.ai.chat == nil then
    config.ai.chat = {}
  end

  config.ai.edit.provider = config.ai.edit.provider or config.ai.provider
  config.ai.chat.provider = config.ai.chat.provider or config.ai.provider
  config.ai.edit.timeout = config.ai.edit.timeout or config.ai.timeout
  config.ai.chat.timeout = config.ai.chat.timeout or config.ai.timeout
  config.ai.edit.model = config.ai.edit.model or config.ai.model
  config.ai.chat.model = config.ai.chat.model or config.ai.model
  config.ai.edit.tokens = config.ai.edit.tokens or config.ai.tokens
  config.ai.chat.tokens = config.ai.chat.tokens or config.ai.tokens
  config.ai.edit.temperature = config.ai.edit.temperature or config.ai.temperature
  config.ai.chat.temperature = config.ai.chat.temperature or config.ai.temperature

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

  config.settings = vim.tbl_deep_extend("force", config.settings, partial_config.settings or {})
  config.settings.edit.context = config.settings.edit.context or config.settings.context
  config.settings.chat.context = config.settings.chat.context or config.settings.context
  config.settings.edit.diff_mode = config.settings.edit.diff_mode or config.settings.diff_mode
  config.settings.chat.diff_mode = config.settings.chat.diff_mode or config.settings.diff_mode

  -- Set border to " " if title or footer is true
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
