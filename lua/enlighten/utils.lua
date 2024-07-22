local M = {}

---@param str string
---@param sep string
---@return string[]
function M.split(str, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = {}
  for s in string.gmatch(str, "([^" .. sep .. "]*)") do
    table.insert(t, s)
  end
  table.remove(t) -- Remove the last element, it's always an empty string
  return t
end

--- Use in a autocmd to stick the current buffer to the window
---@param buf number
---@param win number
function M.sticky_buffer(buf, win)
  if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win) then
    -- pcall necessary to avoid erroring with `mark not set` although no mark are set
    -- this avoid other issues
    -- TODO: error persists...
    pcall(vim.api.nvim_win_set_buf, win, buf)
  end
end

---@param str string
---@param start string
function M.starts_with(str, start)
  return str:sub(1, #start) == start
end

return M
