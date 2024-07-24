---@diagnostic disable: undefined-field

local StreamWriter = require("enlighten.writer.stream")
local tu = require("tests.testutils")
local buffer = require("enlighten.buffer")

local equals = assert.are.same

describe("StreamWriter", function()
  local content = "aaa\nbbb\nccc\nddd\neee"
  local buf
  local win
  ---@type number[]
  local pos

  before_each(function()
    buf = tu.prepare_buffer(content)
    win = vim.api.nvim_open_win(buf, true, { split = "left" })
    pos = { 3, 3 }
  end)

  it("should ignore 'stop' finish reason", function()
    local writer = StreamWriter:new(win, buf, pos)

    writer:on_data(tu.openai_response("", "stop"))
    equals(buffer.get_content(buf), content)
  end)

  it("should call on_done when complete", function()
    local done = false
    local function on_done()
      done = true
    end

    local writer = StreamWriter:new(win, buf, pos, on_done)

    writer:on_complete()
    equals(true, done)
  end)

  it("should write text to the middle of a buffer", function()
    local writer = StreamWriter:new(win, buf, pos)

    writer:on_data(tu.openai_response("stuff"))
    equals("aaa\nbbb\ncccstuff\nddd\neee", buffer.get_content(buf))
  end)

  it("should write text to the start of a buffer", function()
    local writer = StreamWriter:new(win, buf, { 1, 0 })

    writer:on_data(tu.openai_response("stuff"))
    equals("stuffaaa\nbbb\nccc\nddd\neee", buffer.get_content(buf))
  end)

  it("should write text to the end of a buffer", function()
    local writer = StreamWriter:new(win, buf, { 5, 3 })

    writer:on_data(tu.openai_response("stuff"))
    equals("aaa\nbbb\nccc\nddd\neeestuff", buffer.get_content(buf))
  end)

  it("should write new line characters in the middle of a buffer", function()
    local writer = StreamWriter:new(win, buf, pos)

    writer:on_data(tu.openai_response("\n"))
    equals("aaa\nbbb\nccc\n\nddd\neee", buffer.get_content(buf))
  end)

  it("should write multiple new line characters in the middle of a buffer", function()
    local writer = StreamWriter:new(win, buf, pos)

    writer:on_data(tu.openai_response("\n\n"))
    equals("aaa\nbbb\nccc\n\n\nddd\neee", buffer.get_content(buf))
  end)

  it("should write new line characters at the end of a buffer", function()
    local writer = StreamWriter:new(win, buf, { 5, 3 })

    writer:on_data(tu.openai_response("\n"))
    equals("aaa\nbbb\nccc\nddd\neee\n", buffer.get_content(buf))
  end)

  it("should write a mix of text and new line characters", function()
    local writer = StreamWriter:new(win, buf, pos)

    writer:on_data(tu.openai_response("\nstuff\n"))
    equals("aaa\nbbb\nccc\nstuff\n\nddd\neee", buffer.get_content(buf))
  end)
end)
