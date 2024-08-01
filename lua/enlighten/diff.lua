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

-- Compute the diff for two sets of lines.
--
-- Ported to lua from:
--   https://github.com/florian/diff-tool
--   https://florian.github.io/diffing/
---@param left string[]
---@param right string[]
---@return LineDiff
function M.diff(left, right)
  local lcs = M._compute_lcs(left, right)
  local results = {}

  local i = #left
  local j = #right

  while i > 0 or j > 0 do
    if i == 0 then
      table.insert(results, { type = M.constants.addition, value = right[j] })
      j = j - 1
    elseif j == 0 then
      table.insert(results, { type = M.constants.removal, value = left[i] })
      i = i - 1
    elseif left[i] == right[j] then
      table.insert(results, { type = M.constants.unchanged, value = left[i] })
      i = i - 1
      j = j - 1
    elseif lcs[i - 1][j] >= lcs[i][j - 1] then
      table.insert(results, { type = M.constants.removal, value = left[i] })
      i = i - 1
    else
      table.insert(results, { type = M.constants.addition, value = right[j] })
      j = j - 1
    end
  end

  -- Reverse results to get the correct order
  local reversed_results = {}
  for k = #results, 1, -1 do
    table.insert(reversed_results, results[k])
  end

  return reversed_results
end

---@class Hunk
---@field add string[]
---@field remove string[]

-- Extract information about hunks from a computed diff. Hunks are
-- groups of added or removed lines (or both).Hunk row numbers are
-- for the first added line, computed from the provided start line.
---@param start_row number
---@param diff LineDiff
---@return table<number, Hunk>
function M.extract_hunks(start_row, diff)
  local hunks = {}
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

return M
