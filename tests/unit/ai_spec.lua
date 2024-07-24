---@diagnostic disable: undefined-field

local Ai = require("enlighten.ai")
local tu = require("tests.testutils")
local MockWriter = require("tests.mock_writer")
local config = require("enlighten.config")

local equals = assert.are.same

describe("ai", function()
  local buffer_chunk
  local ai
  local writer

  before_each(function()
    ai = Ai:new(config.get_default_config().ai)

    -- Override the exec method so we can capture the stdout handler.
    -- The exec method won't be tested here...
    ---@diagnostic disable-next-line: duplicate-set-field
    ai.exec = function(_, _, on_stdout_chunk)
      buffer_chunk = on_stdout_chunk
    end

    writer = MockWriter:new(0)
    ai:complete("prompt", writer)
  end)

  it("should call writer:on_data when a chunk is received", function()
    local obj = tu.openai_response("wassup")

    -- When a response streams in, it should get buffered into the writer:on_data method
    buffer_chunk(vim.json.encode(obj))
    equals(obj, writer.data[1])

    -- And the writer:on_complete should not be called
    equals(1, #writer.data)
    equals(0, writer.on_complete_calls)
  end)

  it("should process chunks with 'data:' prefix", function()
    local obj = tu.openai_response("wassup")

    -- When a response streams in, it should get buffered into the writer:on_data method
    buffer_chunk("data: " .. vim.json.encode(obj))
    equals(obj, writer.data[1])

    -- And the writer:on_complete should not be called
    equals(1, #writer.data)
    equals(0, writer.on_complete_calls)
  end)

  it("should process multiple incoming chunks with 'data:' prefix", function()
    local res = tu.openai_response("wassup")
    local chunk = vim.json.encode(res)

    -- When a response streams in, it should get buffered into the writer:on_data method
    buffer_chunk("data: " .. chunk .. " data: " .. chunk .. " data: " .. chunk)
    equals(res, writer.data[1])
    equals(res, writer.data[2])
    equals(res, writer.data[3])

    -- And the writer:on_complete should not be called
    equals(3, #writer.data)
    equals(0, writer.on_complete_calls)
  end)

  it("should process incomplete json chunks", function()
    local response = tu.openai_response("wassup")
    local chunk = vim.json.encode(response) or ""
    local chunk_1 = chunk:sub(1, #chunk / 2)
    local chunk_2 = chunk:sub(#chunk / 2 + 1)

    -- When the first part of this response comes in, nothing should happen
    buffer_chunk(chunk_1)
    equals(0, #writer.data)

    -- When the second half comes in, completing the first, the response is processed
    buffer_chunk(chunk_2)
    equals(1, #writer.data)
    equals(response, writer.data[1])

    -- And writer:on_complete should not be called
    equals(0, writer.on_complete_calls)
  end)

  it("should call writer:on_complete when an error is received", function()
    local obj = tu.openai_error()

    buffer_chunk(vim.json.encode(obj))

    equals(0, #writer.data)
    equals(1, writer.on_complete_calls)
  end)
end)
