local M = {}

---@param context EnlightenChat | EnlightenPrompt
---@return EnlightenMention[]
function M.get(context)
  return {
    {
      details = "Add files to context",
      description = "Add files to context",
      command = "files",
      callback = function()
        context.file_picker:open()
      end,
    },
    {
      details = "Add the target buffer to context",
      description = "Add the current buffer to context",
      command = "target",
      callback = function()
        context.file_picker:add_buffer(context.target_buf)
      end,
    },
    {
      details = "Add quickfix to context",
      description = "Add quickfix to context",
      command = "quickfix",
      callback = function()
        context.file_picker:add_quickfix_files()
      end,
    },
    {
      details = "Add buffers list to context",
      description = "Add quickfix to context",
      command = "buffers",
      callback = function()
        context.file_picker:add_buffer_files()
      end,
    },
  }
end

 return M
