local tu = require("tests.testutils")
local openai = require("enlighten.ai.openai")

local equals = assert.are.same

describe("provider openai", function()
  it("should identify errors in streamed responses", function()
    local success = tu.openai_streaming_response("hello")
    local error = tu.openai_error()

    equals(true, openai.is_error(error))
    equals(false, openai.is_error(success))
  end)

  it("should return error messages", function()
    local error = tu.openai_error()
    equals(error.error.message, openai.get_error_message(error))
  end)

  it("should return streamed text", function()
    local success = tu.openai_streaming_response("hello")
    equals("hello", openai.get_text(success))
  end)

  it("should return response text", function()
    local success = tu.openai_response("hello")
    equals("hello", openai.get_text(success))
  end)

  it("should identify when streaming has finished", function()
    local done = tu.openai_streaming_response("hello", "done")
    local nope = tu.openai_streaming_response("hello")

    equals(true, openai.is_streaming_finished(done))
    equals(false, openai.is_streaming_finished(nope))
  end)

  it("should return no content if streaming is finished", function()
    local success = tu.openai_streaming_response("hello", "done")
    equals("", openai.get_text(success))
  end)

  it("should build streaming request for chat", function()
    local opts = tu.build_completion_opts({ provider = "openai", feature = "chat" })
    local chat = {
      { role = "user", content = "a" },
      { role = "assistant", content = "b" },
      { role = "user", content = "c" },
    }
    local body = openai.build_request(chat, opts)

    equals(chat, body.messages)
    equals(opts.temperature, body.temperature)
    equals(opts.model, body.model)
    equals(opts.tokens, body.max_tokens)
    equals(opts.stream, body.stream)
  end)

  it("should build streaming request for edit", function()
    local opts = tu.build_completion_opts({ provider = "openai", feature = "edit" })
    local prompt = "hello"
    local body = openai.build_request(prompt, opts)

    equals({ role = "user", content = "hello" }, body.messages[2])
    equals(opts.temperature, body.temperature)
    equals(opts.model, body.model)
    equals(opts.tokens, body.max_tokens)
    equals(true, body.stream)
  end)

  it("should build streaming request with o1 reasoning model", function()
    local opts = tu.build_completion_opts({ provider = "openai", feature = "edit", model = "o1" })
    local prompt = "hello"
    local body = openai.build_request(prompt, opts)

    equals({ role = "user", content = "hello" }, body.messages[2])
    equals(opts.model, body.model)
    equals(true, body.stream)
    -- not set
    equals(nil, body.temperature)
    equals(nil, body.max_tokens)
  end)

  it("should build streaming request with o3-mini reasoning model", function()
    local opts =
      tu.build_completion_opts({ provider = "openai", feature = "edit", model = "o3-mini" })
    local prompt = "hello"
    local body = openai.build_request(prompt, opts)

    equals({ role = "user", content = "hello" }, body.messages[2])
    equals(opts.model, body.model)
    equals(true, body.stream)
    -- not set
    equals(nil, body.temperature)
    equals(nil, body.max_tokens)
  end)

  it("should build non-streaming request", function()
    local opts = tu.build_completion_opts({ provider = "openai", feature = "edit", stream = false })
    local prompt = "hello"
    local body = openai.build_request(prompt, opts)

    equals(false, body.stream)
  end)

  it("should build json format request", function()
    local opts = tu.build_completion_opts({ provider = "openai", feature = "edit", json = false })
    local prompt = "hello"
    local body = openai.build_request(prompt, opts)

    equals(nil, body.response_format)

    opts = tu.build_completion_opts({ provider = "openai", feature = "edit", json = true })
    body = openai.build_request(prompt, opts)

    equals("json_object", body.response_format.type)
  end)
end)
