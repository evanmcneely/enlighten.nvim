local M = {}

---@param buffer number
---@param hl_group string
---@return vim.api.keyset.get_extmarks
local function get_extmarks(buffer, hl_group)
  local namespaces = vim.api.nvim_get_namespaces()
  local ns_id = namespaces[hl_group]
  if not ns_id then
    error("No namespace id for highlight group " .. hl_group)
  end
  return vim.api.nvim_buf_get_extmarks(buffer, ns_id, 0, -1, { details = true })
end

-- Helper function to check if an extmark has a specific highlight between rows
---@param extmark any
---@param start_row number
---@param end_row number
---@param hl_group string
---@return boolean
local function extmark_has_highlight(extmark, start_row, end_row, hl_group)
  local _, s_row, _, details = unpack(extmark)
  return s_row == start_row and details.end_row == end_row and details.hl_group == hl_group
end

-- Helper function to check if an extmark has removed lines variable
---@param buffer number
---@param extmark_id number
---@return boolean
local function extmark_has_removed_lines_var(buffer, extmark_id)
  local removed_lines_var = "enlighten_removed_lines_" .. extmark_id
  local has_var, _ = pcall(vim.api.nvim_buf_get_var, buffer, removed_lines_var)
  if not has_var then
    return false
  end
  return true
end

---@param substring string
---@param content string
function M.contains(substring, content)
  assert(
    string.find(content, substring, 1, true),
    "Expected string not found in buffer content\n\n"
      .. "... Expected to find\n\n"
      .. substring
      .. "\n\n...Received\n"
      .. content
  )
end

---@param buffer number
---@param start_row number inclusive
---@param end_row number inclusive
function M.has_add_highlight(buffer, start_row, end_row)
  local extmarks = get_extmarks(buffer, "EnlightenDiffHighlights")

  for _, extmark in ipairs(extmarks) do
    if extmark_has_highlight(extmark, start_row - 1, end_row, "EnlightenDiffAdd") then
      return true
    end
  end

  error("Add highlight from row " .. start_row .. " to " .. end_row .. " does not exist")
end

---@param buffer number
---@param start_row number inclusive
---@param end_row number inclusive
---@param with_removed_var? string
function M.has_change_highlight(buffer, start_row, end_row, with_removed_var)
  local extmarks = get_extmarks(buffer, "EnlightenDiffHighlights")

  for _, extmark in ipairs(extmarks) do
    local id = extmark[1]
    if extmark_has_highlight(extmark, start_row - 1, end_row, "EnlightenDiffChange") then
      if with_removed_var and not extmark_has_removed_lines_var(buffer, id) then
        error("Change highlight exists but does not have removed lines variable")
      end
      return true
    end
  end

  error("Change highlight from row " .. start_row .. " to " .. end_row .. " does not exist")
end

---@param buffer number
---@param start_row number
---@param lines string[]
function M.has_remove_highlight(buffer, start_row, lines)
  local extmarks = get_extmarks(buffer, "EnlightenDiffHighlights")

  for _, extmark in ipairs(extmarks) do
    local id, row, _, details = unpack(extmark)
    if row == start_row - 1 and details.virt_lines then
      local found_lines = 0
      for i, line in ipairs(lines) do
        if i <= #details.virt_lines then
          local virt_line = details.virt_lines[i]
          local line_text, group = unpack(virt_line[1])
          if line_text:find("^" .. line) and group == "EnlightenDiffDelete" then
            found_lines = found_lines + 1
          end
        end
      end
      if found_lines == #lines then
        if not extmark_has_removed_lines_var(buffer, id) then
          error("Delete highlight exists but does not have removed lines variable")
        end
        return true
      end
    end
  end

  error("Delete highlight on row " .. start_row .. " with expected lines does not exist")
end

---@param buffer number
---@param start_row number inclusive
---@param end_row number inclusive
function M.no_add_highlight(buffer, start_row, end_row)
  local extmarks = get_extmarks(buffer, "EnlightenDiffHighlights")

  for _, extmark in ipairs(extmarks) do
    if extmark_has_highlight(extmark, start_row - 1, end_row, "EnlightenDiffAdd") then
      error("Add highlight from row " .. start_row .. " to " .. end_row .. " exists but should not")
    end
  end
  return true
end

---@param buffer number
---@param start_row number inclusive
---@param end_row number inclusive
function M.no_change_highlight(buffer, start_row, end_row)
  local extmarks = get_extmarks(buffer, "EnlightenDiffHighlights")

  for _, extmark in ipairs(extmarks) do
    if extmark_has_highlight(extmark, start_row - 1, end_row, "EnlightenDiffChange") then
      error(
        "Change highlight from row " .. start_row .. " to " .. end_row .. " exists but should not"
      )
    end
  end

  return true
end

---@param buffer number
---@param start_row number
function M.no_remove_highlight(buffer, start_row)
  local extmarks = get_extmarks(buffer, "EnlightenDiffHighlights")

  for _, extmark in ipairs(extmarks) do
    local _, row, _, details = unpack(extmark)
    if row == start_row - 1 and details.virt_lines and #details.virt_lines > 0 then
      local virt_line = details.virt_lines[1]
      local _, group = unpack(virt_line[1])
      if group == "EnlightenDiffDelete" then
        error("Delete highlight on row " .. start_row .. " exists but should not")
      end
    end
  end

  return true
end

function M.no_highlights_at_all(buffer)
  local extmarks = get_extmarks(buffer, "EnlightenDiffHighlights")

  if #extmarks > 0 then
    error("Expected no highlights at all, but found " .. #extmarks .. " extmarks")
  end

  return true
end

---@param buffer number
---@param mark_id number
function M.no_removed_lines_var(buffer, mark_id)
  local removed_lines_var = "enlighten_removed_lines_" .. mark_id
  local has_removed_lines, removed_lines =
    pcall(vim.api.nvim_buf_get_var, buffer, removed_lines_var)
  if has_removed_lines then
    error(
      "Removed lines variable for "
        .. mark_id
        .. " still exists with lines: "
        .. vim.inspect(removed_lines)
    )
  end
end

return M
