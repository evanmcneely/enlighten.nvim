local Chat = require("enlighten.chat")
local tu = require("tests.testutils")
local assertions = require("tests.assertions")

local content_1 = {
  "In lines of code, we find our way,",
  "Through logic's path, both night and day.",
  "With functions, loops, and variables bright,",
  "We craft our dreams in digital light.",
}

describe("Chat feature", function()
  local buffer

  before_each(function()
    buffer = tu.prepare_buffer(table.concat(content_1, "\n"))
  end)

  it("should build prompt for editing buffer", function()
    local messages = '{{"role": "user", "content": "hello"}}'
    local range = {
      col_start = 0,
      col_end = 0,
      row_start = 1,
      row_end = 2,
    }

    local prompt = Chat._build_edit_prompt(messages, range, buffer, 2)

    assertions.contains(messages, prompt)
    assertions.contains("Context above:\nIn lines of code, we find our way,", prompt)
    assertions.contains("Context below:\nWe craft our dreams in digital light.", prompt)
    assertions.contains(
      "Snippet:\nThrough logic's path, both night and day.\nWith functions, loops, and variables bright,",
      prompt
    )
  end)

  it("should build prompt for getting editing range", function()
    local messages = '{{"role": "user", "content": "hello"}}'

    local prompt = Chat._build_get_range_prompt(messages, buffer)

    assertions.contains(messages, prompt)
    assertions.contains(
      table.concat({
        "1: In lines of code, we find our way,",
        "2: Through logic's path, both night and day.",
        "3: With functions, loops, and variables bright,",
        "4: We craft our dreams in digital light.",
      }, "\n"),
      prompt
    )
  end)
end)
