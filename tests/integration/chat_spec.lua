local tu = require("tests.testutils")
local buffer = require("enlighten.buffer")

-- stylua: ignore
local content_1 = {
  "In lines of", "code, we", "find our way,\n",
  "Through ", "logic's path, bot","h night and"," day.\nWith ",
  "functions",", loops, and vari","ables bright,","\nWe",
  " craft ","our dreams in ","digital light.\n",
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

  before_each(function()
    ---@type Enlighten
    enlighten = require("enlighten")
    enlighten.setup()

    -- Override the exec method so we can capture the stdout handler.
    ---@diagnostic disable-next-line: duplicate-set-field
    enlighten.ai.exec = function(_, _, on_stdout_chunk, on_complete)
      buffer_chunk = on_stdout_chunk
      complete = on_complete
    end
  end)

  after_each(function()
    enlighten.chat_history = {}
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
    local buf = vim.api.nvim_get_current_buf()

    tu.feedkeys("ihello<Esc><CR>")
    stream(content_1)

    assert.are.same(
      "\n\n>>> Developer\n\nhello\n\n>>> Assistant\n\n"
        .. table.concat(content_1, "")
        .. "\n\n>>> Developer\n\n",
      buffer.get_content(buf)
    )

    tu.feedkeys("imore<Esc><CR>")
    stream(content_2)

    assert.are.same(
      "\n\n>>> Developer\n\nhello\n\n>>> Assistant\n\n"
        .. table.concat(content_1, "")
        .. "\n\n>>> Developer\n\nmore\n\n>>> Assistant\n\n"
        .. table.concat(content_2, "")
        .. "\n\n>>> Developer\n\n",
      buffer.get_content(buf)
    )

    vim.api.nvim_buf_delete(buf, {})
  end)

  it("should copy selected snippet to chat", function()
    tu.prepare_buffer("some\ncontent\nto\ncopy")

    -- Select the first four lines of the buffer
    tu.feedkeys("Vjjj")

    vim.cmd("lua require('enlighten'):chat()")

    local buf = vim.api.nvim_get_current_buf()
    assert.are.same("\n\n>>> Developer\n\nsome\ncontent\nto\ncopy\n\n", buffer.get_content(buf))
  end)

  it("should be able to scroll chat history", function()
    enlighten.chat_history = { { "abc" }, { "def" } }
    vim.cmd("lua require('enlighten').chat()")
    local buf = vim.api.nvim_get_current_buf()

    tu.feedkeys("<Esc><C-o>")
    tu.scheduled_equals("abc", buffer.get_content(buf))

    tu.feedkeys("<C-o>")
    tu.scheduled_equals("def", buffer.get_content(buf))

    tu.feedkeys("<C-i>")
    tu.scheduled_equals("abc", buffer.get_content(buf))

    tu.feedkeys("<C-i>")
    tu.scheduled_equals("\n\n>>> Developer\n\n", buffer.get_content(buf))

    vim.api.nvim_buf_delete(buf, {})
  end)

  it("should save convo to history after completion", function()
    vim.cmd("lua require('enlighten').chat()")

    tu.feedkeys("ihello<Esc><CR>")
    stream(content_1)

    tu.feedkeys("<Esc>q")
    vim.cmd("lua require('enlighten').chat()")
    local buf = vim.api.nvim_get_current_buf()

    tu.feedkeys("<Esc><C-o>")
    local want = "\n\n>>> Developer\n\nhello\n\n>>> Assistant\n\n"
      .. table.concat(content_1, "")
      .. "\n\n>>> Developer\n\n"

    tu.scheduled_equals(want, buffer.get_content(buf))
    assert.are.same({ vim.split(want, "\n") }, enlighten.chat_history)

    vim.api.nvim_buf_delete(buf, {})
  end)
end)
