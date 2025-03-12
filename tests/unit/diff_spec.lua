local diff = require("enlighten.diff")
local mock = require("luassert.mock")
local tu = require("tests.testutils")

local equals = assert.are.same

describe("diff", function()
  describe("diff", function()
    local left
    local right

    before_each(function()
      left = { "aa", "bb", "cc", "dd", "ee" }
      right = { "aa", "bb", "cc", "dd", "ee" }
    end)

    it("should diff lines with no changes", function()
      local got = diff.diff(left, right)
      local want = {
        { type = diff.constants.unchanged, value = "aa" },
        { type = diff.constants.unchanged, value = "bb" },
        { type = diff.constants.unchanged, value = "cc" },
        { type = diff.constants.unchanged, value = "dd" },
        { type = diff.constants.unchanged, value = "ee" },
      }
      equals(want, got)
    end)

    it("should diff lines with one change", function()
      right = { "aa", "zz", "cc", "dd", "ee" }
      local got = diff.diff(left, right)
      local want = {
        { type = diff.constants.unchanged, value = "aa" },
        { type = diff.constants.removal, value = "bb" },
        { type = diff.constants.addition, value = "zz" },
        { type = diff.constants.unchanged, value = "cc" },
        { type = diff.constants.unchanged, value = "dd" },
        { type = diff.constants.unchanged, value = "ee" },
      }
      equals(want, got)
    end)

    it("should diff lines with multiple consecutive changes", function()
      right = { "aa", "zz", "yy", "dd", "ee" }
      local got = diff.diff(left, right)
      local want = {
        { type = diff.constants.unchanged, value = "aa" },
        { type = diff.constants.removal, value = "bb" },
        { type = diff.constants.removal, value = "cc" },
        { type = diff.constants.addition, value = "zz" },
        { type = diff.constants.addition, value = "yy" },
        { type = diff.constants.unchanged, value = "dd" },
        { type = diff.constants.unchanged, value = "ee" },
      }
      equals(want, got)
    end)

    it("should diff lines with multiple non consecutive changes", function()
      right = { "aa", "zz", "cc", "yy", "ee" }
      local got = diff.diff(left, right)
      local want = {
        { type = diff.constants.unchanged, value = "aa" },
        { type = diff.constants.removal, value = "bb" },
        { type = diff.constants.addition, value = "zz" },
        { type = diff.constants.unchanged, value = "cc" },
        { type = diff.constants.removal, value = "dd" },
        { type = diff.constants.addition, value = "yy" },
        { type = diff.constants.unchanged, value = "ee" },
      }
      equals(want, got)
    end)

    it("should diff lines with new lines added", function()
      right = { "aa", "bb", "cc", "xx", "yy", "dd", "ee" }
      local got = diff.diff(left, right)
      local want = {
        { type = diff.constants.unchanged, value = "aa" },
        { type = diff.constants.unchanged, value = "bb" },
        { type = diff.constants.unchanged, value = "cc" },
        { type = diff.constants.addition, value = "xx" },
        { type = diff.constants.addition, value = "yy" },
        { type = diff.constants.unchanged, value = "dd" },
        { type = diff.constants.unchanged, value = "ee" },
      }
      equals(want, got)
    end)

    it("should diff lines with new lines removed", function()
      right = { "aa", "dd", "ee" }
      local got = diff.diff(left, right)
      local want = {
        { type = diff.constants.unchanged, value = "aa" },
        { type = diff.constants.removal, value = "bb" },
        { type = diff.constants.removal, value = "cc" },
        { type = diff.constants.unchanged, value = "dd" },
        { type = diff.constants.unchanged, value = "ee" },
      }
      equals(want, got)
    end)
  end)

  describe("extract_hunks", function()
    it("should group hunks with additions only", function()
      local row = 3
      local changes = {
        { type = diff.constants.unchanged, value = "aa" },
        { type = diff.constants.unchanged, value = "bb" },
        { type = diff.constants.unchanged, value = "cc" },
        { type = diff.constants.addition, value = "xx" },
        { type = diff.constants.addition, value = "yy" },
        { type = diff.constants.unchanged, value = "dd" },
        { type = diff.constants.unchanged, value = "ee" },
      }

      local want = {
        [6] = {
          add = { "xx", "yy" },
          remove = {},
        },
      }
      local got = diff.extract_hunks(row, changes)

      equals(want, got)
    end)

    it("should group hunks with removals only", function()
      local row = 5
      local changes = {
        { type = diff.constants.unchanged, value = "aa" },
        { type = diff.constants.removal, value = "bb" },
        { type = diff.constants.removal, value = "cc" },
        { type = diff.constants.unchanged, value = "dd" },
        { type = diff.constants.unchanged, value = "ee" },
      }

      local want = {
        [6] = {
          add = {},
          remove = { "bb", "cc" },
        },
      }
      local got = diff.extract_hunks(row, changes)

      equals(want, got)
    end)

    it("should group hunks with additions and removals", function()
      local row = 15
      local changes = {
        { type = diff.constants.unchanged, value = "aa" },
        { type = diff.constants.removal, value = "bb" },
        { type = diff.constants.addition, value = "zz" },
        { type = diff.constants.unchanged, value = "cc" },
        { type = diff.constants.unchanged, value = "dd" },
        { type = diff.constants.unchanged, value = "ee" },
      }

      local want = {
        [16] = {
          add = { "zz" },
          remove = { "bb" },
        },
      }
      local got = diff.extract_hunks(row, changes)

      equals(want, got)
    end)

    it("should group hunks when many are present", function()
      local row = 700
      local changes = {
        { type = diff.constants.unchanged, value = "aa" },
        { type = diff.constants.removal, value = "bb" },
        { type = diff.constants.addition, value = "zz" },
        { type = diff.constants.unchanged, value = "cc" },
        { type = diff.constants.unchanged, value = "dd" },
        { type = diff.constants.removal, value = "ll" },
        { type = diff.constants.addition, value = "yy" },
        { type = diff.constants.unchanged, value = "ee" },
      }

      local want = {
        [701] = {
          add = { "zz" },
          remove = { "bb" },
        },
        [704] = {
          add = { "yy" },
          remove = { "ll" },
        },
      }
      local got = diff.extract_hunks(row, changes)

      equals(want, got)
    end)
  end)

  describe("highlight_added_lines", function()
    it("should highlight added lines", function()
      -- mock the vim.api
      local api = mock(vim.api, true)
      local buffer = 5
      local ns = 10
      local row = 0
      local hunk = { add = { "line1", "line2" }, remove = {} }

      diff.highlight_added_lines(buffer, ns, row, hunk)

      assert.stub(api.nvim_buf_set_extmark).was_called_with(buffer, ns, row, 0, {
        end_row = row + #hunk.add,
        hl_group = "EnlightenDiffAdd",
        hl_eol = true,
        priority = 1000,
      })

      mock.revert(api)
    end)
  end)

  describe("highlight_removed_lines", function()
    it("should highlight removed lines", function()
      local buffer = tu.prepare_buffer("")
      -- mock the vim.api
      local api = mock(vim.api, true)
      local ns = 10
      local row = 0
      local hunk = { add = {}, remove = { "line1", "line2" } }

      diff.highlight_removed_lines(buffer, ns, row, hunk)

      assert.stub(api.nvim_buf_set_extmark).was_called_with(buffer, ns, row, -1, {
        virt_lines = {
          { { "line1", "EnlightenDiffDelete" } },
          { { "line2", "EnlightenDiffDelete" } },
        },
        virt_lines_above = true,
      })

      mock.revert(api)
    end)
  end)

  describe("highlight_changed_lines", function()
    it("should highlight changed lines", function()
      -- mock the vim.api
      local api = mock(vim.api, true)
      local buffer = 5
      local ns = 10
      local row = 0
      local hunk = { add = { "line1", "line2" }, remove = { "old1", "old2" } }

      diff.highlight_changed_lines(buffer, ns, row, hunk)

      assert.stub(api.nvim_buf_set_extmark).was_called_with(buffer, ns, row, 0, {
        end_row = row + #hunk.add,
        hl_group = "EnlightenDiffChange",
        hl_eol = true,
        priority = 1000,
      })

      mock.revert(api)
    end)
  end)
end)
