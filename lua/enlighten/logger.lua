---@class EnlightenLog
---@field lines string[]
---@field max_lines number
---@field enabled boolean not used yet, but if we get reports of slow, we will use this
local EnlightenLog = {}

EnlightenLog.__index = EnlightenLog

---@param str string
---@return string
local function trim(str)
  ---@diagnostic disable-next-line: redundant-return-value
  return str:gsub("^%s+", ""):gsub("%s+$", "")
end

---@param str string
---@return string
local function remove_duplicate_whitespace(str)
  ---@diagnostic disable-next-line: redundant-return-value
  return str:gsub("%s+", " ")
end

---@param str string
---@return boolean
local function is_white_space(str)
  return str:gsub("%s", "") == ""
end

---@return EnlightenLog
function EnlightenLog:new()
  local logger = setmetatable({
    lines = {},
    enabled = true,
    max_lines = 100,
  }, self)

  return logger
end

function EnlightenLog:disable()
  self.enabled = false
end

function EnlightenLog:enable()
  self.enabled = true
end

---@vararg any
function EnlightenLog:log(...)
  local processed = {}
  for i = 1, select("#", ...) do
    local item = select(i, ...)
    if type(item) == "table" then
      item = vim.inspect(item)
    end
    table.insert(processed, item)
  end

  local lines = {}
  for _, line in ipairs(processed) do
    local s = vim.split(line, "\n")
    for _, l in ipairs(s) do
      if not is_white_space(l) then
        local ll = trim(remove_duplicate_whitespace(l))
        table.insert(lines, ll)
      end
    end
  end

  table.insert(self.lines, table.concat(lines, " "))

  while #self.lines > self.max_lines do
    table.remove(self.lines, 1)
  end
end

function EnlightenLog:clear()
  self.lines = {}
end

function EnlightenLog:show()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, self.lines)
  vim.api.nvim_win_set_buf(0, bufnr)
end

return EnlightenLog:new()
