local Chat = require("enlighten.chat")
local tu = require("tests.testutils")
local assertions = require("tests.assertions")

-- stylua: ignore
local content_1 = {
  "In lines of", "code, we", "find our way,\n",
  "Through ", "logic's path, bot","h night and"," day.\nWith ",
  "functions",", loops, and vari","ables bright,","\nWe",
  " craft ","our dreams in ","digital light.",
}

describe("Chat feature", function()
  local buffer

  before_each(function()
    buffer = tu.prepare_buffer(table.concat(content_1), "")
  end)

  it("should build prompt for editing buffer", function()
    local messages = '{{"role": "user", "content": "hello"}}'
    local range = {
      col_start = 0,
      col_end = 0,
      row_start = 1,
      row_end = 2,
    } ---@type SelectionRange
    local prompt = Chat._build_edit_prompt(messages, range, buffer, 2)
    assertions.contains(messages, prompt)
    assertions.contains(
      "Snippet:\nThrough logic's path, both night and day.\nWith functions, loops, and variables bright,",
      prompt
    )
    assertions.contains("Context above:\nIn lines ofcode, wefind our way,", prompt)
    assertions.contains("Context below:\nWe craft our dreams in digital light.", prompt)
  end)
end)
