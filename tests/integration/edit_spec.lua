local tu = require("tests.testutils")
local buffer = require("enlighten.buffer")
local ai = require("enlighten.ai")
local stub = require("luassert.stub")

-- stylua: ignore
local content_1 = {
  "In lines of code, we find our way,",
  "",
  "Through logic's path, both night and day.",
  "",
  "With functions, loops, and variables bright,",
  "",
  "We craft our dreams in digital light.",
}

-- stylua: ignore
local content_2 = {
  "local ", "numbers =", "{ 1, 2,", " 3, 4", "}\n",
  "local", " sum = ", "0\n",
  "for ", "i = 1", ", #numbers do", "\n  ",
  " sum = ", "sum + ", "numbers[i]\n",
  "end",
}

describe("edit", function()
  local target_buf
  local buffer_chunk
  local complete
  local enlighten

  before_each(function()
    target_buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, content_1)
    vim.api.nvim_set_current_buf(target_buf)

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
    enlighten.edit_history = {}
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

  it("should be able to edit code in the buffer", function()
    -- Select the first four lines of the buffer
    tu.feedkeys("Vjjj")

    -- Open the prompt and get the buffer
    vim.cmd("lua require('enlighten').edit()")
    local buf = vim.api.nvim_get_current_buf()

    -- Enter our prompt
    tu.feedkeys("ihello<Esc>")
    assert.are.same("hello", buffer.get_content(buf))

    -- Submit prompt and stream some content back in
    tu.feedkeys("<CR>")
    stream(content_2)

    -- New content is written, last two lines of the buffer remain
    assert.are.same(
      table.concat(content_2, "") .. "\n" .. content_1[5] .. "\n\n" .. content_1[7],
      buffer.get_content(target_buf)
    )
  end)

  it("should be able to generate code in the buffer", function()
    -- Open the prompt and get the buffer
    vim.cmd("lua require('enlighten').edit()")
    local buf = vim.api.nvim_get_current_buf()

    -- Enter our prompt
    tu.feedkeys("ihello<Esc>")
    assert.are.same("hello", buffer.get_content(buf))

    -- Submit the prompt and stream some content back in
    tu.feedkeys("<CR>")
    stream(content_2)

    -- New content is written
    table.remove(content_1, 1)
    assert.are.same(
      table.concat(content_2, "") .. "\n" .. table.concat(content_1, "\n"),
      buffer.get_content(target_buf)
    )
  end)
end)
