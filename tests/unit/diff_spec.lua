local diff = require("enlighten.diff")

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
end)
