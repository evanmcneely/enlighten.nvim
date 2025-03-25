local tu = require("tests.testutils")
local assertions = require("tests.assertions")
local buffer = require("enlighten.buffer")
local ai = require("enlighten.ai")
local stub = require("luassert.stub")

-- stylua: ignore
local content_1 = {
  "In lines of", "code, we", "find our way,\n",
  "Through ", "logic's path, bot","h night and"," day.\nWith ",
  "functions",", loops, and vari","ables bright,","\nWe",
  " craft ","our dreams in ","digital light.",
}

-- stylua: ignore
local content_2 = {
  "local ", "numbers =", "{ 1, 2,", " 3, 4", "}\n",
  "local", " sum = ", "0\n\n",
  "for ", "i = 1", ", #numbers do", "\n  ",
  " sum = ", "sum + ", "numbers[i]\n",
  "end",
}

describe("chat", function()
  local buffer_chunk
  local complete
  local enlighten
  local buf

  before_each(function()
    ---@type Enlighten
    enlighten = require("enlighten")
    enlighten.setup()

    -- Override the exec method so we can capture the stdout handler.
    ---@diagnostic disable-next-line: duplicate-set-field
    stub.new(ai, "exec", function(_, _, on_stdout_chunk, on_complete)
      buffer_chunk = on_stdout_chunk
      complete = on_complete
    end)
  end)

  after_each(function()
    enlighten.chat_history = {}
    vim.api.nvim_buf_delete(buf, {})
  end)

  -- Mock the streaming of response chunks, stop sequence and copmletion
  ---@param content string[]
  local function stream(content)
    for _, chunk in ipairs(content) do
      buffer_chunk("data: " .. vim.json.encode(tu.openai_response(chunk)))
    end
    buffer_chunk(vim.json.encode(tu.openai_response("", "stop")))
    complete()
  end

  it("should be able to have a chat conversation", function()
    vim.cmd("lua require('enlighten').chat()")
    buf = vim.api.nvim_get_current_buf()

    tu.feedkeys("ihello<Esc><CR>")
    stream(content_1)

    local content = buffer.get_content(buf)
    assertions.contains("hello", content)
    assertions.contains(table.concat(content_1, ""), content)

    tu.feedkeys("imore<Esc><CR>")
    stream(content_2)

    content = buffer.get_content(buf)
    assertions.contains("hello", content)
    assertions.contains(table.concat(content_1, ""), content)
    assertions.contains("more", content)
    assertions.contains(table.concat(content_2, ""), content)
  end)

  it("should copy selected snippet to chat", function()
    tu.prepare_buffer("some\ncontent\nto\ncopy")

    -- Select the first four lines of the buffer
    tu.feedkeys("Vjjj")

    vim.cmd("lua require('enlighten'):chat()")

    buf = vim.api.nvim_get_current_buf()
    assertions.contains("some\ncontent\nto\ncopy", buffer.get_content(buf))
  end)

  it("should save convo to history after completion", function()
    vim.cmd("lua require('enlighten').chat()")

    tu.feedkeys("ihello<Esc><CR>")
    stream(content_1)

    tu.feedkeys("<Esc>q")
    vim.cmd("lua require('enlighten').chat()")
    buf = vim.api.nvim_get_current_buf()

    tu.feedkeys("<Esc><C-o>")

    local content = buffer.get_content(buf)
    assertions.contains("hello", content)
    assertions.contains(table.concat(content_1, ""), content)
  end)
end)
