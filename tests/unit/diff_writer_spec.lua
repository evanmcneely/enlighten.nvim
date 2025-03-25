local DiffWriter = require("enlighten.writer.diff")
local tu = require("tests.testutils")
local buffer = require("enlighten.buffer")
local assertions = require("tests.assertions")

local equals = assert.are.same

describe("DiffWriter", function()
  local content = "aaa\nbbb\nccc\nddd\neee"
  local buf
  local win
  ---@type SelectionRange
  local range
  local opts

  before_each(function()
    opts = { mode = "diff" }
    buf = tu.prepare_buffer(content)
    win = vim.api.nvim_get_current_win()
    range = {
      row_start = 2,
      row_end = 2,
      col_start = 0,
      col_end = 0,
    }
  end)

  it("should call on_done when complete", function()
    local done = false
    opts.on_done = function()
      done = true
    end
    local writer = DiffWriter:new(buf, win, range, opts)

    writer:on_complete()

    equals(true, done)
  end)

  it("should be active on start and inactive on complete", function()
    local writer = DiffWriter:new(buf, win, range, opts)
    equals(false, writer.active)

    writer:start()
    equals(true, writer.active)

    writer:on_complete()
    equals(false, writer.active)
  end)

  -- current expected behaviour is for the line the cursor is on to always be selected
  describe("normal", function()
    it("should not write to buffer until there is a complete line", function()
      local writer = DiffWriter:new(buf, win, range, opts)

      writer:on_data("hello")
      writer:on_data(" ")
      writer:on_data("world")

      -- No text should be written/changed yet
      equals(buffer.get_content(buf), content)

      -- Text should be written after new line
      writer:on_data("\n")
      equals("aaa\nbbb\nhello world\nddd\neee", buffer.get_content(buf))
    end)

    it("should handle double new line characters as input", function()
      local writer = DiffWriter:new(buf, win, range, opts)

      writer:on_data("\n\n")
      equals("aaa\nbbb\n\n\nddd\neee", buffer.get_content(buf))
    end)

    it("should handle double new line characters separated by text as input", function()
      local writer = DiffWriter:new(buf, win, range, opts)

      writer:on_data("\nhere\n")
      equals("aaa\nbbb\n\nhere\nddd\neee", buffer.get_content(buf))
    end)

    it("should not write characters after a new line character", function()
      local writer = DiffWriter:new(buf, win, range, opts)

      writer:on_data("\nhere")
      equals("aaa\nbbb\n\nddd\neee", buffer.get_content(buf))
    end)

    it("should write all unwritten text on complete", function()
      local writer = DiffWriter:new(buf, win, range, opts)

      writer:on_data("hello world")
      equals(buffer.get_content(buf), content)

      writer:on_complete()
      equals("aaa\nbbb\nhello world\nddd\neee", buffer.get_content(buf))
    end)

    it("should write to an empty buffer with new line characters", function()
      range.row_end = 0
      range.row_start = 0
      buf = tu.prepare_buffer("")
      local writer = DiffWriter:new(buf, win, range, opts)

      writer:on_data("aaa\n")
      writer:on_data("\n")
      writer:on_data("bbb\n")
      writer:on_data("\n")
      writer:on_data("ccc\n")
      equals("aaa\n\nbbb\n\nccc", buffer.get_content(buf))
    end)

    it("should write to the last line of a buffer", function()
      range.row_start = 4
      range.row_end = 4
      local writer = DiffWriter:new(buf, win, range, opts)

      writer:on_data("xxx\n")
      writer:on_data("zzz\n")
      equals("aaa\nbbb\nccc\nddd\nxxx\nzzz", buffer.get_content(buf))
    end)

    it("should write to the last line of a buffer with new line characters", function()
      range.row_start = 4
      range.row_end = 4
      local writer = DiffWriter:new(buf, win, range, opts)

      writer:on_data("xxx\n")
      writer:on_data("\n")
      writer:on_data("zzz\n")
      equals("aaa\nbbb\nccc\nddd\nxxx\n\nzzz", buffer.get_content(buf))
    end)

    it("should write to the end of the buffer", function()
      range.row_start = 6
      range.row_end = 6
      local writer = DiffWriter:new(buf, win, range, opts)

      writer:on_data("xxx\n")
      writer:on_data("\n")
      writer:on_data("yyy\n")
      equals("aaa\nbbb\nccc\nddd\neee\nxxx\n\nyyy", buffer.get_content(buf))
    end)

    it("should write to the beginning of the buffer with new line characters", function()
      range.row_start = 0
      range.row_end = 0
      local writer = DiffWriter:new(buf, win, range, opts)

      writer:on_data("xxx\n")
      writer:on_data("\n")
      writer:on_data("yyy\n")
      equals("xxx\n\nyyy\nbbb\nccc\nddd\neee", buffer.get_content(buf))
    end)

    it("should ignore columns in range (only write lines)", function()
      range.col_start = 2
      range.col_end = 2
      local writer = DiffWriter:new(buf, win, range, opts)

      writer:on_data("xxx\n")
      writer:on_data("\n")
      equals("aaa\nbbb\nxxx\n\nddd\neee", buffer.get_content(buf))
    end)

    it("should reset buffer content on reset", function()
      local writer = DiffWriter:new(buf, win, range, opts)

      writer:on_data("xxx\n")
      writer:on_data("\n")
      writer:on_data("yyy\n")
      writer:on_data("\n")
      writer:on_data("zzz\n")
      writer:on_complete()
      writer:reset()

      equals(content, buffer.get_content(buf))
    end)

    describe("highlights", function()
      it("should highlight changes at middle of buffer", function()
        local writer = DiffWriter:new(buf, win, range, { mode = "change" })

        writer:on_data("hello\n")

        assertions.has_change_highlight(buf, 3, 3, true)
      end)

      it("should highlight changes at start of buffer", function()
        range.row_start = 0
        range.row_end = 0
        local writer = DiffWriter:new(buf, win, range, { mode = "change" })

        writer:on_data("hello\n")

        assertions.has_change_highlight(buf, 1, 1, true)
      end)

      it("should highlight changes at the end of buffer", function()
        range.row_start = 4
        range.row_end = 4
        local writer = DiffWriter:new(buf, win, range, { mode = "change" })

        writer:on_data("hello\n")

        assertions.has_change_highlight(buf, 5, 5)
      end)

      it("should highlight diffs at middle of buffer", function()
        local writer = DiffWriter:new(buf, win, range, opts)

        writer:on_data("hello\n")

        assertions.has_add_highlight(buf, 3, 3)
        assertions.has_remove_highlight(buf, 3, { "ccc" })
      end)

      it("should highlight diffs at start of buffer", function()
        range.row_start = 0
        range.row_end = 0
        local writer = DiffWriter:new(buf, win, range, opts)

        writer:on_data("hello\n")

        assertions.has_add_highlight(buf, 1, 1)
        assertions.has_remove_highlight(buf, 1, { "aaa" })
      end)

      it("should highlight diffs at the end of buffer", function()
        range.row_start = 4
        range.row_end = 4
        local writer = DiffWriter:new(buf, win, range, opts)

        writer:on_data("hello\n")

        assertions.has_add_highlight(buf, 5, 5)
        assertions.has_remove_highlight(buf, 5, { "eee" })
      end)

      it("should not highlight diff when content hasn't changed", function()
        local writer = DiffWriter:new(buf, win, range, opts)

        writer:on_data("ccc\n")

        assertions.no_highlights_at_all(buf)
      end)

      it("should highlight multiple added lines", function()
        local writer = DiffWriter:new(buf, win, range, opts)

        writer:on_data("ccc\n")
        writer:on_data("xxx\n")
        writer:on_data("yyy\n")
        writer:on_data("zzz\n")

        assertions.has_add_highlight(buf, 4, 6)
      end)

      it("should highlight multiple hunks", function()
        local writer = DiffWriter:new(buf, win, range, opts)

        writer:on_data("xxx\n")
        writer:on_data("ccc\n")
        writer:on_data("zzz\n")

        assertions.has_add_highlight(buf, 3, 3)
        assertions.has_add_highlight(buf, 5, 5)
        assertions.no_remove_highlight(buf, 3) -- line "ccc" is recognised as being the existing line
      end)

      it("should reset diff highlights", function()
        local writer = DiffWriter:new(buf, win, range, opts)

        writer:on_data("hello\n")
        assertions.has_add_highlight(buf, 3, 3)
        assertions.has_remove_highlight(buf, 3, { "ccc" })

        writer:reset()

        assertions.no_highlights_at_all(buf)
      end)
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
      local writer = DiffWriter:new(buf, win, range, opts)

      writer:on_data("hello\n")
      equals("aaa\nbbb\nhello\nddd\neee", buffer.get_content(buf))
    end)

    it("should replace multiple lines with new content until end of range", function()
      local writer = DiffWriter:new(buf, win, range, opts)

      writer:on_data("one\n")
      equals("aaa\nbbb\none\nddd\neee", buffer.get_content(buf))
      writer:on_data("two\n")
      equals("aaa\nbbb\none\ntwo\neee", buffer.get_content(buf))

      -- Inserts new text now
      writer:on_data("three\n")
      equals("aaa\nbbb\none\ntwo\nthree\neee", buffer.get_content(buf))
    end)

    it(
      "should insert new lines with new content when out of range and lines are the same",
      function()
        local writer = DiffWriter:new(buf, win, range, opts)

        writer:on_data("one\n")
        writer:on_data("two\n")

        -- Insterts new text when this line is the same as the focused line
        writer:on_data("eee\n")
        equals("aaa\nbbb\none\ntwo\neee\neee", buffer.get_content(buf))
      end
    )

    it("should remove excess selected lines on complete", function()
      range.row_start = 1
      local writer = DiffWriter:new(buf, win, range, opts)

      writer:on_data("one\n")
      writer:on_complete()

      -- This is current behaviour
      -- Expected behaviour might be "aaa\none\neee" so that content is removed
      -- and the line with that content is removed
      equals("aaa\none\neee", buffer.get_content(buf))
    end)

    it("should reset buffer content on reset when rows are selected", function()
      local writer = DiffWriter:new(buf, win, range, opts)

      writer:on_data("hello world\n")
      writer:on_complete()
      writer:reset()

      equals(content, buffer.get_content(buf))
    end)

    it("should reset buffer content on reset when only columns are selected", function()
      range.row_start = 3
      range.col_end = 1
      local writer = DiffWriter:new(buf, win, range, opts)

      writer:on_data("hello world\n")
      writer:on_complete()
      writer:reset()

      equals(content, buffer.get_content(buf))
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
        local writer = DiffWriter:new(buf, win, range, opts)

        assert.are_nil(writer.focused_line_id)

        writer:on_data("hello\n")

        local ext = vim.api.nvim_buf_get_extmark_by_id(
          buf,
          writer.line_ns_id,
          writer.focused_line_id,
          { details = true }
        )
        equals(ext[1], 2)
        equals(ext[3].hl_group, "CursorLine")

        writer:on_data("hello\n")

        ext = vim.api.nvim_buf_get_extmark_by_id(
          buf,
          writer.line_ns_id,
          writer.focused_line_id,
          { details = true }
        )
        equals(ext[1], 3)
        equals(ext[3].hl_group, "CursorLine")
      end)

      it("should reset diff highlights", function()
        local writer = DiffWriter:new(buf, win, range, opts)

        writer:on_data("hello\n")
        assertions.has_remove_highlight(buf, 3, { "ccc" })

        writer:reset()

        assertions.no_highlights_at_all(buf)
      end)
    end)
  end)
end)
