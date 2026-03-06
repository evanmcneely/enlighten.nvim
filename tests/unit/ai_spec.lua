local ai = require("enlighten.ai")
local tu = require("tests.testutils")
local MockWriter = require("tests.mock_writer")
local config = require("enlighten.config")

local equals = assert.are.same

describe("ai", function()
  local buffer_chunk
  local finish_stream
  local writer

  before_each(function()
    -- Override the exec method so we can capture the stdout handler and on_complete callback.
    -- The exec method won't be tested here...
    ---@diagnostic disable-next-line: duplicate-set-field
    ai.exec = function(_, _, on_stdout_chunk, on_complete)
      buffer_chunk = on_stdout_chunk
      finish_stream = on_complete
    end

    writer = MockWriter:new(0)
    ---@diagnostic disable-next-line: param-type-mismatch
    ai.complete("prompt", writer, tu.build_completion_opts(config.build_config().ai.edit))
  end)

  it("should not call writer:on_data when completion is ''", function()
    local obj = tu.openai_streaming_response("")

    buffer_chunk(vim.json.encode(obj))

    equals(0, #writer.data)
    equals(0, writer.on_complete_calls)
  end)

  it("should not call writer:on_data when completion is ''", function()
    local obj = tu.openai_streaming_response("")

    buffer_chunk(vim.json.encode(obj))

    equals(0, #writer.data)
    equals(0, writer.on_complete_calls)
  end)

  it("should call writer:on_data when a chunk is received", function()
    local text = "wassup"
    local obj = tu.openai_streaming_response(text)

    -- When a response streams in, it should get buffered into the writer:on_data method
    buffer_chunk(vim.json.encode(obj))
    equals(text, writer.data[1])

    -- And the writer:on_complete should not be called
    equals(1, #writer.data)
    equals(0, writer.on_complete_calls)
  end)

  it("should process chunks with 'data:' prefix", function()
    local text = "wassup"
    local obj = tu.openai_streaming_response(text)

    -- When a response streams in, it should get buffered into the writer:on_data method
    buffer_chunk("data: " .. vim.json.encode(obj))
    equals(text, writer.data[1])

    -- And the writer:on_complete should not be called
    equals(1, #writer.data)
    equals(0, writer.on_complete_calls)
  end)

  it("should process chunks with 'event:content_block_delta data:' prefix", function()
    -- update the config to use anthropic provider (use chat feature to bypass text filter)
    ai.complete(
      "prompt",
      writer,
      ---@diagnostic disable-next-line: param-type-mismatch
      tu.build_completion_opts(
        vim.tbl_extend(
          "force",
          config.build_config({ ai = { provider = "anthropic" } }).ai.chat,
          { feature = "chat" }
        )
      )
    )

    local text = "wassup"
    local obj = tu.anthropic_streaming_response("content_block_delta", text)

    -- When a response streams in, it should get buffered into the writer:on_data method
    buffer_chunk("event:content_block_delta data: " .. vim.json.encode(obj))
    equals(text, writer.data[1])

    -- And the writer:on_complete should not be called
    equals(1, #writer.data)
    equals(0, writer.on_complete_calls)
  end)

  it("should process multiple incoming chunks with 'data:' prefix", function()
    local text = "wassup"
    local res = tu.openai_streaming_response(text)
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
    local response = tu.openai_streaming_response(text)
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
    local open = tu.openai_streaming_response("{")
    buffer_chunk(vim.json.encode(open))
    equals("{", writer.data[1])

    local close = tu.openai_streaming_response("}")
    buffer_chunk(vim.json.encode(close))
    equals("}", writer.data[2])
  end)

  it("should call writer:on_complete when an error is received", function()
    local obj = tu.openai_error()

    buffer_chunk(vim.json.encode(obj))

    equals(0, #writer.data)
    equals(1, writer.on_complete_calls)
  end)

  it("should run through full anthropic streaming routine", function()
    -- update the config to use anthropic provider (use chat feature to bypass text filter)
    ai.complete(
      "prompt",
      writer,
      ---@diagnostic disable-next-line: param-type-mismatch
      tu.build_completion_opts(
        vim.tbl_extend(
          "force",
          config.build_config({ ai = { provider = "anthropic" } }).ai.chat,
          { feature = "chat" }
        )
      )
    )

    local routine = {
      tu.anthropic_streaming_response("message_start"),
      tu.anthropic_streaming_response("content_block_start"),
      tu.anthropic_streaming_response("ping"),
      tu.anthropic_streaming_response("content_block_delta", "hello"),
      tu.anthropic_streaming_response("content_block_delta", "hello"),
      tu.anthropic_streaming_response("ping"),
      tu.anthropic_streaming_response("content_block_delta", "hello"),
      tu.anthropic_streaming_response("content_block_stop"),
      tu.anthropic_streaming_response("content_block_start"),
      tu.anthropic_streaming_response("content_block_delta", "hello"),
      tu.anthropic_streaming_response("ping"),
      tu.anthropic_streaming_response("content_block_delta", "hello"),
      tu.anthropic_streaming_response("content_block_delta", "hello"),
      tu.anthropic_streaming_response("ping"),
      tu.anthropic_streaming_response("content_block_stop"),
      tu.anthropic_streaming_response("message_delta"),
      tu.anthropic_streaming_response("message_stop"),
    }

    for _, obj in ipairs(routine) do
      buffer_chunk("event:" .. obj.type .. " data:" .. vim.json.encode(obj))
    end

    equals(6, #writer.data) -- only called on "content_block_delta" events
    equals(0, writer.on_complete_calls) -- only called when connection closed
  end)

  it("should strip code fences from anthropic streaming edit responses", function()
    ai.complete(
      "prompt",
      writer,
      ---@diagnostic disable-next-line: param-type-mismatch
      tu.build_completion_opts(config.build_config({ ai = { provider = "anthropic" } }).ai.edit)
    )

    local routine = {
      tu.anthropic_streaming_response("message_start"),
      tu.anthropic_streaming_response("content_block_start"),
      tu.anthropic_streaming_response("content_block_delta", "```python\n"),
      tu.anthropic_streaming_response("content_block_delta", "print('hello')\n"),
      tu.anthropic_streaming_response("content_block_delta", "print('world')\n"),
      tu.anthropic_streaming_response("content_block_delta", "```"),
      tu.anthropic_streaming_response("content_block_stop"),
      tu.anthropic_streaming_response("message_stop"),
    }

    for _, obj in ipairs(routine) do
      buffer_chunk("event:" .. obj.type .. " data:" .. vim.json.encode(obj))
    end

    -- Flush remaining text via on_complete
    finish_stream()

    -- The opening fence ```python should be stripped
    -- The closing ``` should be stripped on flush
    -- Only the actual code lines should be forwarded
    local all_text = table.concat(writer.data, "")
    equals(true, not all_text:match("```"))
    equals(true, all_text:match("print") ~= nil)
  end)

  it("should not strip code fences from anthropic streaming chat responses", function()
    ai.complete(
      "prompt",
      writer,
      ---@diagnostic disable-next-line: param-type-mismatch
      tu.build_completion_opts(
        vim.tbl_extend(
          "force",
          config.build_config({ ai = { provider = "anthropic" } }).ai.chat,
          { feature = "chat" }
        )
      )
    )

    local routine = {
      tu.anthropic_streaming_response("message_start"),
      tu.anthropic_streaming_response("content_block_start"),
      tu.anthropic_streaming_response("content_block_delta", "```python\n"),
      tu.anthropic_streaming_response("content_block_delta", "print('hello')\n"),
      tu.anthropic_streaming_response("content_block_delta", "```"),
      tu.anthropic_streaming_response("content_block_stop"),
      tu.anthropic_streaming_response("message_stop"),
    }

    for _, obj in ipairs(routine) do
      buffer_chunk("event:" .. obj.type .. " data:" .. vim.json.encode(obj))
    end

    finish_stream()

    -- Chat should preserve code fences
    local all_text = table.concat(writer.data, "")
    equals(true, all_text:match("```python") ~= nil)
  end)

  it("should strip code fences from anthropic non-streaming edit responses", function()
    ai.complete(
      "prompt",
      writer,
      ---@diagnostic disable-next-line: param-type-mismatch
      tu.build_completion_opts(
        vim.tbl_extend(
          "force",
          config.build_config({ ai = { provider = "anthropic" } }).ai.edit,
          { stream = false }
        )
      )
    )

    local response = tu.anthropic_response("```python\nprint('hello')\n```")
    buffer_chunk(vim.json.encode(response))

    equals(1, #writer.data)
    equals("print('hello')", writer.data[1])
  end)
end)
