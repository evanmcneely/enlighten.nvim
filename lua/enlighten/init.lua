local Edit = require("enlighten/edit")
local Chat = require("enlighten/chat")
local config = require("enlighten/config")
local highlights = require("enlighten/highlights")
local Logger = require("enlighten/logger")

---@class Enlighten
--- Full plugin configuration with default values overridden by user provided ones.
---@field config EnlightenConfig
--- `true` after the setup method completes successfully. Check for this to ensure
--- sure the config is set and environment is valid.
---@field setup_complete boolean
--- Helpful logger for debugging.
---@field logger EnlightenLog
local enlighten = {
  config = config.config,
  setup_complete = false,
  logger = Logger,
}

---@param user_config EnlightenPartialConfig?
function enlighten.setup(user_config)
  local all_good = config.validate_environment()
  if not all_good then
    return
  end

  enlighten.config = config.build_config(user_config)
  highlights.setup()
  enlighten.setup_complete = true
end

function enlighten.edit()
  if not enlighten.setup_complete then
    return
  end

  local current_win = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_buf_type = vim.api.nvim_get_option_value("filetype", { buf = current_buf })

  -- If the current buffer is one of ours, do nothing
  if current_buf_type == "enlighten" then
    return
  end

  local windows = vim.api.nvim_list_wins()

  for _, win in ipairs(windows) do
    local window_config = vim.api.nvim_win_get_config(win)
    local window_buf = vim.api.nvim_win_get_buf(win)
    local window_buf_type = vim.api.nvim_get_option_value("filetype", { buf = window_buf })

    -- If we find an enlighten popup relative to the current window, focus it
    if
      window_buf_type == "enlighten"
      and window_config.relative == "win"
      and window_config.win == current_win
    then
      vim.api.nvim_set_current_win(win)
      return
    end
  end

  Edit:new(enlighten.config.ai.edit, enlighten.config.settings.edit)
end

function enlighten.chat()
  if not enlighten.setup_complete then
    return
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local current_buf_type = vim.api.nvim_get_option_value("filetype", { buf = current_buf })

  -- If the current buffer is one of ours, do nothing
  if current_buf_type == "enlighten" then
    return
  end

  Chat:new(enlighten.config.ai.chat, enlighten.config.settings.chat)
end

function enlighten.debug_highlights()
  if not enlighten.setup_complete then
    return
  end

  local namespaces = vim.api.nvim_get_namespaces()
  local highlight_ns = namespaces["EnlightenDiffHighlights"]

  if not highlight_ns then
    print("EnlightenDiffHighlights namespace not found")
    return
  end

  local current_buf = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(current_buf) then
    print("Current buffer is not valid")
    return
  end

  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_row = cursor_pos[1] - 1 -- Convert to 0-indexed

  local extmarks =
    vim.api.nvim_buf_get_extmarks(current_buf, highlight_ns, 0, -1, { details = true })
  if #extmarks == 0 then
    print("No extmarks found in current buffer")
    return
  end

  local found = false
  local found_marks = {
    added = {},
    removed = {},
  }
  local processed_ids = {}
  local add_mark_positions = {}

  -- First pass: identify all EnlightenDiffAdd marks and their positions
  for _, mark in ipairs(extmarks) do
    local hl_group = mark[4].hl_group
    local mark_row_start = mark[2]

    if hl_group == "EnlightenDiffAdd" or hl_group == "EnlightenDiffChange" then
      if cursor_row >= mark_row_start and cursor_row <= (mark[4].end_row or mark_row_start) then
        add_mark_positions[mark_row_start] = true
      end
    end
  end

  -- Second pass: process all marks
  for _, mark in ipairs(extmarks) do
    local mark_id = mark[1]
    local hl_group = mark[4].hl_group
    local mark_row_start = mark[2]
    local mark_row_end = mark[4].end_row or mark_row_start
    local has_virt_lines_with_delete = false

    -- Check if mark has virtual lines with EnlightenDiffDelete
    if mark[4].virt_lines then
      for _, virt_line in ipairs(mark[4].virt_lines) do
        for _, virt_text in ipairs(virt_line) do
          if virt_text[2] == "EnlightenDiffDelete" then
            has_virt_lines_with_delete = true
            break
          end
        end
        if has_virt_lines_with_delete then
          break
        end
      end
    end

    -- Process marks that are relevant to our highlighting
    if
      has_virt_lines_with_delete
      or hl_group == "EnlightenDiffAdd"
      or hl_group == "EnlightenDiffChange"
    then
      -- Check if cursor is on this mark OR if this is a delete mark at the same position as an add mark under cursor
      if
        (cursor_row >= mark_row_start and cursor_row <= mark_row_end)
        or (has_virt_lines_with_delete and add_mark_positions[mark_row_start])
      then
        found = true

        -- Avoid duplicates by checking the mark ID
        if not processed_ids[mark_id] then
          processed_ids[mark_id] = true

          if has_virt_lines_with_delete then
            table.insert(found_marks.removed, mark_id)
          elseif hl_group == "EnlightenDiffAdd" or hl_group == "EnlightenDiffChange" then
            table.insert(found_marks.added, mark_id)
          end
        end
      end
    end
  end

  if not found then
    print("No extmarks found at cursor position")
  else
    print("Extmarks at cursor position (row " .. (cursor_row + 1) .. "):")
    print(vim.inspect(found_marks))
  end
end

return enlighten
