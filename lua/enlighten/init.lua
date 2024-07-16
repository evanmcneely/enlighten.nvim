local Log = require("enlighten.logger")
local Ui = require("enlighten.ui")
local Config = require("enlighten.config")

---@class Enlighten
---@field config EnlightenConfig
---@field ui EnlightenUI
---@field logger EnlightenLog
local Enlighten = {}

Enlighten.__index = Enlighten

---@return Enlighten
function Enlighten:new()
	local config = Config.get_default_config()

	local enlighten = setmetatable({
		config = config,
		logger = Log,
		ui = Ui:new(),
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

	return self
end

return enlighten_me
