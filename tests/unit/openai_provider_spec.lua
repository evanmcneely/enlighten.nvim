local tu = require("tests.testutils")
local openai = require("enlighten.ai.openai")

local equals = assert.are.same

describe("provider openai", function()
  it("should identify errors in streamed responses", function()
    local success = tu.openai_response("hello")
    local error = tu.openai_error()

    equals(true, openai.is_error(error))
    equals(false, openai.is_error(success))
  end)

  it("should return error messages", function()
    local error = tu.openai_error()
    equals(error.error.message, openai.get_error_message(error))
  end)

  it("should return streamed text", function()
    local success = tu.openai_response("hello")
    equals("hello", openai.get_text(success))
  end)

  it("should identify when streaming has finished", function()
    local done = tu.openai_response("hello", "done")
    local nope = tu.openai_response("hello")

    equals(true, openai.is_streaming_finished(done))
    equals(false, openai.is_streaming_finished(nope))
  end)

  it("should return no content if streaming is finished", function()
    local success = tu.openai_response("hello", "done")
    equals("", openai.get_text(success))
  end)
end)
