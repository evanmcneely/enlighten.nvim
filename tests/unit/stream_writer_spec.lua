local StreamWriter = require("enlighten.writer.stream")
local tu = require("tests.testutils")
local buffer = require("enlighten.buffer")

local equals = assert.are.same

describe("StreamWriter", function()
  local content = "aaa\nbbb\nccc\nddd\neee"
  local buf
  local win
  ---@type number[]

  before_each(function()
    vim.cmd("vsplit")
    win = vim.api.nvim_get_current_win()
    buf = tu.prepare_buffer(content)
    vim.api.nvim_win_set_buf(win, buf)
  end)

  it("should call on_done when complete", function()
    local done = false
    local function on_done()
      done = true
    end

    local writer = StreamWriter:new(win, buf, on_done)

    writer:on_complete()
    equals(true, done)
  end)

  it("should have active state on start and inactive state on complete", function()
    local writer = StreamWriter:new(win, buf)

    equals(false, writer.active)

    writer:start()
    equals(true, writer.active)

    writer:on_complete()
    equals(false, writer.active)
  end)

  it("should not write text when stopped", function()
    local writer = StreamWriter:new(win, buf)
    writer:start()

    writer:stop()

    writer:on_data("stuff")
    writer:on_data("stuff")
    writer:on_data("stuff")
    equals(content, buffer.get_content(buf))
  end)

  it("should write text to the end of a buffer", function()
    local writer = StreamWriter:new(win, buf)
    writer:start()

    writer:on_data("stuff")
    -- you might expect "aaa\nbbb\nccc\nddd\neee\nstuff" but this is how it is for now
    equals("aaa\nbbb\nccc\nddd\nstuffeee", buffer.get_content(buf))
  end)

  it("should write new line characters at the end of a buffer", function()
    local writer = StreamWriter:new(win, buf)
    writer:start()

    writer:on_data("\n")
    equals("aaa\nbbb\nccc\nddd\neee\n", buffer.get_content(buf))
  end)

  it("should write a mix of text and new line characters", function()
    local writer = StreamWriter:new(win, buf)
    writer:start()

    writer:on_data("\nstuff\n")
    equals("aaa\nbbb\nccc\nddd\neee\nstuff\n", buffer.get_content(buf))
  end)
end)
