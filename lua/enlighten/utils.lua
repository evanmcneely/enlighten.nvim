local M = {}

---@param str string
---@param start string
---@return boolean
function M.starts_with(str, start)
  return str:sub(1, #start) == start
end

function M.slice(tbl, start_idx, end_idx)
  local sliced = {}
  for i = start_idx or 1, end_idx or #tbl do
    sliced[#sliced + 1] = tbl[i]
  end
  return sliced
end

---@param tbl table
function M.protect(tbl)
  return setmetatable({}, {
    __index = tbl,
    __newindex = function(_, key, value)
      error("attempting to change constant " .. tostring(key) .. " to " .. tostring(value), 2)
    end,
  })
end

return M
