local History = require("enlighten.history")
local buffer = require("enlighten.buffer")
local tu = require("tests.testutils")

local equals = assert.are.same

describe("history", function()
  local content = "abc"
  local buf

  before_each(function()
    buf = tu.prepare_buffer(content)
  end)

  it("should not scroll when there is no history", function()
    local h = History:new(buf, {})

    h:scroll_back()
    equals(content, buffer.get_content(buf))

    h:scroll_forward()
    equals(content, buffer.get_content(buf))
  end)

  it("should scroll backwards and forwards when there is history", function()
    local h = History:new(buf, { { "1" }, { "2" }, { "3" } })

    h:scroll_back()
    equals("1", buffer.get_content(buf))

    h:scroll_back()
    equals("2", buffer.get_content(buf))

    h:scroll_back()
    equals("3", buffer.get_content(buf))

    h:scroll_forward()
    equals("2", buffer.get_content(buf))

    h:scroll_forward()
    equals("1", buffer.get_content(buf))

    h:scroll_forward()
    equals(content, buffer.get_content(buf))
  end)

  it("should add current buf content to history", function()
    local h = History:new(buf, { { "1" } })

    local items = h:update()

    equals({ { content }, { "1" } }, h.items)
    equals({ { content }, { "1" } }, items)
  end)
end)
