local equals = assert.are.same
local tu = require("tests.testutils")
local assertions = require("tests.assertions")

describe("enlighten commands and keymaps", function()
  local target_buf

  require("enlighten").setup()

  before_each(function()
    ---@type Enlighten
    target_buf = vim.api.nvim_get_current_buf()
  end)

  describe("chat", function()
    it("should open the chat", function()
      -- open and initialize the chat
      vim.cmd("lua require('enlighten').chat()")

      local buf = vim.api.nvim_get_current_buf()
      assert.are.same("enlighten", vim.api.nvim_get_option_value("filetype", { buf = buf }))
      assert.are.same("enlighten-chat", vim.api.nvim_buf_get_name(buf):match("enlighten%-chat"))

      vim.api.nvim_buf_delete(buf, {})
    end)
  end)

  describe("edit", function()
    it("should open the prompt when edit is invoked", function()
      vim.cmd("lua require('enlighten').edit()")

      local buf = vim.api.nvim_get_current_buf()
      assert.are.same("enlighten", vim.api.nvim_get_option_value("filetype", { buf = buf }))
      assert.are.same("enlighten-edit", vim.api.nvim_buf_get_name(buf):match("enlighten%-edit"))
    end)

    it("should focus prompt when edit is invoked and prompt already exists for buffer", function()
      vim.cmd("lua require('enlighten').edit()")
      local prompt_buf = vim.api.nvim_get_current_buf()

      vim.api.nvim_set_current_buf(target_buf)

      vim.cmd("lua require('enlighten').edit()")
      assert.are.same(prompt_buf, vim.api.nvim_get_current_buf())
    end)
  end)

  describe("hunks", function()
    local test_lines
    local buffer
    local ns
    local remove_mark
    local remove_only_mark
    local change_mark

    before_each(function()
      test_lines = {
        "line1",
        "line2",
        "line3",
        "line4",
        "line5",
        "line6",
        "line7",
        "line8",
        "line9",
        "line10",
        "line11",
        "line12",
      }

      buffer = tu.prepare_buffer(table.concat(test_lines, "\n"))
      ns = vim.api.nvim_create_namespace("EnlightenDiffHighlights")

      -- Create a hunk with removals (line 2)
      remove_only_mark = vim.api.nvim_buf_set_extmark(buffer, ns, 2, -1, {
        virt_lines = {
          { { "deleted line", "EnlightenDiffDelete" } },
        },
        virt_lines_above = true,
      })
      vim.api.nvim_buf_set_var(
        buffer,
        "enlighten_removed_lines_" .. remove_only_mark,
        { "deleted line" }
      )

      -- Create a hunk with additions (line 4)
      vim.api.nvim_buf_set_extmark(buffer, ns, 4, 0, {
        end_row = 5,
        hl_group = "EnlightenDiffAdd",
        hl_eol = true,
        priority = 1000,
      })

      -- Create a hunk with both additions and removals (line 6)
      vim.api.nvim_buf_set_extmark(buffer, ns, 6, 0, {
        end_row = 8,
        hl_group = "EnlightenDiffAdd",
        hl_eol = true,
        priority = 1000,
      })
      remove_mark = vim.api.nvim_buf_set_extmark(buffer, ns, 6, -1, {
        virt_lines = {
          { { "old line", "EnlightenDiffDelete" } },
        },
        virt_lines_above = true,
      })
      vim.api.nvim_buf_set_var(buffer, "enlighten_removed_lines_" .. remove_mark, { "old line" })

      -- Create a hunk with changed lines and removed lines (line 9)
      change_mark = vim.api.nvim_buf_set_extmark(buffer, ns, 9, 0, {
        end_row = 10,
        hl_group = "EnlightenDiffChange",
        hl_eol = true,
        priority = 1000,
      })
      vim.api.nvim_buf_set_var(buffer, "enlighten_removed_lines_" .. change_mark, { "old line" })

      -- Create a hunk with changed lines (line 11)
      vim.api.nvim_buf_set_extmark(buffer, ns, 11, 0, {
        end_row = 12,
        hl_group = "EnlightenDiffChange",
        hl_eol = true,
        priority = 1000,
      })
    end)

    describe("keep", function()
      it("should do nothing if the cursor is not on a diff highlight", function()
        vim.api.nvim_win_set_cursor(0, { 2, 0 })

        vim.cmd("lua require('enlighten').keep()")

        assertions.has_remove_highlight(buffer, 3, { "deleted line" })
        assertions.has_add_highlight(buffer, 5, 5)
        assertions.has_add_highlight(buffer, 7, 8)
        assertions.has_remove_highlight(buffer, 7, { "old line" })
        assertions.has_change_highlight(buffer, 10, 10, true)
        assertions.has_change_highlight(buffer, 12, 12)

        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        equals(test_lines, lines)
      end)

      it("should clear deleted diff highlights from lines cursor is on", function()
        vim.api.nvim_win_set_cursor(0, { 3, 0 })

        vim.cmd("lua require('enlighten').keep()")

        assertions.no_remove_highlight(buffer, 3)
        assertions.no_removed_lines_var(buffer, remove_only_mark)

        assertions.has_add_highlight(buffer, 5, 5)
        assertions.has_add_highlight(buffer, 7, 8)
        assertions.has_remove_highlight(buffer, 7, { "old line" })
        assertions.has_change_highlight(buffer, 10, 10, true)
        assertions.has_change_highlight(buffer, 12, 12)

        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        equals(test_lines, lines)
      end)

      it("should clear added diff highlights from lines cursor is on", function()
        vim.api.nvim_win_set_cursor(0, { 5, 0 })

        vim.cmd("lua require('enlighten').keep()")

        assertions.no_add_highlight(buffer, 5, 5)

        assertions.has_remove_highlight(buffer, 3, { "deleted line" })
        assertions.has_add_highlight(buffer, 7, 8)
        assertions.has_remove_highlight(buffer, 7, { "old line" })
        assertions.has_change_highlight(buffer, 10, 10, true)
        assertions.has_change_highlight(buffer, 12, 12)

        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        equals(test_lines, lines)
      end)

      it("should clear added and deleted diff highlights from lines cursor is on", function()
        vim.api.nvim_win_set_cursor(0, { 8, 0 })

        vim.cmd("lua require('enlighten').keep()")

        assertions.no_add_highlight(buffer, 7, 8)
        assertions.no_remove_highlight(buffer, 7)
        assertions.no_removed_lines_var(buffer, remove_mark)

        assertions.has_remove_highlight(buffer, 3, { "deleted line" })
        assertions.has_add_highlight(buffer, 5, 5)
        assertions.has_change_highlight(buffer, 10, 10, true)
        assertions.has_change_highlight(buffer, 12, 12)

        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        equals(test_lines, lines)
      end)

      it(
        "should clear changed diff highlights with removed lines from lines cursor is on",
        function()
          vim.api.nvim_win_set_cursor(0, { 10, 0 })

          vim.cmd("lua require('enlighten').keep()")

          assertions.no_change_highlight(buffer, 10, 10)
          assertions.no_removed_lines_var(buffer, change_mark)

          assertions.has_remove_highlight(buffer, 3, { "deleted line" })
          assertions.has_add_highlight(buffer, 5, 5)
          assertions.has_add_highlight(buffer, 7, 8)
          assertions.has_remove_highlight(buffer, 7, { "old line" })
          assertions.has_change_highlight(buffer, 12, 12)

          local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
          equals(test_lines, lines)
        end
      )

      it("should clear changed diff highlights from lines cursor is on", function()
        vim.api.nvim_win_set_cursor(0, { 12, 0 })

        vim.cmd("lua require('enlighten').keep()")

        assertions.no_change_highlight(buffer, 12, 12)

        assertions.has_remove_highlight(buffer, 3, { "deleted line" })
        assertions.has_add_highlight(buffer, 5, 5)
        assertions.has_add_highlight(buffer, 7, 8)
        assertions.has_remove_highlight(buffer, 7, { "old line" })
        assertions.has_change_highlight(buffer, 10, 10, true)

        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        equals(test_lines, lines)
      end)

      it("should clear all diff highlights when the whole buffer is selected", function()
        vim.cmd("normal! ggVG")

        vim.cmd("lua require('enlighten').keep()")

        assertions.no_highlights_at_all(buffer)
        assertions.no_removed_lines_var(buffer, change_mark)
        assertions.no_removed_lines_var(buffer, remove_mark)
        assertions.no_removed_lines_var(buffer, remove_only_mark)

        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        equals(test_lines, lines)
      end)

      it("should clear diff highlights only in the selected range", function()
        vim.api.nvim_win_set_cursor(0, { 5, 0 }) -- Start at line 5
        vim.cmd("normal! V2j") -- Select 3 lines (5, 6, 7)

        vim.cmd("lua require('enlighten').keep()")

        assertions.no_add_highlight(buffer, 5, 5)
        assertions.no_add_highlight(buffer, 7, 8)
        assertions.no_remove_highlight(buffer, 7)
        assertions.no_removed_lines_var(buffer, remove_mark)

        assertions.has_remove_highlight(buffer, 3, { "deleted line" })
        assertions.has_change_highlight(buffer, 10, 10, true)
        assertions.has_change_highlight(buffer, 12, 12)

        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        equals(test_lines, lines)
      end)
    end)

    describe("discard", function()
      it("should do nothing if the cursor is not on a diff highlight", function()
        vim.api.nvim_win_set_cursor(0, { 2, 0 })

        vim.cmd("lua require('enlighten').discard()")

        assertions.has_remove_highlight(buffer, 3, { "deleted line" })
        assertions.has_add_highlight(buffer, 5, 5)
        assertions.has_add_highlight(buffer, 7, 8)
        assertions.has_remove_highlight(buffer, 7, { "old line" })
        assertions.has_change_highlight(buffer, 10, 10, true)
        assertions.has_change_highlight(buffer, 12, 12)

        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        equals(test_lines, lines)
      end)

      it("should clear deleted diff highlights from lines cursor is on", function()
        vim.api.nvim_win_set_cursor(0, { 3, 0 })

        vim.cmd("lua require('enlighten').discard()")

        assertions.no_remove_highlight(buffer, 3)
        assertions.no_removed_lines_var(buffer, remove_only_mark)

        assertions.has_add_highlight(buffer, 6, 6)
        assertions.has_add_highlight(buffer, 8, 9)
        assertions.has_remove_highlight(buffer, 8, { "old line" })
        assertions.has_change_highlight(buffer, 11, 11, true)
        assertions.has_change_highlight(buffer, 13, 13)

        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        table.insert(test_lines, 3, "deleted line")
        equals(test_lines, lines)
      end)

      it("should clear added diff highlights from lines cursor is on", function()
        vim.api.nvim_win_set_cursor(0, { 5, 0 })

        vim.cmd("lua require('enlighten').discard()")

        assertions.no_add_highlight(buffer, 5, 5)

        assertions.has_remove_highlight(buffer, 3, { "deleted line" })
        assertions.has_add_highlight(buffer, 6, 7)
        assertions.has_remove_highlight(buffer, 6, { "old line" })
        assertions.has_change_highlight(buffer, 9, 9, true)
        assertions.has_change_highlight(buffer, 11, 11)

        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        table.remove(test_lines, 5)
        equals(test_lines, lines)
      end)

      it("should clear added and deleted diff highlights from lines cursor is on", function()
        vim.api.nvim_win_set_cursor(0, { 8, 0 })

        vim.cmd("lua require('enlighten').discard()")

        assertions.no_add_highlight(buffer, 7, 8)
        assertions.no_remove_highlight(buffer, 7)
        assertions.no_removed_lines_var(buffer, remove_mark)

        assertions.has_remove_highlight(buffer, 3, { "deleted line" })
        assertions.has_add_highlight(buffer, 5, 5)
        assertions.has_change_highlight(buffer, 9, 9, true)
        assertions.has_change_highlight(buffer, 11, 11)

        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        table.remove(test_lines, 7)
        table.remove(test_lines, 7)
        table.insert(test_lines, 7, "old line")
        equals(test_lines, lines)
      end)

      it(
        "should clear changed diff highlights with removed lines from lines cursor is on",
        function()
          vim.api.nvim_win_set_cursor(0, { 10, 0 })

          vim.cmd("lua require('enlighten').discard()")

          assertions.no_change_highlight(buffer, 10, 10)
          assertions.no_removed_lines_var(buffer, change_mark)

          assertions.has_remove_highlight(buffer, 3, { "deleted line" })
          assertions.has_add_highlight(buffer, 5, 5)
          assertions.has_add_highlight(buffer, 7, 8)
          assertions.has_remove_highlight(buffer, 7, { "old line" })
          assertions.has_change_highlight(buffer, 12, 12)

          local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
          table.remove(test_lines, 10)
          table.insert(test_lines, 10, "old line")
          equals(test_lines, lines)
        end
      )

      it("should clear changed diff highlights from lines cursor is on", function()
        vim.api.nvim_win_set_cursor(0, { 12, 0 })

        vim.cmd("lua require('enlighten').discard()")

        assertions.no_change_highlight(buffer, 12, 12)

        assertions.has_remove_highlight(buffer, 3, { "deleted line" })
        assertions.has_add_highlight(buffer, 5, 5)
        assertions.has_add_highlight(buffer, 7, 8)
        assertions.has_remove_highlight(buffer, 7, { "old line" })
        assertions.has_change_highlight(buffer, 10, 10, true)

        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        table.remove(test_lines, 12)
        equals(test_lines, lines)
      end)

      it("should clear all diff highlights when the whole buffer is selected", function()
        vim.cmd("normal! ggVG")

        vim.cmd("lua require('enlighten').discard()")

        assertions.no_highlights_at_all(buffer)
        assertions.no_removed_lines_var(buffer, remove_mark)
        assertions.no_removed_lines_var(buffer, remove_only_mark)
        assertions.no_removed_lines_var(buffer, change_mark)

        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        table.remove(test_lines, 12)
        table.remove(test_lines, 10)
        table.insert(test_lines, 10, "old line")
        table.remove(test_lines, 7)
        table.remove(test_lines, 7)
        table.insert(test_lines, 7, "old line")
        table.remove(test_lines, 5)
        table.insert(test_lines, 3, "deleted line")
        equals(test_lines, lines)
      end)

      it("should clear diff highlights only in the selected range", function()
        vim.api.nvim_win_set_cursor(0, { 5, 0 }) -- Start at line 5
        vim.cmd("normal! V2j") -- Select 3 lines (5, 6, 7)

        vim.cmd("lua require('enlighten').discard()")

        assertions.no_add_highlight(buffer, 5, 5)
        assertions.no_add_highlight(buffer, 7, 8)
        assertions.no_remove_highlight(buffer, 7)
        assertions.no_removed_lines_var(buffer, remove_mark)

        assertions.has_remove_highlight(buffer, 3, { "deleted line" })
        assertions.has_change_highlight(buffer, 8, 8, true)
        assertions.has_change_highlight(buffer, 10, 10)

        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        table.remove(test_lines, 7)
        table.remove(test_lines, 7)
        table.insert(test_lines, 7, "old line")
        table.remove(test_lines, 5)
        equals(test_lines, lines)
      end)
    end)

    describe("keep_all", function()
      it("should clear all diff highlights", function()
        vim.cmd("lua require('enlighten').keep_all()")

        assertions.no_highlights_at_all(buffer)
        assertions.no_removed_lines_var(buffer, remove_mark)
        assertions.no_removed_lines_var(buffer, remove_only_mark)
        assertions.no_removed_lines_var(buffer, change_mark)

        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        equals(test_lines, lines)
      end)
    end)

    describe("discard_all", function()
      it("should clear all diff highlights", function()
        vim.cmd("lua require('enlighten').discard_all()")

        assertions.no_highlights_at_all(buffer)
        assertions.no_removed_lines_var(buffer, remove_mark)
        assertions.no_removed_lines_var(buffer, remove_only_mark)
        assertions.no_removed_lines_var(buffer, change_mark)

        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        table.remove(test_lines, 12)
        table.remove(test_lines, 10)
        table.insert(test_lines, 10, "old line")
        table.remove(test_lines, 7)
        table.remove(test_lines, 7)
        table.insert(test_lines, 7, "old line")
        table.remove(test_lines, 5)
        table.insert(test_lines, 3, "deleted line")
        equals(test_lines, lines)
      end)
    end)
  end)
end)
