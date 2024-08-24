local History = require("enlighten.history")

local equals = assert.are.same

describe("history", function()
  local content = "abc"

  it("should not scroll when there is no history", function()
    local h = History:new({})

    local got = h:scroll_back()
    equals(nil, got)

    got = h:scroll_forward()
    equals(nil, got)
  end)

  it("should scroll backwards and forwards when there is history", function()
    local h = History:new({ { "1" }, { "2" }, { "3" } })

    equals({ "1" }, h:scroll_back())

    equals({ "2" }, h:scroll_back())

    equals({ "3" }, h:scroll_back())

    equals({ "2" }, h:scroll_forward())

    equals({ "1" }, h:scroll_forward())
  end)

  it("should add current buf content to history", function()
    local h = History:new({ { "1" } })

    local items = h:update(content)

    equals({ { content }, { "1" } }, h.items)
    equals({ { content }, { "1" } }, items)
  end)

  it("should update history of the past", function()
    local h = History:new({ { "1" }, { "2" }, { "3" } })
    h.index = 2

    local items = h:update(content)

    equals({ { "1" }, { content }, { "3" } }, h.items)
    equals({ { "1" }, { content }, { "3" } }, items)
  end)

  it("should skip the first history item after current content has been saved", function()
    local h = History:new({ { "1" } })
    h:update(content)

    local got = h:scroll_back()
    equals("1", got)

    got = h:scroll_forward()
    equals(content, got)
  end)
end)
