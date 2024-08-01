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
    writer:on_data("hello")
    writer:on_data(" ")
    writer:on_data("world")

    -- No text should be written/changed yet
    equals(buffer.get_content(buf), content)

    -- Text should be written after new line
    writer:on_data("\n")
    equals("aaa\nbbb\nhello world\nccc\nddd\neee", buffer.get_content(buf))
  end)

  it("should handle double new line characters as input", function()
    local writer = DiffWriter:new(buf, range)

    writer:on_data("\n\n")
    equals("aaa\nbbb\n\n\nccc\nddd\neee", buffer.get_content(buf))
  end)

  it("should handle double new line characters separated by text as input", function()
    local writer = DiffWriter:new(buf, range)

    writer:on_data("\nhere\n")
    equals("aaa\nbbb\n\nhere\nccc\nddd\neee", buffer.get_content(buf))
  end)

  it("should not write characters after a new line character", function()
    local writer = DiffWriter:new(buf, range)

    -- The text "here" remains to accumulate on new line
    writer:on_data("\nhere")
    equals("aaa\nbbb\n\nccc\nddd\neee", buffer.get_content(buf))
  end)

  it("should write all unwritten text on complete", function()
    local writer = DiffWriter:new(buf, range)

    -- Text is received that is unwritten
    writer:on_data("hello world")
    equals(buffer.get_content(buf), content)

    -- Now text get written
    writer:on_complete()
    equals("aaa\nbbb\nhello world\nccc\nddd\neee", buffer.get_content(buf))
  end)

  describe("normal", function()
    it("should write to the middle of the buffer", function()
      local writer = DiffWriter:new(buf, range)

      writer:on_data("hello\n")
      equals("aaa\nbbb\nhello\nccc\nddd\neee", buffer.get_content(buf))
    end)

    it("should write to the end of the buffer", function()
      range.row_start = 5
      range.row_end = 5
      local writer = DiffWriter:new(buf, range)

      writer:on_data("hello\n")
      equals("aaa\nbbb\nccc\nddd\neee\nhello", buffer.get_content(buf))
    end)

    it("should write to the beginning of the buffer", function()
      range.row_start = 0
      range.row_end = 0
      local writer = DiffWriter:new(buf, range)

      writer:on_data("hello\n")
      equals("hello\naaa\nbbb\nccc\nddd\neee", buffer.get_content(buf))
    end)

    it("should ignore columns in range (only write lines)", function()
      range.col_start = 2
      range.col_end = 2
      local writer = DiffWriter:new(buf, range)

      writer:on_data("hello\n")
      equals("aaa\nbbb\nhello\nccc\nddd\neee", buffer.get_content(buf))
    end)

    it("should reset buffer content on reset", function()
      local writer = DiffWriter:new(buf, range)

      writer:on_data("hello world\n")
      writer:on_complete()
      writer:reset()

      equals(content, buffer.get_content(buf))
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

      writer:on_data("hello\n")
      equals("aaa\nbbb\nhello\nddd\neee", buffer.get_content(buf))
    end)

    it("should replace multiple lines with new content until end of range", function()
      local writer = DiffWriter:new(buf, range)

      writer:on_data("one\n")
      equals("aaa\nbbb\none\nddd\neee", buffer.get_content(buf))
      writer:on_data("two\n")
      equals("aaa\nbbb\none\ntwo\neee", buffer.get_content(buf))

      -- Insterts new text now
      writer:on_data("three\n")
      equals("aaa\nbbb\none\ntwo\nthree\neee", buffer.get_content(buf))
    end)

    it("should remove excess selected lines on complete", function()
      range.row_start = 1
      local writer = DiffWriter:new(buf, range)

      writer:on_data("one\n")
      writer:on_complete()

      -- This is current behaviour
      -- Expected behaviour might be "aaa\none\neee" so that content is removed
      -- and the line with that content is removed
      equals("aaa\none\neee", buffer.get_content(buf))
    end)

    it("should reset buffer content on reset when rows are selected", function()
      local writer = DiffWriter:new(buf, range)

      writer:on_data("hello world\n")
      writer:on_complete()
      writer:reset()

      equals(content, buffer.get_content(buf))
    end)

    it("should reset buffer content on reset when only columns are selected", function()
      range.row_start = 3
      range.col_end = 1
      local writer = DiffWriter:new(buf, range)

      writer:on_data("hello world\n")
      writer:on_complete()
      writer:reset()

      equals(content, buffer.get_content(buf))
    end)
  end)

  describe("highlights", function()
    before_each(function()
      range = {
        row_start = 2,
        row_end = 3,
        col_start = 0,
        col_end = 0,
      }
    end)

    it("should highlight focused line while generating", function()
      local writer = DiffWriter:new(buf, range)

      assert.are_nil(writer.focused_line_id)

      writer:on_data("hello\n")

      local ext = vim.api.nvim_buf_get_extmark_by_id(
        buf,
        writer.line_ns_id,
        writer.focused_line_id,
        { details = true }
      )
      equals(ext[1], 3)
      equals(ext[3].hl_group, "CursorLine")

      writer:on_data("hello\n")

      ext = vim.api.nvim_buf_get_extmark_by_id(
        buf,
        writer.line_ns_id,
        writer.focused_line_id,
        { details = true }
      )
      equals(ext[1], 4)
      equals(ext[3].hl_group, "CursorLine")
    end)

    -- it("should highlight diffs", function()
    --   local writer = DiffWriter:new(buf, range)
    --
    --   writer:on_data("hello\n")
    --
    --   local ext = vim.api.nvim_buf_get_extmarks(buf, writer.diff_ns_id, 0, -1, { details = true })
    --   print(vim.inspect(ext))
    --   equals(true, false)
    -- end)

    it("should reset diff highlights", function()
      local writer = DiffWriter:new(buf, range)

      writer:on_data("hello\n")

      local ext = vim.api.nvim_buf_get_extmarks(buf, writer.diff_ns_id, 0, -1, { details = true })
      assert.are.not_equal({}, ext)

      writer:reset()

      ext = vim.api.nvim_buf_get_extmarks(buf, writer.diff_ns_id, 0, -1, { details = true })
      equals({}, ext)
    end)
  end)
end)
