local api = vim.api
local utils = require("enlighten/utils")

local M = {}

M.constants = utils.protect({
  addition = "addition",
  removal = "removal",
  unchanged = "unchanged",
})

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

  local found_marks = {
    added = {},
    removed = {},
  }
  local processed_ids = {}
  local add_mark_positions = {}
  local add_marks_in_range = {}

  -- First pass: identify all EnlightenDiffAdd marks and their positions
  for _, mark in ipairs(extmarks) do
    local hl_group = mark[4].hl_group
    local mark_row_start = mark[2]
    local mark_row_end = mark[4].end_row or mark_row_start

    if
      hl_group == "EnlightenDiffAdd"
      -- ignoring EnlightenDiffChange highlights because we loose the deleted lines
      -- needed to perform reset operations
      -- or hl_group == "EnlightenDiffChange"
    then
      -- Check if mark overlaps with the range
      if (mark_row_start <= row_end) and (mark_row_end >= row_start) then
        add_mark_positions[mark_row_start] = true
        table.insert(add_marks_in_range, { id = mark[1], row = mark_row_start })
      end
    end
  end

  -- Second pass: process all marks
  for _, mark in ipairs(extmarks) do
    local mark_id = mark[1]
    local hl_group = mark[4].hl_group
    local mark_row_start = mark[2]
    local mark_row_end = mark[4].end_row or mark_row_start
    local mark_is_delete = false

    -- Check if mark has virtual lines with EnlightenDiffDelete
    if mark[4].virt_lines then
      for _, virt_line in ipairs(mark[4].virt_lines) do
        for _, virt_text in ipairs(virt_line) do
          if virt_text[2] == "EnlightenDiffDelete" then
            mark_is_delete = true
            break
          end
        end
        if mark_is_delete then
          break
        end
      end
    end

    -- Process marks that are relevant to our highlighting
    if
      mark_is_delete or hl_group == "EnlightenDiffAdd"
      -- or hl_group == "EnlightenDiffChange"
    then
      -- Check if mark overlaps with range OR if this is a delete mark at the same position as an add mark in range
      if
        ((mark_row_start <= row_end) and (mark_row_end >= row_start))
        or (mark_is_delete and add_mark_positions[mark_row_start])
      then
        -- Avoid duplicates by checking the mark ID
        if not processed_ids[mark_id] then
          processed_ids[mark_id] = true

          if mark_is_delete then
            table.insert(found_marks.removed, mark_id)
          elseif hl_group == "EnlightenDiffAdd" or hl_group == "EnlightenDiffChange" then
            table.insert(found_marks.added, mark_id)
          end
        end
      end
    end
  end

  -- Third pass: look for delete marks at the same position as add marks in range
  if #add_marks_in_range > 0 then
    for _, mark in ipairs(extmarks) do
      local mark_id = mark[1]
      local mark_row_start = mark[2]
      local mark_is_delete = false

      if mark[4].virt_lines then
        for _, virt_line in ipairs(mark[4].virt_lines) do
          for _, virt_text in ipairs(virt_line) do
            if virt_text[2] == "EnlightenDiffDelete" then
              mark_is_delete = true
              break
            end
          end
          if mark_is_delete then
            break
          end
        end
      end

      if mark_is_delete then
        for _, add_mark in ipairs(add_marks_in_range) do
          if mark_row_start == add_mark.row and not processed_ids[mark_id] then
            processed_ids[mark_id] = true
            table.insert(found_marks.removed, mark_id)
          end
        end
      end
    end
  end

  return found_marks
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
      local lines = {}
      for _, virt_line in ipairs(mark[3].virt_lines) do
        for _, virt_text in ipairs(virt_line) do
          if virt_text[2] == "EnlightenDiffDelete" then
            -- Remove trailing spaces that were added to fill the line
            local content = virt_text[1]:gsub("%s+$", "")
            table.insert(lines, content)
          end
        end
      end
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
