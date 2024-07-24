---@diagnostic disable: undefined-field

local buffer = require("enlighten.buffer")
local tu = require("tests.testutils")

local equals = assert.are.same

describe("buffer", function()
  local content = "a\nb\nc\nd\ne"
  local buf

  before_each(function()
    buf = tu.prepare_buffer(content)
  end)

  describe("get_content", function()
    it("should return text content between start and finish indices", function()
      equals("c\nd", buffer.get_content(buf, 2, 4))
    end)

    it("should return text content to end of buffer when finish is omitted", function()
      equals("c\nd\ne", buffer.get_content(buf, 2))
    end)

    it("should return all text content when both start and finish indices are omitted", function()
      equals("a\nb\nc\nd\ne", buffer.get_content(buf))
    end)
  end)

  describe("get_lines", function()
    it("should return text content between start and finish indices", function()
      equals({ "c", "d" }, buffer.get_lines(buf, 2, 4))
    end)

    it("should return text content to end of buffer when finish is omitted", function()
      equals({ "c", "d", "e" }, buffer.get_lines(buf, 2))
    end)

    it("should return all text content when both start and finish indices are omitted", function()
      equals({ "a", "b", "c", "d", "e" }, buffer.get_lines(buf))
    end)
  end)
end)
