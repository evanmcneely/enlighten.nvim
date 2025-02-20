local M = {}

--- Check if the provided string starts with the substring
---@param str string
---@param sub_str string
---@return boolean
function M.starts_with(str, sub_str)
  return str:sub(1, #sub_str) == sub_str
end

--- Create a slice of the table from the start index (inclusive) to
--- end index (exclusive). Returns a new table without modifying the
--- existing table.
---@param tbl table
---@param start_idx number
---@param end_idx number
---@return table
function M.slice(tbl, start_idx, end_idx)
  local sliced = {}
  for i = start_idx or 1, end_idx or #tbl do
    sliced[#sliced + 1] = tbl[i]
  end
  return sliced
end

---Returns a protected table that prevents modifications to it's keys
---by throwing an error if a change is attempted.
---@param tbl table
function M.protect(tbl)
  return setmetatable({}, {
    __index = tbl,
    __newindex = function(_, key, value)
      error("attempting to change constant " .. tostring(key) .. " to " .. tostring(value), 2)
    end,
  })
end

--- Removes elements from the table at the start and end that are empty
--- strings, modifying the table in place.
---@param tbl string[]
function M.trim_empty_lines(tbl)
  while tbl[1] == "" do
    table.remove(tbl, 1)
  end
  while tbl[#tbl] == "" do
    table.remove(tbl)
  end
  return tbl
end

return M
