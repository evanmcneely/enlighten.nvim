local utils = require("enlighten.utils")

local equals = assert.are.same

describe("utils", function()
  describe("starts_with", function()
    it("should return true when string starts with matcher", function()
      equals(true, utils.starts_with("g testing", "g"))
    end)

    it("should return false when string does not start with matcher", function()
      equals(false, utils.starts_with("g testing", "h"))
    end)
  end)

  -- TODO write tests for slice
  -- TODO write tests for trim_empty_lines
end)
