local M = {}

---@param str string
---@param start string
---@return boolean
function M.starts_with(str, start)
  return str:sub(1, #start) == start
end

return M
