local api = vim.api
local Logger = require("enlighten.logger")

---@class MemoryWriter: Writer
local MemoryWriter = {}

---@param on_done fun(string):nil
---@return MemoryWriter
function MemoryWriter:new(on_done)
  Logger:log("memory:new")

  self.__index = self
  return setmetatable({
    active = false,
    accumulated_text = "",
    on_done = on_done,
  }, self)
end

---@param text string
function MemoryWriter:on_data(text)
  self.accumulated_text = self.accumulated_text .. text
end

function MemoryWriter:on_complete(err)
  self.active = false

  if err then
    Logger:log("memory:on_complete - error", err)
    api.nvim_err_writeln("Enlighten: " .. err)
    return
  end

  self.on_done(self.accumulated_text)

  Logger:log("memory:on_complete - ai completion", self.accumulated_text)
end

function MemoryWriter:start()
  self.active = true
end

function MemoryWriter:reset()
  self.accumulated_text = ""
end

function MemoryWriter.stop()
  -- nothing
end

return MemoryWriter
