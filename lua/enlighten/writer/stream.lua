local api = vim.api
local Logger = require("enlighten/logger")
local utils = require("enlighten/utils")

---@class StreamWriter: Writer
---@field pos number[]
---@field ns_id number
---@field window number
local StreamWriter = {}

---@param window number
---@param buffer number
---@param pos number[]
---@param on_done? fun(): nil
---@return StreamWriter
function StreamWriter:new(window, buffer, pos, on_done)
  local ns_id = api.nvim_create_namespace("Enlighten")
  Logger:log("stream:new", { buffer = buffer, ns_id = ns_id, pos = pos })

  self.__index = self
  return setmetatable({
    buffer = buffer,
    window = window,
    pos = pos,
    accumulated_text = "",
    ns_id = ns_id,
    on_done = on_done,
  }, self)
end

---@param text string
function StreamWriter:on_data(text)
  self.accumulated_text = self.accumulated_text .. text

  -- Insert a new line into the buffer and update the position
  local function new_line()
    api.nvim_buf_set_lines(self.buffer, self.pos[1], self.pos[1], false, { "" })
    self.pos[1] = self.pos[1] + 1
    self.pos[2] = 0
    vim.api.nvim_win_set_cursor(self.window, self.pos)
  end

  -- Set the text at the position and update the position
  ---@param t string
  local function set_text(t)
    api.nvim_buf_set_text(
      self.buffer,
      self.pos[1] - 1,
      self.pos[2],
      self.pos[1] - 1,
      self.pos[2],
      { t }
    )
    self.pos[2] = self.pos[2] + #t
    vim.api.nvim_win_set_cursor(self.window, self.pos)
  end

  -- Handle all new line characters at the start of the string
  while utils.starts_with(text, "\n") do
    Logger:log("stream:on_data - new line", { pos = self.pos, text = text })
    new_line()
    text = text:sub(2)
  end

  if text == "" then
    return
  end

  local lines = vim.split(text, "\n")

  -- If there is only one line we can set and move on. Multiple lines
  -- indicate newline characters are in the text and need to be handled
  -- by inserting new lines into the buffer for every line after the one
  if #lines > 1 then
    for i = 1, #lines do
      Logger:log("stream:on_data - setting", { line = lines[i], pos = self.pos, text = text })
      if i ~= 1 then
        new_line()
      end
      set_text(lines[i])
    end
  elseif lines[1] ~= nil then
    Logger:log("stream:on_data - setting", { line = lines[1], pos = self.pos, text = text })
    set_text(lines[1])
  end
end

---@param err? string
function StreamWriter:on_complete(err)
  if err then
    Logger:log("stream:on_complete - error", err)
    api.nvim_err_writeln("Enlighten: " .. err)
    return
  end

  if self.on_done ~= nil then
    self:on_done()
  end

  Logger:log("stream:on_complete - ai completion", self.accumulated_text)
end

return StreamWriter
