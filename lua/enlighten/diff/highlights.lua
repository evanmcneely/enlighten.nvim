local api = vim.api

local M = {}

---Extract text content from virtual lines with a specific highlight group
---@param virt_lines any[][]
---@param highlight_group string|nil
---@return string[]
local function extract_lines_from_virt_lines(virt_lines, highlight_group)
  local lines = {}

  if not virt_lines then
    return lines
  end

  for _, virt_line in ipairs(virt_lines) do
    for _, virt_text in ipairs(virt_line) do
      local text, hl_group = virt_text[1], virt_text[2]
      if not highlight_group or hl_group == highlight_group then
        -- Remove trailing spaces that were added to fill the line
        local content = text:gsub("%s+$", "")
        table.insert(lines, content)
        break -- Only take the first matching text chunk from each virtual line
      end
    end
  end

  return lines
end

local function set_removed_lines_var(buffer, mark_id, value)
  local removed_lines_var = "enlighten_removed_lines_" .. mark_id
  api.nvim_buf_set_var(buffer, removed_lines_var, value)
end

local function clear_removed_lines_var(buffer, mark_id)
  local removed_lines_var = "enlighten_removed_lines_" .. mark_id
  pcall(api.nvim_buf_del_var, buffer, removed_lines_var)
end

local function get_removed_lines_var(buffer, mark_id)
  local removed_lines_var = "enlighten_removed_lines_" .. mark_id
  local has_removed_lines, removed_lines = pcall(api.nvim_buf_get_var, buffer, removed_lines_var)
  return has_removed_lines or false, removed_lines or {}
end

---@class MarkData
---@field mark vim.api.keyset.get_extmark_item
---@field id number
---@field row number
---@field row_end number
---@field lines string[]

---@class ClassifiedMarks
---@field added MarkData[] marks with EnlightenDiffAdd virtual lines
---@field removed MarkData[] marks with EnlightenDiffDelete virtual lines
---@field changed MarkData[] marks with EnlightenDiffChange
---@field by_row table<number, MarkData[]> index marks by row for quick lookup

---@class Operation
---@field type string "replace"|"delete"|"insert"
---@field row number Starting row of the operation
---@field end_row? number Ending row for replace/delete operations
---@field lines? string[] Lines to replace
---@field added_id? number ID of the extmark representing added lines
---@field removed_id? number ID of the extmark representing removed lines

---Applies a ADD highlight to the provided buffer for the specific hunk and row
---@param buffer number
---@param ns number
---@param row number
---@param hunk Hunk
---@return nil
function M.highlight_added_lines(buffer, ns, row, hunk)
  -- Has the potential to error when writing/highlighting content at the end of the buffer.
  pcall(function()
    api.nvim_buf_set_extmark(buffer, ns, row, 0, {
      end_row = row + #hunk.add,
      hl_group = "EnlightenDiffAdd",
      hl_eol = true,
      priority = 1000,
    })
  end)
end

---Applies a REMOVED highlight to the provided buffer for the specific hunk and row
---@param buffer number
---@param ns number
---@param row number
---@param hunk Hunk
---@return nil
function M.highlight_removed_lines(buffer, ns, row, hunk)
  local virt_lines = {} --- @type {[1]: string, [2]: string}[][]

  for _, line in pairs(hunk.remove) do
    table.insert(
      virt_lines,
      { { line .. string.rep(" ", vim.o.columns or 0), "EnlightenDiffDelete" } }
    )
  end

  local mark_id = api.nvim_buf_set_extmark(buffer, ns, row, -1, {
    virt_lines = virt_lines,
    -- TODO: virt_lines_above doesn't work on row 0 neovim/neovim#16166
    virt_lines_above = true,
  })

  set_removed_lines_var(buffer, mark_id, hunk.remove)
end

---Applies a CHANGED highlight to the provided buffer for the specific hunk and row
---@param buffer number
---@param ns number
---@param row number
---@param hunk Hunk
---@return nil
function M.highlight_changed_lines(buffer, ns, row, hunk)
  -- Has the potential to error when writing/highlighting content at the end of the buffer.
  pcall(function()
    local mark_id = api.nvim_buf_set_extmark(buffer, ns, row, 0, {
      end_row = row + #hunk.add,
      hl_group = "EnlightenDiffChange",
      hl_eol = true,
      priority = 1000,
    })

    set_removed_lines_var(buffer, mark_id)
  end)
end

--- Find and return the hunks that partially overlap with the provided range using
--- the diff highlight data on extmarks. If this cannot be completed for some reason,
--- we return nil
---@param buffer number
---@param range SelectionRange
---@return ClassifiedMarks|nil
function M.get_hunk_in_range(buffer, range)
  local namespaces = api.nvim_get_namespaces()
  local ns = namespaces["EnlightenDiffHighlights"]

  if not ns then
    return nil
  end

  local extmarks = vim.api.nvim_buf_get_extmarks(buffer, ns, 0, -1, { details = true })
  if #extmarks == 0 then
    return nil
  end

  ---@type ClassifiedMarks
  local classified_marks = {
    added = {},
    removed = {},
    changed = {},
    by_row = {},
  }

  -- First pass: classify all marks
  for _, mark in ipairs(extmarks) do
    local mark_id, mark_row, _, mark_details = mark[1], mark[2], mark[3], mark[4]
    local mark_row_end = mark_details.end_row or mark_row

    ---@type MarkData
    local data = {
      mark = mark,
      id = mark_id,
      row = mark_row,
      row_end = mark_row_end,
      lines = {},
    }

    -- Store mark by row for quick position lookup
    classified_marks.by_row[mark_row] = classified_marks.by_row[mark_row] or {}
    table.insert(classified_marks.by_row[mark_row], data)

    local has_removed_lines, removed_lines = get_removed_lines_var(buffer, mark_id)
    if has_removed_lines and removed_lines then
      data.lines = removed_lines
    end

    -- Check if mark is a deletion (has EnlightenDiffDelete virtual lines)
    if mark_details.virt_lines then
      local lines = extract_lines_from_virt_lines(mark_details.virt_lines, "EnlightenDiffDelete")
      if #lines > 0 then
        data.lines = lines
        table.insert(classified_marks.removed, data)
      end
    end

    -- Categorize marks by type of change
    if mark_details.hl_group == "EnlightenDiffAdd" then
      table.insert(classified_marks.added, data)
    elseif mark_details.hl_group == "EnlightenDiffChange" then
      table.insert(classified_marks.changed, data)
    else
      table.insert(classified_marks.removed, data)
    end
  end

  -- Find marks that are in the specified range or are related to marks in the range
  ---@type ClassifiedMarks
  local marks_in_range = {
    added = {},
    removed = {},
    changed = {},
    by_row = {},
  }
  local processed_ids = {} ---@type table<number, boolean>

  -- Helper function to check if a mark overlaps with the range
  ---@param mark_data MarkData
  ---@return boolean
  local function mark_overlaps_range(mark_data)
    return (mark_data.row <= range.row_end) and (mark_data.row_end >= range.row_start)
  end

  -- Helper function to check if a mark has already been processed
  ---@param mark_data MarkData
  ---@return boolean
  local function mark_already_processed(mark_data)
    return processed_ids[mark_data.id] or false
  end

  -- Process added marks in range
  for _, mark_data in ipairs(classified_marks.added) do
    if mark_overlaps_range(mark_data) and not mark_already_processed(mark_data) then
      processed_ids[mark_data.id] = true
      table.insert(marks_in_range.added, mark_data)

      -- Find any removal marks at the same position
      if classified_marks.by_row[mark_data.row] then
        for _, related_mark in ipairs(classified_marks.by_row[mark_data.row]) do
          if not mark_already_processed(related_mark) and #related_mark.lines > 0 then
            processed_ids[related_mark.id] = true
            table.insert(marks_in_range.removed, related_mark)
          end
        end
      end
    end
  end

  -- Process changed marks in range
  for _, mark_data in ipairs(classified_marks.changed) do
    if mark_overlaps_range(mark_data) and not mark_already_processed(mark_data) then
      processed_ids[mark_data.id] = true
      table.insert(marks_in_range.changed, mark_data)
    end
  end

  -- Process removal marks in range
  for _, mark_data in ipairs(classified_marks.removed) do
    if
      mark_data.row >= range.row_start
      and mark_data.row <= range.row_end
      and not mark_already_processed(mark_data)
    then
      processed_ids[mark_data.id] = true
      table.insert(marks_in_range.removed, mark_data)
    end
  end

  return marks_in_range
end

--- Clear the diff highlights while keeping any changes from the provided hunks.
--- * Changed lines are not handled here yet *
---@param buffer number
---@param hunks ClassifiedMarks
function M.keep_hunk(buffer, hunks)
  local namespaces = api.nvim_get_namespaces()
  local highlight_ns = namespaces["EnlightenDiffHighlights"]

  for _, mark in ipairs(hunks.added) do
    api.nvim_buf_del_extmark(buffer, highlight_ns, mark.id)
  end

  for _, mark in ipairs(hunks.removed) do
    api.nvim_buf_del_extmark(buffer, highlight_ns, mark.id)
    clear_removed_lines_var(buffer, mark.id)
  end

  for _, mark in ipairs(hunks.changed) do
    api.nvim_buf_del_extmark(buffer, highlight_ns, mark.id)
    clear_removed_lines_var(buffer, mark.id)
  end
end

--- Clear the diff highlights while resetting any changes from the provided hunks.
--- * Changed lines are not handled here yet *
---@param buffer number
---@param hunks ClassifiedMarks
function M.reset_hunk(buffer, hunks)
  local namespaces = api.nvim_get_namespaces()
  local highlight_ns = namespaces["EnlightenDiffHighlights"]

  -- First collect all the information about marks
  local added_marks = {}
  local removed_marks = {}
  local changed_marks = {}

  for _, mark in ipairs(hunks.added) do
    if mark then
      added_marks[mark.id] = {
        start_row = mark.row,
        end_row = mark.row_end,
      }
    end
  end

  for _, mark in ipairs(hunks.removed) do
    if mark and mark.lines then
      removed_marks[mark.id] = {
        row = mark.row,
        lines = mark.lines,
      }
    end
  end

  for _, mark in ipairs(hunks.changed) do
    if mark and mark.lines then
      changed_marks[mark.id] = {
        row = mark.row,
        end_row = mark.row_end,
        lines = mark.lines,
      }
    end
  end

  -- changed marks are not handled here yet

  local operations = {} ---@type Operation[]

  -- Create operations for matching pairs
  for added_id, added_info in pairs(added_marks) do
    for removed_id, removed_info in pairs(removed_marks) do
      if added_info.start_row == removed_info.row then
        table.insert(operations, {
          type = "replace",
          row = added_info.start_row,
          end_row = added_info.end_row,
          lines = removed_info.lines,
          added_id = added_id,
          removed_id = removed_id,
        })
        -- Mark as matched
        added_marks[added_id] = nil
        removed_marks[removed_id] = nil
        break
      end
    end
  end

  -- Create operations for unmatched added marks (delete)
  for added_id, added_info in pairs(added_marks) do
    table.insert(operations, {
      type = "delete",
      row = added_info.start_row,
      end_row = added_info.end_row,
      added_id = added_id,
    })
  end

  -- Create operations for unmatched removed marks (insert)
  for removed_id, removed_info in pairs(removed_marks) do
    table.insert(operations, {
      type = "insert",
      row = removed_info.row,
      lines = removed_info.lines,
      removed_id = removed_id,
    })
  end

  -- Create operations for unmatched removed marks (insert)
  for changed_id, changed_info in pairs(changed_marks) do
    table.insert(operations, {
      type = "replace",
      row = changed_info.row,
      end_row = changed_info.end_row,
      lines = changed_info.lines,
      added_id = changed_id,
      removed_id = nil,
    })
  end

  -- Sort operations in reverse order by row to avoid position shifts
  table.sort(operations, function(a, b)
    return a.row > b.row
  end)

  -- Execute operations in the sorted order
  for _, op in ipairs(operations) do
    if op.type == "replace" then
      api.nvim_buf_set_lines(buffer, op.row, op.end_row, true, op.lines)
      api.nvim_buf_del_extmark(buffer, highlight_ns, op.added_id)
      if op.removed_id then
        api.nvim_buf_del_extmark(buffer, highlight_ns, op.removed_id)
        clear_removed_lines_var(buffer, op.removed_id)
      end
      clear_removed_lines_var(buffer, op.added_id)
    elseif op.type == "delete" then
      api.nvim_buf_set_lines(buffer, op.row, op.end_row, true, {})
      api.nvim_buf_del_extmark(buffer, highlight_ns, op.added_id)
    elseif op.type == "insert" then
      api.nvim_buf_set_lines(buffer, op.row, op.row, true, op.lines)
      api.nvim_buf_del_extmark(buffer, highlight_ns, op.removed_id)
      clear_removed_lines_var(buffer, op.removed_id)
    end
  end
end

return M
