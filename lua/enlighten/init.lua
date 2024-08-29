local Edit = require("enlighten/edit")
local Chat = require("enlighten/chat")
local config = require("enlighten/config")
local highlights = require("enlighten/highlights")

---@class Enlighten
---@field config EnlightenConfig
---@field edit_history HistoryItem[]
---@field chat_history HistoryItem[]
local enlighten = {}

---@param user_config EnlightenPartialConfig?
function enlighten.setup(user_config)
  local all_good = config.validate_environment()
  if not all_good then
    return
  end

  enlighten.config = config.build_config(user_config)
  enlighten.chat_history = {}
  enlighten.edit_history = {}

  highlights.setup()
end

function enlighten.edit()
  local all_good = config.validate_environment()
  if not all_good then
    return
  end

  local current_win = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_buf_type = vim.api.nvim_get_option_value("filetype", { buf = current_buf })

  -- If the current buffer is one of ours, do nothing
  if current_buf_type == "enlighten" then
    return
  end

  local popups = vim.api.nvim_list_wins()

  for _, win in ipairs(popups) do
    local win_config = vim.api.nvim_win_get_config(win)
    local buf = vim.api.nvim_win_get_buf(win)
    local buf_type = vim.api.nvim_get_option_value("filetype", { buf = buf })

    -- If we find an enlighten popup relative to the current window, focus it
    if
      buf_type == "enlighten"
      and win_config.relative == "win"
      and win_config.win == current_win
    then
      vim.api.nvim_set_current_win(win)
      return
    end
  end

  Edit:new(enlighten.config.ai.edit, enlighten.config.settings.edit, enlighten.edit_history)
end

function enlighten.chat()
  local all_good = config.validate_environment()
  if not all_good then
    return
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local current_buf_type = vim.api.nvim_get_option_value("filetype", { buf = current_buf })

  -- If the current buffer is one of ours, do nothing
  if current_buf_type == "enlighten" then
    return
  end

  Chat:new(enlighten.config.ai.chat, enlighten.config.settings.chat, enlighten.chat_history)
end

return enlighten
