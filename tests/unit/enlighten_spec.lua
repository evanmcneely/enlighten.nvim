local tu = require("tests.testutils")

describe("enlighten commands and keymaps", function()
  local target_buf

  before_each(function()
    ---@type Enlighten
    target_buf = vim.api.nvim_get_current_buf()
  end)

  describe("chat", function()
    it("should open the chat", function()
      -- open and initialize the chat
      vim.cmd("lua require('enlighten'):chat()")

      local buf = vim.api.nvim_get_current_buf()
      assert.are.same("enlighten", vim.api.nvim_get_option_value("filetype", { buf = buf }))
      assert.are.same("enlighten-chat", vim.api.nvim_buf_get_name(buf):match("enlighten%-chat"))

      vim.api.nvim_buf_delete(buf, {})
    end)
  end)

  describe("edit", function()
    it("should open the prompt when edit is invoked", function()
      vim.cmd("lua require('enlighten'):edit()")

      local buf = vim.api.nvim_get_current_buf()
      assert.are.same("enlighten", vim.api.nvim_get_option_value("filetype", { buf = buf }))
      assert.are.same("enlighten-prompt", vim.api.nvim_buf_get_name(buf):match("enlighten%-prompt"))
    end)

    it("should focus prompt when edit is invoked and prompt already exists for buffer", function()
      vim.cmd("lua require('enlighten'):edit()")
      local prompt_buf = vim.api.nvim_get_current_buf()

      vim.api.nvim_set_current_buf(target_buf)

      vim.cmd("lua require('enlighten'):edit()")
      tu.scheduled_equals(prompt_buf, vim.api.nvim_get_current_buf())
    end)
  end)
end)
