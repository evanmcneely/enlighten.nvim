---@diagnostic disable: undefined-field

local DiffWriter = require("enlighten.writer.diff")
local tu = require("tests.testutils")
local buffer = require("enlighten.buffer")

local equals = assert.are.same

describe("DiffWriter", function()
  local content = "aaa\nbbb\nccc\nddd\neee"
  local buf
  ---@type Range
  local range

  before_each(function()
    buf = tu.prepare_buffer(content)
    range = {
      row_start = 2,
      row_end = 2,
      col_start = 0,
      col_end = 0,
    }
  end)

  it("should ignore 'stop' finish reason", function()
    local writer = DiffWriter:new(buf, range)

    writer:on_data(tu.openai_response("", "stop"))
    equals(buffer.get_content(buf), content)
  end)

  it("should call on_done when complete", function()
    local done = false
    local function on_done()
      done = true
    end
    local writer = DiffWriter:new(buf, range, on_done)

    writer:on_complete()

    equals(true, done)
  end)

  it("should not write to buffer until there is a complete line", function()
    local writer = DiffWriter:new(buf, range)

    -- Text is streaming in
    writer:on_data(tu.openai_response("hello"))
    writer:on_data(tu.openai_response(" "))
    writer:on_data(tu.openai_response("world"))

    -- No text should be written/changed yet
    equals(buffer.get_content(buf), content)

    -- Text should be written after new line
    writer:on_data(tu.openai_response("\n"))
    equals("aaa\nbbb\nhello world\nccc\nddd\neee", buffer.get_content(buf))
  end)

  it("should handle double new line characters as input", function()
    local writer = DiffWriter:new(buf, range)

    writer:on_data(tu.openai_response("\n\n"))
    equals("aaa\nbbb\n\n\nccc\nddd\neee", buffer.get_content(buf))
  end)

  it("should handle double new line characters separated by text as input", function()
    local writer = DiffWriter:new(buf, range)

    writer:on_data(tu.openai_response("\nhere\n"))
    equals("aaa\nbbb\n\nhere\nccc\nddd\neee", buffer.get_content(buf))
  end)

  it("should not write characters after a new line character", function()
    local writer = DiffWriter:new(buf, range)

    -- The text "here" remains to accumulate on new line
    writer:on_data(tu.openai_response("\nhere"))
    equals("aaa\nbbb\n\nccc\nddd\neee", buffer.get_content(buf))
  end)

  it("should write all unwritten text on complete", function()
    local writer = DiffWriter:new(buf, range)

    -- Text is received that is unwritten
    writer:on_data(tu.openai_response("hello world"))
    equals(buffer.get_content(buf), content)

    -- Now text get written
    writer:on_complete()
    equals("aaa\nbbb\nhello world\nccc\nddd\neee", buffer.get_content(buf))
  end)

  describe("normal", function()
    it("should write to the middle of the buffer", function()
      local writer = DiffWriter:new(buf, range)

      writer:on_data(tu.openai_response("hello\n"))
      equals("aaa\nbbb\nhello\nccc\nddd\neee", buffer.get_content(buf))
    end)

    it("should write to the end of the buffer", function()
      range.row_start = 5
      range.row_end = 5
      local writer = DiffWriter:new(buf, range)

      writer:on_data(tu.openai_response("hello\n"))
      equals("aaa\nbbb\nccc\nddd\neee\nhello", buffer.get_content(buf))
    end)

    it("should write to the beginning of the buffer", function()
      range.row_start = 0
      range.row_end = 0
      local writer = DiffWriter:new(buf, range)

      writer:on_data(tu.openai_response("hello\n"))
      equals("hello\naaa\nbbb\nccc\nddd\neee", buffer.get_content(buf))
    end)

    it("should ignore columns in range (only write lines)", function()
      range.col_start = 2
      range.col_end = 2
      local writer = DiffWriter:new(buf, range)

      writer:on_data(tu.openai_response("hello\n"))
      equals("aaa\nbbb\nhello\nccc\nddd\neee", buffer.get_content(buf))
    end)
  end)

  describe("selections", function()
    before_each(function()
      range = {
        row_start = 2,
        row_end = 3,
        col_start = 0,
        col_end = 0,
      }
    end)

    it("should replace lines with new content", function()
      local writer = DiffWriter:new(buf, range)

      writer:on_data(tu.openai_response("hello\n"))
      equals("aaa\nbbb\nhello\nddd\neee", buffer.get_content(buf))
    end)

    it("should replace multiple lines with new content until end of range", function()
      local writer = DiffWriter:new(buf, range)

      writer:on_data(tu.openai_response("one\n"))
      equals("aaa\nbbb\none\nddd\neee", buffer.get_content(buf))
      writer:on_data(tu.openai_response("two\n"))
      equals("aaa\nbbb\none\ntwo\neee", buffer.get_content(buf))

      -- Insterts new text now
      writer:on_data(tu.openai_response("three\n"))
      equals("aaa\nbbb\none\ntwo\nthree\neee", buffer.get_content(buf))
    end)

    it("should remove excess selected lines on complete", function()
      range.row_start = 1
      local writer = DiffWriter:new(buf, range)

      writer:on_data(tu.openai_response("one\n"))
      writer:on_complete()

      -- This is current behaviour
      -- Expected behaviour might be "aaa\none\neee" so that content is removed
      -- and the line with that content is removed
      equals("aaa\none\n\neee", buffer.get_content(buf))
    end)
  end)
end)
