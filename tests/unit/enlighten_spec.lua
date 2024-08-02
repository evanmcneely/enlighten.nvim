describe("enlighten commands and keymaps", function()
  local enlighten
  local target_buf

  before_each(function()
    ---@type Enlighten
    enlighten = require("enlighten")
    target_buf = vim.api.nvim_get_current_buf()
  end)

  describe("chat", function()
    it("should open and close the chat when toggle_chat is invoked", function()
      -- chat should open and initialize the chat
      vim.cmd("lua require('enlighten'):toggle_chat()")

      local buf = vim.api.nvim_get_current_buf()
      assert.are_truthy(enlighten.chat)
      assert.are.same(buf, enlighten.chat.chat_buf)
      assert.are.same(target_buf, enlighten.chat.target_buf)

      -- chat should close
      vim.cmd("lua require('enlighten'):toggle_chat()")
      assert.are_nil(enlighten.chat)
    end)

    it(
      "should open the chat when open_chat is invoked and close it when close_chat is invoked",
      function()
        -- chat should open and initialize the chat
        vim.cmd("lua require('enlighten'):open_chat()")

        local buf = vim.api.nvim_get_current_buf()
        assert.are_truthy(enlighten.chat)
        assert.are.same(buf, enlighten.chat.chat_buf)
        assert.are.same(target_buf, enlighten.chat.target_buf)

        -- chat should close
        vim.cmd("lua require('enlighten'):close_chat()")
        assert.are_nil(enlighten.chat)
      end
    )
  end)

  describe("prompt", function()
    it("should open and close the prompt when toggle_prompt is invoked", function()
      -- prompt should open and initialize the prompt
      vim.cmd("lua require('enlighten'):toggle_prompt()")

      local buf = vim.api.nvim_get_current_buf()
      assert.are_truthy(enlighten.prompt)
      assert.are.same(buf, enlighten.prompt.prompt_buf)
      assert.are.same(target_buf, enlighten.prompt.target_buf)

      -- prompt should close
      vim.cmd("lua require('enlighten'):toggle_prompt()")
      assert.are_nil(enlighten.prompt)
    end)

    it(
      "should open the prompt when open_prompt is invoked and close it when close_prompt is invoked",
      function()
        -- prompt should open and initialize the prompt
        vim.cmd("lua require('enlighten'):open_prompt()")

        local buf = vim.api.nvim_get_current_buf()
        assert.are_truthy(enlighten.prompt)
        assert.are.same(buf, enlighten.prompt.prompt_buf)
        assert.are.same(target_buf, enlighten.prompt.target_buf)

        -- prompt should close
        vim.cmd("lua require('enlighten'):close_prompt()")
        assert.are_nil(enlighten.prompt)
      end
    )
  end)
end)
