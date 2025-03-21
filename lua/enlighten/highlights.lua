local M = {}

local function get_highlights()
  local float_title_hl = vim.api.nvim_get_hl(0, { name = "FloatTitle", link = false })
  local float_footer_hl = vim.api.nvim_get_hl(0, { name = "FloatFooter", link = false })
  local float_border_hl = vim.api.nvim_get_hl(0, { name = "FloatBorder", link = false })
  local comment_hl = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
  local function_hl = vim.api.nvim_get_hl(0, { name = "Function", link = false })
  local number_hl = vim.api.nvim_get_hl(0, { name = "Number", link = false })
  local string_hl = vim.api.nvim_get_hl(0, { name = "String", link = false })
  local cursorline_hl = vim.api.nvim_get_hl(0, { name = "Cursorline", link = false })

  return {
    EnlightenDiffAdd = { default = true, link = "DiffAdd" },
    EnlightenDiffChange = { default = true, link = "DiffText" },
    EnlightenDiffDelete = { default = true, link = "DiffDelete" },
    EnlightenChatRoleUser = { fg = string_hl.fg, bg = cursorline_hl.bg },
    EnlightenChatRoleAssistant = { fg = number_hl.fg, bg = cursorline_hl.bg },
    EnlightenChatRoleSign = { fg = function_hl.fg },
    EnlightenPromptTitle = { fg = function_hl.fg, bg = float_title_hl.bg },
    EnlightenPromptBorder = { fg = comment_hl.fg, bg = float_border_hl.bg },
    EnlightenPromptHelpMsg = { fg = comment_hl.fg, bg = float_footer_hl.bg },
    EnlightenPromptHelpKey = { fg = function_hl.fg, bg = float_footer_hl.bg },
  }
end

function M.setup()
  -- TODO test and fix issues with other major themes and default (untheme'd)
  for k, v in pairs(get_highlights()) do
    vim.api.nvim_set_hl(0, k, v)
  end

  -- Use markdown highlighting in the chat and prompt buffers
  vim.treesitter.language.register("markdown", { "enlighten" })
end

return M
