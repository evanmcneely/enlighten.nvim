local api = vim.api
local Logger = require("enlighten.logger")

---@class SelfWriter: Writer
local SelfWriter = {}

---@param on_done fun(string):nil
---@return SelfWriter
function SelfWriter:new(on_done)
  Logger:log("self:new")

  self.__index = self
  return setmetatable({
    active = false,
    accumulated_text = "",
    on_done = on_done,
  }, self)
end

---@param text string
function SelfWriter:on_data(text)
  self.accumulated_text = self.accumulated_text .. text
end

function SelfWriter:on_complete(err)
  self.active = false

  if err then
    Logger:log("self:on_complete - error", err)
    api.nvim_err_writeln("Enlighten: " .. err)
    return
  end

  self.on_done(self.accumulated_text)

  Logger:log("self:on_complete - ai completion", self.accumulated_text)
end

function SelfWriter:start()
  self.active = true
end

function SelfWriter:reset()
  self.accumulated_text = ""
end

function SelfWriter.stop()
  -- nothing
end

return SelfWriter
