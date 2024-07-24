---@class MockWriter: Writer
---@field data OpenAIStreamingResponse[]
---@field complete_err? string
---@field on_done_calls number
---@field on_complete_calls number
local MockWriter = {}

function MockWriter:new(buffer)
  self.__index = self
  self.buffer = buffer
  self.data = {}
  self.complete_err = nil
  self.on_done_calls = 0
  self.on_complete_calls = 0
  return self
end

function MockWriter:on_data(data)
  table.insert(self.data, data)
end

function MockWriter:on_complete(err)
  self.on_complete_calls = self.on_complete_calls + 1
  self.complete_err = err
end

return MockWriter
