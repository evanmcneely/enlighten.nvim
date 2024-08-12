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
    ai = Ai:new(config.merge_config().ai)

    -- Override the exec method so we can capture the stdout handler.
    -- The exec method won't be tested here...
    ---@diagnostic disable-next-line: duplicate-set-field
    ai.exec = function(_, _, on_stdout_chunk)
      buffer_chunk = on_stdout_chunk
    end

    writer = MockWriter:new(0)
    ai:complete("prompt", writer)
  end)

  it("should not call writer:on_data when completion is ''", function()
    local obj = tu.openai_response("")

    buffer_chunk(vim.json.encode(obj))

    equals(0, #writer.data)
    equals(0, writer.on_complete_calls)
  end)

  it("should not call writer:on_data when completion is ''", function()
    local obj = tu.openai_response("")

    buffer_chunk(vim.json.encode(obj))

    equals(0, #writer.data)
    equals(0, writer.on_complete_calls)
  end)

  it("should call writer:on_data when a chunk is received", function()
    local text = "wassup"
    local obj = tu.openai_response(text)

    -- When a response streams in, it should get buffered into the writer:on_data method
    buffer_chunk(vim.json.encode(obj))
    equals(text, writer.data[1])

    -- And the writer:on_complete should not be called
    equals(1, #writer.data)
    equals(0, writer.on_complete_calls)
  end)

  it("should process chunks with 'data:' prefix", function()
    local text = "wassup"
    local obj = tu.openai_response(text)

    -- When a response streams in, it should get buffered into the writer:on_data method
    buffer_chunk("data: " .. vim.json.encode(obj))
    equals(text, writer.data[1])

    -- And the writer:on_complete should not be called
    equals(1, #writer.data)
    equals(0, writer.on_complete_calls)
  end)

  it("should process multiple incoming chunks with 'data:' prefix", function()
    local text = "wassup"
    local res = tu.openai_response(text)
    local chunk = vim.json.encode(res)

    -- When a response streams in, it should get buffered into the writer:on_data method
    buffer_chunk("data: " .. chunk .. " data: " .. chunk .. " data: " .. chunk)
    equals(text, writer.data[1])
    equals(text, writer.data[2])
    equals(text, writer.data[3])

    -- And the writer:on_complete should not be called
    equals(3, #writer.data)
    equals(0, writer.on_complete_calls)
  end)

  it("should process incomplete json chunks", function()
    local text = "wassup"
    local response = tu.openai_response(text)
    local chunk = vim.json.encode(response) or ""
    local chunk_1 = chunk:sub(1, #chunk / 2)
    local chunk_2 = chunk:sub(#chunk / 2 + 1)

    -- When the first part of this response comes in, nothing should happen
    buffer_chunk(chunk_1)
    equals(0, #writer.data)

    -- When the second half comes in, completing the first, the response is processed
    buffer_chunk(chunk_2)
    equals(1, #writer.data)
    equals(text, writer.data[1])

    -- And writer:on_complete should not be called
    equals(0, writer.on_complete_calls)
  end)

  it("should process open and close {} in completion content", function()
    local open = tu.openai_response("{")
    buffer_chunk(vim.json.encode(open))
    equals("{", writer.data[1])

    local close = tu.openai_response("}")
    buffer_chunk(vim.json.encode(close))
    equals("}", writer.data[2])
  end)

  it("should call writer:on_complete when an error is received", function()
    local obj = tu.openai_error()

    buffer_chunk(vim.json.encode(obj))

    equals(0, #writer.data)
    equals(1, writer.on_complete_calls)
  end)
end)
