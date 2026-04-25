local tu = require("tests.testutils")
local anthropic = require("enlighten.ai.anthropic")

local equals = assert.are.same

describe("provider anthropic", function()
  it("should identify errors in streamed responses", function()
    local success = tu.anthropic_streaming_response("content_block_delta", "yop")
    local error = tu.anthropic_error()

    equals(true, anthropic.is_error(error))
    equals(false, anthropic.is_error(success))
  end)

  it("should return error messages", function()
    local error = tu.anthropic_error()
    equals(error.error.message, anthropic.get_error_message(error))
  end)

  it("should return no text for message_start events", function()
    local res = tu.anthropic_streaming_response("message_start")
    equals("", anthropic.get_text(res))
  end)

  it("should return no text for content_block_start events", function()
    local res = tu.anthropic_streaming_response("content_block_start")
    equals("", anthropic.get_text(res))
  end)

  it("should return no text for ping events", function()
    local res = tu.anthropic_streaming_response("ping")
    equals("", anthropic.get_text(res))
  end)

  it("should text for content_block_delta events", function()
    local res = tu.anthropic_streaming_response("content_block_delta", "hello")
    equals("hello", anthropic.get_text(res))
  end)

  it("should return no text for content_block_stop events", function()
    local res = tu.anthropic_streaming_response("content_block_stop")
    equals("", anthropic.get_text(res))
  end)

  it("should return no text for message_delta events", function()
    local res = tu.anthropic_streaming_response("message_delta")
    equals("", anthropic.get_text(res))
  end)

  it("should return no text for message_stop events", function()
    local res = tu.anthropic_streaming_response("message_stop")
    equals("", anthropic.get_text(res))
  end)

  it("should identify when streaming has finished", function()
    local start = tu.anthropic_streaming_response("message_start")
    local stop = tu.anthropic_streaming_response("message_stop")
    local delta = tu.anthropic_streaming_response("message_delta")
    local block_start = tu.anthropic_streaming_response("content_block_start")
    local block_delta = tu.anthropic_streaming_response("content_block_delta", "hello")
    local block_stop = tu.anthropic_streaming_response("content_block_stop")
    local ping = tu.anthropic_streaming_response("ping")

    equals(false, anthropic.is_streaming_finished(start))
    equals(true, anthropic.is_streaming_finished(stop))
    equals(false, anthropic.is_streaming_finished(delta))
    equals(false, anthropic.is_streaming_finished(block_start))
    equals(false, anthropic.is_streaming_finished(block_delta))
    equals(false, anthropic.is_streaming_finished(block_stop))
    equals(false, anthropic.is_streaming_finished(ping))
  end)

  it("should return text from response", function()
    local res = tu.anthropic_response("hello")
    equals("hello", anthropic.get_text(res))
  end)

  it("should build streaming request for chat", function()
    local opts = tu.build_completion_opts({ provider = "anthropic", feature = "chat" })
    local chat = {
      { role = "user", content = "a" },
      { role = "assistant", content = "b" },
      { role = "user", content = "c" },
    }
    local body = anthropic.build_request(chat, opts)

    equals(chat, body.messages)
    equals(opts.temperature, body.temperature)
    equals(opts.model, body.model)
    equals(opts.tokens, body.max_tokens)
    equals(opts.stream, body.stream)
  end)

  it("should build streaming request for edit", function()
    local opts = tu.build_completion_opts({ provider = "anthropic", feature = "edit" })
    local prompt = "hello"
    local body = anthropic.build_request(prompt, opts)

    equals({ { role = "user", content = "hello" } }, body.messages)
    equals(opts.temperature, body.temperature)
    equals(opts.model, body.model)
    equals(opts.tokens, body.max_tokens)
    equals(true, body.stream)
  end)

  describe("strip_code_block", function()
    it("should strip opening and closing fences with language tag", function()
      local input = "```python\nprint('hello')\nprint('world')\n```"
      equals("print('hello')\nprint('world')", anthropic.strip_code_block(input))
    end)

    it("should strip fences with different language tags", function()
      equals("local x = 1", anthropic.strip_code_block("```lua\nlocal x = 1\n```"))
      equals("const x = 1", anthropic.strip_code_block("```javascript\nconst x = 1\n```"))
    end)

    it("should strip fences with no language tag", function()
      equals("hello world", anthropic.strip_code_block("```\nhello world\n```"))
    end)

    it("should return text unchanged when no fences present", function()
      local input = "print('hello')\nprint('world')"
      equals(input, anthropic.strip_code_block(input))
    end)

    it("should preserve interior code fences", function()
      local input = "```python\ncode with ``` inside\n```"
      equals("code with ``` inside", anthropic.strip_code_block(input))
    end)

    it("should handle trailing whitespace on closing fence", function()
      local input = "```python\nprint('hi')\n```  "
      equals("print('hi')", anthropic.strip_code_block(input))
    end)
  end)

  describe("create_text_filter", function()
    it("should return nil for chat feature", function()
      equals(nil, anthropic.create_text_filter("chat"))
    end)

    it("should return a filter for edit feature", function()
      local filter = anthropic.create_text_filter("edit")
      assert.is_not_nil(filter)
      assert.is_not_nil(filter.process)
      assert.is_not_nil(filter.flush)
    end)

    it("should return a filter for get_range feature", function()
      local filter = anthropic.create_text_filter("get_range")
      assert.is_not_nil(filter)
    end)

    it("should strip opening fence from streamed text", function()
      local filter = anthropic.create_text_filter("edit")
      -- First chunk contains opening fence and some code
      local result = filter.process("```python\nprint('hello')\n")
      equals("print('hello')\n", result)
    end)

    it("should handle opening fence split across chunks", function()
      local filter = anthropic.create_text_filter("edit")
      -- First chunk is incomplete (no newline yet)
      equals("", filter.process("```py"))
      -- Second chunk completes the first line
      local result = filter.process("thon\nprint('hello')\n")
      equals("print('hello')\n", result)
    end)

    it("should strip closing fence on flush", function()
      local filter = anthropic.create_text_filter("edit")
      filter.process("```python\nprint('hello')\n")
      -- Last chunk is the closing fence
      filter.process("```")
      equals("", filter.flush())
    end)

    it("should strip closing fence with trailing whitespace", function()
      local filter = anthropic.create_text_filter("edit")
      filter.process("```python\nprint('hello')\n")
      filter.process("```  ")
      equals("", filter.flush())
    end)

    it("should pass through text without fences", function()
      local filter = anthropic.create_text_filter("edit")
      local result = filter.process("print('hello')\n")
      -- First line is checked but not a fence, so it passes through
      -- But the incomplete trailing content is held back
      equals("print('hello')\n", result)
      equals("", filter.flush())
    end)

    it("should flush remaining non-fence text", function()
      local filter = anthropic.create_text_filter("edit")
      filter.process("line1\n")
      -- Partial last line that is not a fence
      filter.process("line2")
      equals("line2", filter.flush())
    end)

    it("should handle complete response in one chunk", function()
      local filter = anthropic.create_text_filter("edit")
      local result = filter.process("```python\nprint('hello')\nprint('world')\n")
      equals("print('hello')\nprint('world')\n", result)
      filter.process("```")
      equals("", filter.flush())
    end)

    it("should handle text arriving character by character", function()
      local filter = anthropic.create_text_filter("edit")
      local input = "```python\nprint('hi')\n```"
      local collected = ""
      for i = 1, #input do
        collected = collected .. filter.process(input:sub(i, i))
      end
      collected = collected .. filter.flush()
      equals("print('hi')\n", collected)
    end)

    it("should strip opening fence preceded by blank lines", function()
      local filter = anthropic.create_text_filter("edit")
      local collected = ""
      collected = collected .. filter.process("\n\n```go\nfunc main() {\n")
      collected = collected .. filter.process("}\n")
      collected = collected .. filter.flush()
      equals("func main() {\n}\n", collected)
    end)

    it("should strip opening fence preceded by blank lines across chunks", function()
      local filter = anthropic.create_text_filter("edit")
      local collected = ""
      -- First chunk is just blank lines, no content line yet
      collected = collected .. filter.process("\n\n")
      -- Second chunk has the fence and code
      collected = collected .. filter.process("```go\nfunc main() {\n}\n")
      collected = collected .. filter.flush()
      equals("func main() {\n}\n", collected)
    end)

    it("should strip opening fence preceded by whitespace-only lines", function()
      local filter = anthropic.create_text_filter("edit")
      local collected = ""
      collected = collected .. filter.process("  \n\t\n```lua\nlocal x = 1\n")
      collected = collected .. filter.flush()
      equals("local x = 1\n", collected)
    end)

    it("should preserve blank lines after opening fence", function()
      local filter = anthropic.create_text_filter("edit")
      local collected = ""
      collected = collected .. filter.process("```go\n\n\nfunc main() {\n}\n")
      collected = collected .. filter.flush()
      equals("\n\nfunc main() {\n}\n", collected)
    end)

    it("should strip closing fence and trailing blank lines", function()
      local filter = anthropic.create_text_filter("edit")
      local collected = ""
      collected = collected .. filter.process("```go\nfunc main() {\n}\n```\n\n")
      collected = collected .. filter.flush()
      equals("func main() {\n}\n", collected)
    end)

    it("should strip closing fence and trailing blank lines across chunks", function()
      local filter = anthropic.create_text_filter("edit")
      local collected = ""
      collected = collected .. filter.process("```go\nfunc main() {\n}\n```\n")
      collected = collected .. filter.process("\n")
      collected = collected .. filter.process("\n")
      collected = collected .. filter.flush()
      equals("func main() {\n}\n", collected)
    end)

    it("should strip closing fence arriving as its own chunk", function()
      local filter = anthropic.create_text_filter("edit")
      local collected = ""
      collected = collected .. filter.process("```go\nfunc main() {\n}\n")
      collected = collected .. filter.process("```\n")
      collected = collected .. filter.flush()
      equals("func main() {\n}\n", collected)
    end)

    it("should strip closing fence split across chunks", function()
      local filter = anthropic.create_text_filter("edit")
      local collected = ""
      collected = collected .. filter.process("```go\nfunc main() {\n}\n")
      collected = collected .. filter.process("``")
      collected = collected .. filter.process("`\n")
      collected = collected .. filter.flush()
      equals("func main() {\n}\n", collected)
    end)

    it("should preserve inline backticks in code content", function()
      local filter = anthropic.create_text_filter("edit")
      local collected = ""
      collected = collected .. filter.process('```lua\nlocal s = "```"\nprint(s)\n')
      collected = collected .. filter.flush()
      equals('local s = "```"\nprint(s)\n', collected)
    end)
  end)
end)
