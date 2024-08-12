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
    equals(error.error.message, openai.get_error_text(error))
  end)

  it("should return streamed text", function()
    local success = tu.openai_response("hello")
    equals("hello", openai.get_streamed_text(success))
  end)
end)
