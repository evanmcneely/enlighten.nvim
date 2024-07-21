local Logger = require("enlighten/logger")
local Prompt = require("enlighten/prompt")
local Chat = require("enlighten/chat")
local Ai = require("enlighten/ai")
local Config = require("enlighten/config")

---@class Enlighten
---@field config EnlightenConfig
---@field prompt EnlightenPrompt
---@field logger EnlightenLog
local Enlighten = {}

Enlighten.__index = Enlighten

---@return Enlighten
function Enlighten:new()
	local config = Config.get_default_config()

	local enlighten = setmetatable({
		config = config,
		logger = Logger,
		prompt = nil,
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

	Config.validate_environment()

	return self
end

--- Focus the prompt window if it exists and create a new one otherwise
function Enlighten:open_prompt()
	if self.prompt ~= nil then
		self.logger:log("enlighten:open_prompt - focusing")
		self:focus_prompt()
		return
	end

	self.logger:log("enlighten:open_prompt - new")
	local ai = Ai:new(self.config.ai.prompt)
	self.prompt = Prompt:new(ai, self.config.settings.prompt)
end

--- Close the prompt window if it exists and open it otherwise
function Enlighten:toggle_prompt()
	if self.prompt ~= nil then
		self.logger:log("enlighten:toggle_prompt - close")
		self:close_prompt()
		return
	end

	self.logger:log("enlighten:toggle_prompt - open")
	self:open_prompt()
end

--- Focus the prompt window if it exists
function Enlighten:focus_prompt()
	if self.prompt ~= nil then
		self.logger:log("enlighten:focus_prompt - focusing")
		self.prompt:focus()
	end
end

--- Close the prompt window if it exists
function Enlighten:close_prompt()
	if self.prompt ~= nil then
		self.logger:log("enlighten:close_prompt - closing")
		self.prompt:close()
		self.prompt = nil
	end
end

--- Focus the prompt in the chat pane if it exists and create a new one otherwise
function Enlighten:open_chat()
	if self.chat ~= nil then
		self.logger:log("enlighten:open_chat - focusing")
		self:focus_chat()
		return
	end

	self.logger:log("enlighten:open_chat - new")
	local ai = Ai:new(self.config.ai.chat)
	self.chat = Chat:new(ai, self.config.settings.chat)
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

--- Focus the chat pane prompt if it exists
function Enlighten:focus_chat()
	if self.chat ~= nil then
		self.logger:log("enlighten:focus_chat - focusing")
		self.chat:focus()
	end
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
