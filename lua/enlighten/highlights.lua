local M = {}

local highlights = {
  EnlightenDiffAdd = { default = true, link = "DiffAdd" },
  EnlightenDiffDelete = { default = true, link = "DiffDelete" },
  EnlightenChatRole = { default = true, link = "ModeMsg" },
  EnlightenPromptTitle = { default = true, link = "ModeMsg" },
  EnlightenPromptHelpMsg = { default = true, link = "ModeMsg" },
  EnlightenPromptHelpKey = { default = true, link = "Function" },
}

function M.setup()
  for k, v in pairs(highlights) do
    vim.api.nvim_set_hl(0, k, v)
  end

  -- Use markdown highlighting in the chat buffer and prompt buffers
  vim.treesitter.language.register("markdown", { "enlighten" })
end

return M
