local Logger = require("enlighten/logger")
local Prompt = require("enlighten/prompt")
local Chat = require("enlighten/chat")
local Ai = require("enlighten/ai")
local Config = require("enlighten/config")
local highlights = require("enlighten/highlights")

---@class Enlighten
---@field config EnlightenConfig
---@field logger EnlightenLog
---@field prompt EnlightenPrompt
---@field chat EnlightenChat
---@field prompt_history string[][]
---@field chat_history string[][]
---@field ai AI
local Enlighten = {}

Enlighten.__index = Enlighten

---@return Enlighten
function Enlighten:new()
  local config = Config.get_default_config()

  local enlighten = setmetatable({
    config = config,
    logger = Logger,
    chat = nil,
    prompt_history = {},
    chat_history = {},
  }, self)

  return enlighten
end

local enlighten_me = Enlighten:new()

---@param self Enlighten
---@param partial_config EnlightenPartialConfig?
---@return Enlighten
function Enlighten.setup(self, partial_config)
  if self ~= enlighten_me then
    ---@diagnostic disable-next-line: cast-local-type
    partial_config = self
    self = enlighten_me
  end

  ---@diagnostic disable-next-line: param-type-mismatch
  self.config = Config.merge_config(partial_config, self.config)
  self.ai = Ai:new(self.config.ai)

  Config.validate_environment()

  highlights.setup()

  return self
end

function Enlighten:edit()
  local current_win = vim.api.nvim_get_current_win()
  local popups = vim.api.nvim_list_wins()

  for _, win in ipairs(popups) do
    local config = vim.api.nvim_win_get_config(win)
    local buf = vim.api.nvim_win_get_buf(win)
    local buf_type = vim.api.nvim_get_option_value("filetype", { buf = buf })

    if buf_type == "enlighten" and config.relative == "win" and config.win == current_win then
      vim.api.nvim_set_current_win(win)
      return
    end
  end

  Prompt:new(self.ai, self.config.settings.prompt, self.prompt_history)
end

--- Focus the prompt in the chat pane if it exists and create a new one otherwise
function Enlighten:open_chat()
  if self.chat ~= nil then
    self.logger:log("enlighten:open_chat - focusing")
    self.chat:focus()
    return
  end

  self.logger:log("enlighten:open_chat - new")
  self.chat = Chat:new(self.ai, self.config.settings.chat, self.chat_history)
end

--- Close the chat pane if it exists and open it otherwise
function Enlighten:toggle_chat()
  if self.chat ~= nil then
    self.logger:log("enlighten:toggle_chat - close")
    self:close_chat()
    return
  end

  self.logger:log("enlighten:toggle_chat - open")
  self:open_chat()
end

--- Close the chat if it exists
function Enlighten:close_chat()
  if self.chat ~= nil then
    self.logger:log("enlighten:close_chat - closing")
    self.chat:close()
    self.chat = nil
  end
end

return enlighten_me
