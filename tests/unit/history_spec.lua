local History = require("enlighten.history")
local mock = require("luassert.mock")

local equals = assert.are.same

describe("history", function()
  local content = "abc"

  it("should not scroll when there is no history", function()
    local h = History:new("testing")

    local got = h:scroll_back()
    equals(nil, got)

    got = h:scroll_forward()
    equals(nil, got)
  end)

  it("should scroll backwards and forwards when there is history", function()
    local h = History:new("testing")
    h:set({
      { messages = { { role = "user", content = "1" } }, date = "2023-01-01" },
      { messages = { { role = "user", content = "2" } }, date = "2023-01-02" },
      { messages = { { role = "user", content = "3" } }, date = "2023-01-03" },
    })

    equals(h.items[1], h:scroll_back())
    equals(h.items[2], h:scroll_back())
    equals(h.items[3], h:scroll_back())
    equals(h.items[2], h:scroll_forward())
    equals(h.items[1], h:scroll_forward())
  end)

  it("should add current buf content to history", function()
    local h = History:new("testing")
    h:set({
      { messages = { role = "user", content = "1" }, date = "2023-01-01" },
    })

    local items = h:update(content)

    equals(content, h.items[1].messages[1].content)
    equals(h.items, items)
  end)

  it("should update history of the past", function()
    local h = History:new("testing")
    h:set({
      { messages = { { role = "user", content = "1" } }, date = "2023-01-01" },
      { messages = { { role = "user", content = "2" } }, date = "2023-01-02" },
      { messages = { { role = "user", content = "3" } }, date = "2023-01-03" },
    })
    h.index = 2

    local items = h:update(content)

    equals(content, h.items[2].messages[1].content)
    equals(h.items, items)

    mock:clear()
  end)
end)
