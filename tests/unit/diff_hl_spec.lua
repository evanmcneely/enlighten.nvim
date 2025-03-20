local diff_hl = require("enlighten.diff.highlights")
local mock = require("luassert.mock")
local tu = require("tests.testutils")

describe("diff_hl", function()
  describe("highlight_added_lines", function()
    it("should highlight added lines", function()
      local api = mock(vim.api, true)
      local buffer = 5
      local ns = 10
      local row = 0
      local hunk = { add = { "line1", "line2" }, remove = {} }

      api.nvim_buf_set_extmark.returns(1)
      diff_hl.highlight_added_lines(buffer, ns, row, hunk)

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
      local api = mock(vim.api, true)
      local ns = 10
      local row = 0
      local hunk = { add = {}, remove = { "line1", "line2" } }

      api.nvim_buf_set_extmark.returns(1)
      diff_hl.highlight_removed_lines(buffer, ns, row, hunk)

      assert.stub(api.nvim_buf_set_extmark).was_called_with(buffer, ns, row, -1, {
        virt_lines = {
          { { "line1", "EnlightenDiffDelete" } },
          { { "line2", "EnlightenDiffDelete" } },
        },
        virt_lines_above = true,
      })

      mock.revert(api)
    end)

    it("should set buffer variable for removed lines", function()
      local api = mock(vim.api, true)
      local buffer = 5
      local ns = 10
      local row = 0
      local hunk = { add = { "line1", "line2" }, remove = { "old1", "old2" } }

      api.nvim_buf_set_extmark.returns(42)
      diff_hl.highlight_removed_lines(buffer, ns, row, hunk)

      assert
        .stub(api.nvim_buf_set_var)
        .was_called_with(buffer, "enlighten_removed_lines_42", hunk.remove)

      mock.revert(api)
    end)
  end)

  describe("highlight_changed_lines", function()
    it("should highlight changed lines", function()
      local api = mock(vim.api, true)
      local buffer = 5
      local ns = 10
      local row = 0
      local hunk = { add = { "line1", "line2" }, remove = { "old1", "old2" } }

      api.nvim_buf_set_extmark.returns(1)
      diff_hl.highlight_changed_lines(buffer, ns, row, hunk)

      assert.stub(api.nvim_buf_set_extmark).was_called_with(buffer, ns, row, 0, {
        end_row = row + #hunk.add,
        hl_group = "EnlightenDiffChange",
        hl_eol = true,
        priority = 1000,
      })

      mock.revert(api)
    end)

    it("should set buffer variable for removed lines", function()
      local api = mock(vim.api, true)
      local buffer = 5
      local ns = 10
      local row = 0
      local hunk = { add = { "line1", "line2" }, remove = { "old1", "old2" } }

      api.nvim_buf_set_extmark.returns(42)
      diff_hl.highlight_changed_lines(buffer, ns, row, hunk)

      assert
        .stub(api.nvim_buf_set_var)
        .was_called_with(buffer, "enlighten_removed_lines_42", hunk.remove)

      mock.revert(api)
    end)
  end)
end)
