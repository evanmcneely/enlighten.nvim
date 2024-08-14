local tu = require("tests.testutils")
local anthropic = require("enlighten.ai.anthropic")

local equals = assert.are.same

describe("provider anthropic", function()
  it("should identify errors in streamed responses", function()
    local success = tu.anthropic_response("content_block_delta", "yop")
    local error = tu.anthropic_error()

    equals(true, anthropic.is_error(error))
    equals(false, anthropic.is_error(success))
  end)

  it("should return error messages", function()
    local error = tu.anthropic_error()
    equals(error.error.message, anthropic.get_error_text(error))
  end)

  it("should return no text for message_start events", function()
    local res = tu.anthropic_response("message_start")
    equals("", anthropic.get_streamed_text(res))
  end)

  it("should return no text for content_block_start events", function()
    local res = tu.anthropic_response("content_block_start")
    equals("", anthropic.get_streamed_text(res))
  end)

  it("should return no text for ping events", function()
    local res = tu.anthropic_response("ping")
    equals("", anthropic.get_streamed_text(res))
  end)

  it("should text for content_block_delta events", function()
    local res = tu.anthropic_response("content_block_delta", "hello")
    equals("hello", anthropic.get_streamed_text(res))
  end)

  it("should return no text for content_block_stop events", function()
    local res = tu.anthropic_response("content_block_stop")
    equals("", anthropic.get_streamed_text(res))
  end)

  it("should return no text for message_delta events", function()
    local res = tu.anthropic_response("message_delta")
    equals("", anthropic.get_streamed_text(res))
  end)

  it("should return no text for message_stop events", function()
    local res = tu.anthropic_response("message_stop")
    equals("", anthropic.get_streamed_text(res))
  end)

  it("should identify when streaming has finished", function()
    local start = tu.anthropic_response("message_start")
    local stop = tu.anthropic_response("message_stop")
    local delta = tu.anthropic_response("message_delta")
    local block_start = tu.anthropic_response("content_block_start")
    local block_delta = tu.anthropic_response("content_block_delta", "hello")
    local block_stop = tu.anthropic_response("content_block_stop")
    local ping = tu.anthropic_response("ping")

    equals(false, anthropic.is_streaming_finished(start))
    equals(true, anthropic.is_streaming_finished(stop))
    equals(false, anthropic.is_streaming_finished(delta))
    equals(false, anthropic.is_streaming_finished(block_start))
    equals(false, anthropic.is_streaming_finished(block_delta))
    equals(false, anthropic.is_streaming_finished(block_stop))
    equals(false, anthropic.is_streaming_finished(ping))
  end)
end)