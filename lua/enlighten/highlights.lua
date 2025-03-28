local M = {}

local function get_highlights()
  local float_title_hl = vim.api.nvim_get_hl(0, { name = "FloatTitle", link = false })
  local comment_hl = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
  local function_hl = vim.api.nvim_get_hl(0, { name = "Function", link = false })
  local number_hl = vim.api.nvim_get_hl(0, { name = "Number", link = false })
  local string_hl = vim.api.nvim_get_hl(0, { name = "String", link = false })
  local cursorline_hl = vim.api.nvim_get_hl(0, { name = "Cursorline", link = false })
  local removed_fg_hl = vim.api.nvim_get_hl(0, { name = "diffRemoved", link = false })
  local removed_bg_hl = vim.api.nvim_get_hl(0, { name = "DiffDelete", link = false })
  local normal_hl = vim.api.nvim_get_hl(0, { name = "NormalFloat", link = false })

  return {
    EnlightenDiffAdd = { default = true, link = "DiffAdd" },
    EnlightenDiffChange = { default = true, link = "DiffText" },
    EnlightenDiffDelete = { fg = removed_fg_hl.fg, bg = removed_bg_hl.bg or "#616161" }, -- grey fallback
    EnlightenChatRoleUser = { fg = string_hl.fg, bg = cursorline_hl.bg },
    EnlightenChatRoleAssistant = { fg = number_hl.fg, bg = cursorline_hl.bg },
    EnlightenChatRoleSign = { fg = function_hl.fg },
    EnlightenPromptTitle = { fg = float_title_hl.fg, bg = normal_hl.bg },
    EnlightenPromptBorder = { fg = comment_hl.fg, bg = normal_hl.bg },
    EnlightenPromptHelpMsg = { fg = comment_hl.fg, bg = normal_hl.bg },
    EnlightenPromptHelpKey = { fg = float_title_hl.fg, bg = normal_hl.bg },
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
