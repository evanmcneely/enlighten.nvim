local DiffWriter = require("enlighten.writer.diff")
local tu = require("tests.testutils")
local buffer = require("enlighten.buffer")

local equals = assert.are.same

local function assert_highlight(extmarks, start_row, end_row, hl_group)
  for _, extmark in ipairs(extmarks) do
    local _, s_row, _, details = unpack(extmark)
    if s_row == start_row and details.end_row == end_row and details.hl_group == hl_group then
      return true
    end
  end
  error(
    "Highlight "
      .. hl_group
      .. " from row "
      .. start_row
      .. " to "
      .. end_row
      .. "  does not exist:\n"
      .. vim.inspect(extmarks)
  )
end

local function assert_virtual_line(extmarks, row, start_text, hl_group)
  for _, extmark in ipairs(extmarks) do
    local _, s_row, _, details = unpack(extmark)
    if s_row == row and details.virt_lines then
      for _, virt_line in ipairs(details.virt_lines) do
        local text, group = unpack(virt_line[1])
        if text:find("^" .. start_text) and group == hl_group then
          return true
        end
      end
    end
  end
  error(
    "Virtual line on row "
      .. row
      .. " starting with "
      .. start_text
      .. " and highlight "
      .. hl_group
      .. " does not exist:\n"
      .. vim.inspect(extmarks)
  )
end

local function assert_no_virt_lines(extmarks)
  for _, extmark in ipairs(extmarks) do
    local _, _, _, details = unpack(extmark)
    if details.virt_lines then
      error("Extmark with virtual lines exists")
    end
  end
  return true
end

describe("DiffWriter", function()
  local content = "aaa\nbbb\nccc\nddd\neee"
  local buf
  ---@type Range
  local range

  local function get_extmarks_for_buffer(writer)
    return vim.api.nvim_buf_get_extmarks(buf, writer.diff_ns_id, 0, -1, { details = true })
  end

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

  it("should be active on start and inactive on complete", function()
    local writer = DiffWriter:new(buf, range)
    equals(false, writer.active)

    writer:start()
    equals(true, writer.active)

    writer:on_complete()
    equals(false, writer.active)
  end)

  -- current expected behaviour is for the line the cursor is on to always be selected
  describe("normal", function()
    it("should not write to buffer until there is a complete line", function()
      local writer = DiffWriter:new(buf, range)

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
      local writer = DiffWriter:new(buf, range)

      writer:on_data("\n\n")
      equals("aaa\nbbb\n\n\nddd\neee", buffer.get_content(buf))
    end)

    it("should handle double new line characters separated by text as input", function()
      local writer = DiffWriter:new(buf, range)

      writer:on_data("\nhere\n")
      equals("aaa\nbbb\n\nhere\nddd\neee", buffer.get_content(buf))
    end)

    it("should not write characters after a new line character", function()
      local writer = DiffWriter:new(buf, range)

      writer:on_data("\nhere")
      equals("aaa\nbbb\n\nddd\neee", buffer.get_content(buf))
    end)

    it("should write all unwritten text on complete", function()
      local writer = DiffWriter:new(buf, range)

      writer:on_data("hello world")
      equals(buffer.get_content(buf), content)

      writer:on_complete()
      tu.scheduled_equals("aaa\nbbb\nhello world\nddd\neee", buffer.get_content(buf))
    end)

    it("should write to an empty buffer with new line characters", function()
      range.row_end = 0
      range.row_start = 0
      buf = tu.prepare_buffer("")
      local writer = DiffWriter:new(buf, range)

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
      local writer = DiffWriter:new(buf, range)

      writer:on_data("xxx\n")
      writer:on_data("zzz\n")
      equals("aaa\nbbb\nccc\nddd\nxxx\nzzz", buffer.get_content(buf))
    end)

    it("should write to the last line of a buffer with new line characters", function()
      range.row_start = 4
      range.row_end = 4
      local writer = DiffWriter:new(buf, range)

      writer:on_data("xxx\n")
      writer:on_data("\n")
      writer:on_data("zzz\n")
      equals("aaa\nbbb\nccc\nddd\nxxx\n\nzzz", buffer.get_content(buf))
    end)

    it("should write to the end of the buffer", function()
      range.row_start = 6
      range.row_end = 6
      local writer = DiffWriter:new(buf, range)

      writer:on_data("xxx\n")
      writer:on_data("\n")
      writer:on_data("yyy\n")
      equals("aaa\nbbb\nccc\nddd\neee\nxxx\n\nyyy", buffer.get_content(buf))
    end)

    it("should write to the beginning of the buffer with new line characters", function()
      range.row_start = 0
      range.row_end = 0
      local writer = DiffWriter:new(buf, range)

      writer:on_data("xxx\n")
      writer:on_data("\n")
      writer:on_data("yyy\n")
      equals("xxx\n\nyyy\nbbb\nccc\nddd\neee", buffer.get_content(buf))
    end)

    it("should ignore columns in range (only write lines)", function()
      range.col_start = 2
      range.col_end = 2
      local writer = DiffWriter:new(buf, range)

      writer:on_data("xxx\n")
      writer:on_data("\n")
      equals("aaa\nbbb\nxxx\n\nddd\neee", buffer.get_content(buf))
    end)

    it("should reset buffer content on reset", function()
      local writer = DiffWriter:new(buf, range)

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
      it("should highlight diffs at middle of buffer", function()
        local writer = DiffWriter:new(buf, range)

        writer:on_data("hello\n")

        local ext = get_extmarks_for_buffer(writer)
        assert_highlight(ext, 2, 3, "EnlightenDiffChange")
      end)

      it("should highlight diffs at start of buffer", function()
        range.row_start = 0
        range.row_end = 0
        local writer = DiffWriter:new(buf, range)

        writer:on_data("hello\n")

        local ext = get_extmarks_for_buffer(writer)
        assert_highlight(ext, 0, 1, "EnlightenDiffChange")
      end)

      it("should highlight diffs at the end of buffer", function()
        range.row_start = 4
        range.row_end = 4
        local writer = DiffWriter:new(buf, range)

        writer:on_data("hello\n")

        local ext = get_extmarks_for_buffer(writer)
        assert_highlight(ext, 4, 5, "EnlightenDiffChange")
      end)

      it("should not highlight diff when content hasn't changed", function()
        local writer = DiffWriter:new(buf, range)

        writer:on_data("ccc\n")

        local ext = get_extmarks_for_buffer(writer)
        equals({}, ext)
      end)

      it("should highlight multiple added lines", function()
        local writer = DiffWriter:new(buf, range)

        writer:on_data("ccc\n")
        writer:on_data("xxx\n")
        writer:on_data("yyy\n")
        writer:on_data("zzz\n")

        local ext = get_extmarks_for_buffer(writer)
        assert_highlight(ext, 3, 6, "EnlightenDiffAdd")
      end)

      it("should highlight multiple hunks", function()
        local writer = DiffWriter:new(buf, range)

        writer:on_data("xxx\n")
        writer:on_data("ccc\n")
        writer:on_data("zzz\n")

        local ext = get_extmarks_for_buffer(writer)
        assert_highlight(ext, 2, 3, "EnlightenDiffAdd")
        assert_highlight(ext, 4, 5, "EnlightenDiffAdd")
        assert_no_virt_lines(ext) -- line "ccc" is recognised as being the existing line
      end)

      it("should reset diff highlights", function()
        local writer = DiffWriter:new(buf, range)

        writer:on_data("hello\n")

        local ext = get_extmarks_for_buffer(writer)
        assert.are.not_equal({}, ext)

        writer:reset()

        ext = get_extmarks_for_buffer(writer)
        equals({}, ext)
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
        local writer = DiffWriter:new(buf, range)

        writer:on_data("hello\n")

        local ext = get_extmarks_for_buffer(writer)
        assert.are.not_equal({}, ext)

        writer:reset()

        ext = get_extmarks_for_buffer(writer)
        equals({}, ext)
      end)
    end)
  end)
end)
