---@class AnthropicStreamingResponse
---@field type string
---@field index? number
---@field delta? AnthropicTextDelta

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
---@field prompt string
---@field temperature number
---@field system? string
---@field messages AnthropicMessage[]

-- luacheck: push ignore
local prompt_system_prompt = [[
  You are a coding assistant helping a software developer edit code in their IDE.
  All of you responses should consist of only the code you want to write. Do not include any explanations or summarys. Do not include code block markdown starting with ```.
  Match the current indentation of the code snippet.
]]

local chat_system_prompt = [[
  You are a coding assistant helping a software developer edit code in their IDE.
  You are provided a chat transcript between "Developer" and "Assistant" (you). The most recent messages are at the bottom.
  Support the developer by answering questions and following instructions. Keep your explanations concise. Do not repeat any code snippet provided.
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
function M.get_error_text(body)
  if M.is_error(body) then
    return body.error.message
  end

  return ""
end

---@param body AnthropicStreamingResponse
---@return string
function M.get_streamed_text(body)
  local completion = body.delta

  if completion then
    return completion.text or ""
  end

  return ""
end

---@return string[]
function M.build_stream_headers()
  return { "-H", "x-api-key: " .. M.get_api_key(), "-H", "anthropic-version: 2023-06-01" }
end

--- Parse the buffer content into the Anthropic messages format
---@param content string
---@return {role:string, content:string}[]
function M.build_messages(content)
  local messages = {}
  local current_role = nil
  local current_content = {}

  for line in content:gmatch("[^\r\n]+") do
    if line:match("^>>> Developer") then
      if current_role then
        table.insert(
          messages,
          { role = current_role, content = table.concat(current_content, "\n") }
        )
        current_content = {}
      end
      current_role = "user"
    elseif line:match("^>>> Assistant") then
      if current_role then
        table.insert(
          messages,
          { role = current_role, content = table.concat(current_content, "\n") }
        )
        current_content = {}
      end
      current_role = "assistant"
    elseif current_role then
      table.insert(current_content, line)
    end
  end

  if current_role then
    table.insert(messages, { role = current_role, content = table.concat(current_content, "\n") })
  end

  return messages
end

---@param feat string
---@param prompt string
---@param config EnlightenAiProviderConfig
---@return AnthropicRequest
function M.build_stream_request(feat, prompt, config)
  local system_prompt = ""
  local messages = { { role = "user", content = prompt } }
  if feat == "chat" then
    system_prompt = chat_system_prompt
    -- messages = M.build_messages(prompt)
  elseif feat == "prompt" then
    system_prompt = prompt_system_prompt
  end

  return {
    model = config.model,
    max_tokens = config.tokens,
    temperature = config.temperature,
    stream = true,
    system = system_prompt,
    messages = messages,
  }
end

return M
