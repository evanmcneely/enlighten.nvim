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

---@param type string
---@param text? string
---@return AnthropicStreamingResponse
function M.anthropic_response(type, text)
  local responses = {
    message_start = {
      type = "message_start",
      message = {
        id = "msg_01J34gY9WFCkWUxe4RkjUbcS",
        type = "message",
        role = "assistant",
        model = "claude-3-5-sonnet-20240620",
        content = {},
        stop_reason = nil,
        stop_sequence = nil,
        usage = {
          input_tokens = 102,
          output_tokens = 3,
        },
      },
    },
    content_block_start = {
      type = "content_block_start",
      index = 0,
      content_block = {
        type = "text",
        text = "",
      },
    },
    ping = {
      type = "ping",
    },
    content_block_delta = {
      type = "content_block_delta",
      index = 0,
      delta = {
        type = "text_delta",
        text = text,
      },
    },
    content_block_stop = {
      type = "content_block_stop",
      index = 0,
    },
    message_delta = {
      type = "message_delta",
      delta = {
        stop_reason = "end_turn",
        stop_sequence = nil,
      },
      usage = {
        output_tokens = 15,
      },
    },
    message_stop = {
      type = "message_stop",
    },
  }

  return responses[type] or {}
end

---@return OpenAIError
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

---@return AnthropicError
function M.anthropic_error()
  return {
    type = "error",
    error = {
      type = "invalid_request_error",
      message = "max_tokens: Field required",
    },
  }
end

---@param keys string
local function escape_keys(keys)
  return vim.api.nvim_replace_termcodes(keys, true, false, true)
end

---@param keys string
function M.feedkeys(keys)
  vim.api.nvim_feedkeys(escape_keys(keys), "xm", true)
end

---@param want any
---@param got any
function M.scheduled_equals(want, got)
  vim.schedule(function()
    assert.are.same(want, got)
  end)
end

return M
