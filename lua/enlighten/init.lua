local Edit = require("enlighten/edit")
local Chat = require("enlighten/chat")
local config = require("enlighten/config")
local highlights = require("enlighten/highlights")
local Logger = require("enlighten/logger")

---@class Enlighten
--- Full plugin configuration with default values overridden by user provided ones.
---@field config EnlightenConfig
--- `true` after the setup method completes successfully. Check for this to ensure
--- sure the config is set and environment is valid.
---@field setup_complete boolean
--- Helpful logger for debugging.
---@field logger EnlightenLog
local enlighten = {
  config = config.config,
  setup_complete = false,
  logger = Logger,
}

---@param user_config EnlightenPartialConfig?
function enlighten.setup(user_config)
  local all_good = config.validate_environment()
  if not all_good then
    return
  end

  enlighten.config = config.build_config(user_config)
  highlights.setup()
  enlighten.setup_complete = true
end

function enlighten.edit()
  if not enlighten.setup_complete then
    return
  end

  local current_win = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_buf_type = vim.api.nvim_get_option_value("filetype", { buf = current_buf })

  -- If the current buffer is one of ours, do nothing
  if current_buf_type == "enlighten" then
    return
  end

  local windows = vim.api.nvim_list_wins()

  for _, win in ipairs(windows) do
    local window_config = vim.api.nvim_win_get_config(win)
    local window_buf = vim.api.nvim_win_get_buf(win)
    local window_buf_type = vim.api.nvim_get_option_value("filetype", { buf = window_buf })

    -- If we find an enlighten popup relative to the current window, focus it
    if
      window_buf_type == "enlighten"
      and window_config.relative == "win"
      and window_config.win == current_win
    then
      vim.api.nvim_set_current_win(win)
      return
    end
  end

  Edit:new(enlighten.config.ai.edit, enlighten.config.settings.edit)
end

function enlighten.chat()
  if not enlighten.setup_complete then
    return
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local current_buf_type = vim.api.nvim_get_option_value("filetype", { buf = current_buf })

  -- If the current buffer is one of ours, do nothing
  if current_buf_type == "enlighten" then
    return
  end

  Chat:new(enlighten.config.ai.chat, enlighten.config.settings.chat)
end

return enlighten
