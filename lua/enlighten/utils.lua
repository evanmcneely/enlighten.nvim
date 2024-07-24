local M = {}

---@param str string
---@param start string
function M.starts_with(str, start)
  return str:sub(1, #start) == start
end

return M
