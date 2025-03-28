---@class AnthropicStreamingResponse
---@field type string
---@field index? number
---@field delta? AnthropicTextDelta

---@class AnthropicResponse
---@field id string
---@field type string
---@field role string
---@field model string
---@field content AnthropicContent[]
---@field stop_reason string
---@field stop_sequence string | nil

---@class AnthropicContent
---@field type string
---@field text string

---@class AnthropicTextDelta
---@field type string
---@field text? string
---@field stog_reason? string
---@field stop_sequence? string

---@class AnthropicError
---@field type string
---@field error AnthropicErrorDetails

---@class AnthropicErrorDetails
---@field type string
---@field message string

---@class AnthropicMessage
---@field role string
---@field content string

---@class AnthropicRequest
---@field model string
---@field max_tokens number
---@field stream? boolean
---@field temperature number
---@field system? string
---@field messages AnthropicMessage[]
---@field stop_sequences? string

-- luacheck: push ignore
-- Anthropic is having a very hard time respecting the indentation of the provided code snippet.
local edit_system_prompt = [[
  You are a coding assistant helping a user edit code in Neovim.
  All of your responses should consist of only the code you want to write. Do not include any explanations or summaries. Do not include code block markdown starting with ```.
  Match the current indentation of the code snippet in your response.

  You are given:
  1. Context - Code surrounding the snippet (above and below).
  2. Snippet - The specific block of code the user wants to edit in place in the buffer.
  3. Instructions - User provided instructions for editing the snippet.

  Your job is to rewrite the snippet following the users instructions. Your response will replace the snippet within the wider context.
]]

local chat_system_prompt = [[
  You are a coding assistant helping a software developer (the user) edit code in their IDE.
  Support the user by answering questions and following instructions. Keep your explanations concise. Do not repeat any code snippet provided.
]]

local get_range_prompt = [[
  You are not to respond with opening or closing ``` 
]]
-- luacheck: pop

---@class AnthropicProvider: AiProvider
local M = {}

M.name = "Anthropic"
M.endpoint = "https://api.anthropic.com/v1/messages"
M.api_key_env_var = "ANTHROPIC_API_KEY"

---@return string
function M.get_api_key()
  return os.getenv(M.api_key_env_var) or ""
end

---@param body AnthropicStreamingResponse | AnthropicError
---@return boolean
function M.is_error(body)
  return body.type == "error"
end

---@param body AnthropicStreamingResponse | AnthropicError
---@return boolean
function M.is_streaming_finished(body)
  return body.type == "message_stop"
end

---@param body AnthropicError
---@return string
function M.get_error_message(body)
  if M.is_error(body) then
    return body.error.message
  end

  return ""
end

---@param body AnthropicStreamingResponse | AnthropicResponse
---@return string
function M.get_text(body)
  if body.delta then -- streaming response
    return body.delta.text or ""
  elseif body.content and body.content[1] and body.content[1].type == "text" then -- regular response
    return body.content[1].text or ""
  end

  return ""
end

---@return string[]
function M.build_headers()
  return { "-H", "x-api-key: " .. M.get_api_key(), "-H", "anthropic-version: 2023-06-01" }
end

---@param feature string
---@return string
function M._get_system_prompt(feature)
  local system_prompt = ""
  if feature == "chat" then
    system_prompt = chat_system_prompt
  elseif feature == "edit" then
    system_prompt = edit_system_prompt
  elseif feature == "get_range" then
    system_prompt = get_range_prompt
  end
  return system_prompt
end

---@param prompt string | AiMessages
---@param opts CompletionOptions
---@return AnthropicRequest
function M.build_request(prompt, opts)
  local messages = type(prompt) == "string" and { { role = "user", content = prompt } } or prompt

  return {
    model = opts.model,
    max_tokens = opts.tokens,
    temperature = opts.temperature,
    stream = opts.stream,
    system = M._get_system_prompt(opts.feature),
    messages = messages,
  }
end

return M
