local api = vim.api
local utils = require("enlighten/utils")

local M = {}

M.constants = utils.protect({
  addition = "addition",
  removal = "removal",
  unchanged = "unchanged",
})

---Extract text content from virtual lines with a specific highlight group
---@param virt_lines any[][] The virtual lines from an extmark
---@param highlight_group string|nil The highlight group to filter by (optional)
---@return string[] The extracted text lines
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

---@param left string[]
---@param right string[]
---@return number[][]
function M._compute_lcs(left, right)
  local m, n = #left, #right
  local lcs = {}

  for i = 0, m do
    lcs[i] = {}
    for j = 0, n do
      if i == 0 or j == 0 then
        lcs[i][j] = 0
      elseif left[i] == right[j] then
        lcs[i][j] = lcs[i - 1][j - 1] + 1
      else
        lcs[i][j] = math.max(lcs[i - 1][j], lcs[i][j - 1])
      end
    end
  end

  return lcs
end

---@alias LineDiff {type: string, value: string}[]

--- Compute the diff for two sets of lines.
--- Ported to lua from:
---   https://github.com/florian/diff-tool
---   https://florian.github.io/diffing/
---@param left string[]
---@param right string[]
---@return LineDiff
function M.diff(left, right)
  local lcs = M._compute_lcs(left, right)
  local results = {}

  local i = #left
  local j = #right

  while i > 0 or j > 0 do
    if i > 0 and j > 0 and left[i] == right[j] then
      table.insert(results, { type = M.constants.unchanged, value = left[i] })
      i = i - 1
      j = j - 1
    elseif j > 0 and (i == 0 or lcs[i][j - 1] >= lcs[i - 1][j]) then
      table.insert(results, { type = M.constants.addition, value = right[j] })
      j = j - 1
    else
      table.insert(results, { type = M.constants.removal, value = left[i] })
      i = i - 1
    end
  end

  -- Reverse results to get the correct order (additions before deletions)
  local reversed_results = {}
  for k = #results, 1, -1 do
    table.insert(reversed_results, results[k])
  end

  return reversed_results
end

---@class Hunk
---@field add string[]
---@field remove string[]

--- Extract information about hunks from a computed diff. Hunks are
--- groups of added or removed lines (or both). Hunk row numbers are
--- for the first added line, computed from the provided start line.
---@param start_row number
---@param diff LineDiff
---@return table<number, Hunk>
function M.extract_hunks(start_row, diff)
  local hunks = {} ---@type table<number, Hunk>
  local current = nil
  local row = start_row

  local function init_hunk(r)
    current = r
    hunks[r] = { add = {}, remove = {} }
  end

  for _, line in pairs(diff) do
    if line.type == M.constants.unchanged then
      current = nil
      row = row + 1
    elseif line.type == M.constants.addition or line.type == M.constants.removal then
      if not current then
        init_hunk(row)
      end
      local hunk = hunks[current]
      if line.type == M.constants.addition then
        table.insert(hunk.add, line.value)
        row = row + 1
      else
        table.insert(hunk.remove, line.value)
      end
    end
  end

  return hunks
end

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

  api.nvim_buf_set_extmark(buffer, ns, row, -1, {
    virt_lines = virt_lines,
    -- TODO: virt_lines_above doesn't work on row 0 neovim/neovim#16166
    virt_lines_above = true,
  })
end

---@param buffer number
---@param ns number
---@param row number
---@param hunk Hunk
---@return nil
function M.highlight_changed_lines(buffer, ns, row, hunk)
  -- Has the potential to error when writing/highlighting content at the end of the buffer.
  pcall(function()
    api.nvim_buf_set_extmark(buffer, ns, row, 0, {
      end_row = row + #hunk.add,
      hl_group = "EnlightenDiffChange",
      hl_eol = true,
      priority = 1000,
    })
  end)
end

---@param range Range
function M.get_hunk_in_range(range)
  local namespaces = vim.api.nvim_get_namespaces()
  local highlight_ns = namespaces["EnlightenDiffHighlights"]

  if not highlight_ns then
    return
  end

  local current_buf = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(current_buf) then
    return
  end

  local row_start = range.row_start
  local row_end = range.row_end

  local extmarks =
    vim.api.nvim_buf_get_extmarks(current_buf, highlight_ns, 0, -1, { details = true })
  if #extmarks == 0 then
    return
  end

  -- Classify marks by type and position
  local classified_marks = {
    added = {}, -- marks with EnlightenDiffAdd
    removed = {}, -- marks with EnlightenDiffDelete virtual lines
    changed = {}, -- marks with EnlightenDiffChange
    by_row = {}, -- index marks by row for quick lookup
  }

  -- First pass: classify all marks
  for _, mark in ipairs(extmarks) do
    local mark_id = mark[1]
    local mark_row = mark[2]
    local mark_details = mark[4]
    local mark_row_end = mark_details.end_row or mark_row

    -- Store mark by row for quick position lookup
    if not classified_marks.by_row[mark_row] then
      classified_marks.by_row[mark_row] = {}
    end
    table.insert(classified_marks.by_row[mark_row], mark)

    -- Check if mark is a deletion (has EnlightenDiffDelete virtual lines)
    local is_deletion = false
    local deleted_lines
    if mark_details.virt_lines then
      local lines = extract_lines_from_virt_lines(mark_details.virt_lines, "EnlightenDiffDelete")
      is_deletion = #lines > 0
      if is_deletion then
        deleted_lines = lines
      end
    end

    if is_deletion then
      table.insert(classified_marks.removed, {
        id = mark_id,
        row = mark_row,
        mark = mark,
        lines = deleted_lines,
      })
    elseif mark_details.hl_group == "EnlightenDiffAdd" then
      table.insert(classified_marks.added, {
        id = mark_id,
        row = mark_row,
        end_row = mark_row_end,
        mark = mark,
      })
    elseif mark_details.hl_group == "EnlightenDiffChange" then
      table.insert(classified_marks.changed, {
        id = mark_id,
        row = mark_row,
        end_row = mark_row_end,
        mark = mark,
      })
    end
  end

  -- Find marks that are in the specified range or are related to marks in the range
  local marks_in_range = {
    added = {},
    removed = {},
  }
  local processed_ids = {}

  -- Process added marks in range
  for _, mark_info in ipairs(classified_marks.added) do
    local mark_overlaps_range = (mark_info.row <= row_end) and (mark_info.end_row >= row_start)

    if mark_overlaps_range and not processed_ids[mark_info.id] then
      processed_ids[mark_info.id] = true
      table.insert(marks_in_range.added, mark_info.id)

      -- Find any removal marks at the same position
      if classified_marks.by_row[mark_info.row] then
        for _, related_mark in ipairs(classified_marks.by_row[mark_info.row]) do
          local related_id = related_mark[1]
          local related_details = related_mark[4]

          if
            not processed_ids[related_id]
            and related_details.virt_lines
            and #extract_lines_from_virt_lines(related_details.virt_lines, "EnlightenDiffDelete")
              > 0
          then
            processed_ids[related_id] = true
            table.insert(marks_in_range.removed, related_id)
          end
        end
      end
    end
  end

  -- Process removal marks in range
  for _, mark_info in ipairs(classified_marks.removed) do
    local mark_overlaps_range = (mark_info.row <= row_end) and (mark_info.row >= row_start)

    if mark_overlaps_range and not processed_ids[mark_info.id] then
      processed_ids[mark_info.id] = true
      table.insert(marks_in_range.removed, mark_info.id)
    end
  end

  return marks_in_range
end

function M.keep_hunk(current_buf, hunks)
  local namespaces = vim.api.nvim_get_namespaces()
  local highlight_ns = namespaces["EnlightenDiffHighlights"]

  for _, mark_id in ipairs(hunks.added) do
    vim.api.nvim_buf_del_extmark(current_buf, highlight_ns, mark_id)
  end

  for _, mark_id in ipairs(hunks.removed) do
    vim.api.nvim_buf_del_extmark(current_buf, highlight_ns, mark_id)
  end
end

function M.reset_hunk(current_buf, hunks)
  local namespaces = vim.api.nvim_get_namespaces()
  local highlight_ns = namespaces["EnlightenDiffHighlights"]

  -- First collect all the information about marks
  local added_marks = {}
  local removed_marks = {}

  for _, mark_id in ipairs(hunks.added) do
    local mark =
      vim.api.nvim_buf_get_extmark_by_id(current_buf, highlight_ns, mark_id, { details = true })
    if mark then
      added_marks[mark_id] = {
        start_row = mark[1],
        end_row = mark[3].end_row or mark[1],
      }
    end
  end

  for _, mark_id in ipairs(hunks.removed) do
    local mark =
      vim.api.nvim_buf_get_extmark_by_id(current_buf, highlight_ns, mark_id, { details = true })
    if mark and mark[3].virt_lines then
      local lines = extract_lines_from_virt_lines(mark[3].virt_lines, "EnlightenDiffDelete")
      removed_marks[mark_id] = {
        row = mark[1],
        lines = lines,
      }
    end
  end

  -- Sort marks by row in reverse order to prevent position shifts
  local operations = {}

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

  -- Sort operations in reverse order by row to avoid position shifts
  table.sort(operations, function(a, b)
    return a.row > b.row
  end)

  -- Execute operations in the sorted order
  for _, op in ipairs(operations) do
    if op.type == "replace" then
      vim.api.nvim_buf_set_lines(current_buf, op.row, op.end_row, true, op.lines)
      vim.api.nvim_buf_del_extmark(current_buf, highlight_ns, op.added_id)
      vim.api.nvim_buf_del_extmark(current_buf, highlight_ns, op.removed_id)
    elseif op.type == "delete" then
      vim.api.nvim_buf_set_lines(current_buf, op.row, op.end_row, true, {})
      vim.api.nvim_buf_del_extmark(current_buf, highlight_ns, op.added_id)
    elseif op.type == "insert" then
      vim.api.nvim_buf_set_lines(current_buf, op.row, op.row, true, op.lines)
      vim.api.nvim_buf_del_extmark(current_buf, highlight_ns, op.removed_id)
    end
  end
end

return M
