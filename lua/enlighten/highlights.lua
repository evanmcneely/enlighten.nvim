local M = {}

local highlights = {
  EnlightenDiffAdd = { default = true, link = "DiffAdd" },
  EnlightenDiffDelete = { default = true, link = "DiffDelete" },
  EnlightenChatAssistant = { default = true, link = "ModeMsg" },
  EnlightenChatUser = { default = true, link = "ModeMsg", },
}

function M.setup()
  for k, v in pairs(highlights) do
    vim.api.nvim_set_hl(0, k, v)
  end

  -- Use markdown highlighting in the chat buffer and prompt buffers
  vim.treesitter.language.register("markdown", { "enlighten" })
end

return M
