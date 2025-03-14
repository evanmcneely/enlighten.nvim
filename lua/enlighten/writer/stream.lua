local api = vim.api
local Logger = require("enlighten.logger")
local utils = require("enlighten.utils")

---@class StreamWriter: Writer
--- Position { row, column} in the buffer that text will be streamed into
---@field pos {[1]: number, [2]: number}
--- The window if the buffer we are writing to. Used to move the cursor around.
---@field window number
local StreamWriter = {}

---@param window number
---@param buffer number
---@param on_done? fun(): nil
---@return StreamWriter
function StreamWriter:new(window, buffer, on_done)
  Logger:log("stream:new", { buffer = buffer })

  self.__index = self
  return setmetatable({
    active = false,
    shortcircuit = false,
    buffer = buffer,
    window = window,
    pos = { 0, 0 },
    accumulated_text = "",
    on_done = on_done,
  }, self)
end

---@param text string
function StreamWriter:on_data(text)
  if self.shortcircuit then
    return
  end

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
      if i ~= 1 then
        new_line()
      end
      set_text(lines[i])
    end
  elseif lines[1] ~= nil then
    set_text(lines[1])
  end
end

---@param err? string
function StreamWriter:on_complete(err)
  self.active = false

  if err then
    Logger:log("stream:on_complete - error", err)
    api.nvim_err_writeln("Enlighten: " .. err)
    return
  end

  if self.shortcircuit then
    return
  end

  if self.on_done ~= nil then
    self:on_done()
  end

  Logger:log("stream:on_complete - ai completion", self.accumulated_text)
end

function StreamWriter:start()
  local count = api.nvim_buf_line_count(self.buffer)
  self.pos = { count, 0 }
  self.active = true
  self.shortcircuit = false
end

function StreamWriter:reset()
  self.accumulated_text = ""
  self.shortcircuit = false
end

function StreamWriter:stop()
  self.shortcircuit = true
end

return StreamWriter
