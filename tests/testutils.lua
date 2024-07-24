local M = {}

---@param content string
---@return number
function M.prepare_buffer(content)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_command("buffer " .. buf)
  vim.api.nvim_buf_set_lines(0, 0, -1, true, vim.split(content, "\n"))
  return buf
end

---@param text string
---@param finish_reason? string
---@return OpenAIStreamingResponse
function M.openai_response(text, finish_reason)
  return {
    id = "chatcmpl-9nxbCSxY2A7Jp9nOBDhu4jdo9z6ME",
    object = "chat.completion.chunk",
    created = 1721694198,
    model = "gpt-4o-2024-05-13",
    system_fingerprint = "fp_400f27fa1f",
    choices = {
      {
        index = 0,
        delta = { content = text },
        logprobs = nil,
        finish_reason = finish_reason,
      },
    },
  }
end

function M.openai_error()
  return {
    error = {
      type = "invalid_request_error",
      code = "unknown_url",
      message = "Unknown request URL: POST /v1/chat/completion.",
      param = nil,
    },
  }
end

return M
