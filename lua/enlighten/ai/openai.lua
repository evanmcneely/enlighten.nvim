--- General format for chat messages.
---@alias AiRole "user"|"assistant"
---@alias AiMessages {role:AiRole, content:string}[]

---@class OpenAIStreamingResponse
---@field id string
---@field object string
---@field created number
---@field model string
---@field system_fingerprint string
---@field choices OpenAIStreamingChoice[]

---@class OpenAIResponse
---@field id string
---@field object string
---@field created number
---@field model string
---@field choices OpenAIChoice[]

---@class OpenAIStreamingChoice
---@field index number
---@field delta? OpenAIDelta
---@field logprobs any
---@field finish_reason any

---@class OpenAIChoice
---@field index number
---@field message OpenAIMessage
---@field logprobs any
---@field finish_reason any

---@class OpenAIDelta
---@field role string
---@field content string

---@class OpenAIErrorDetails
---@field message string
---
---@class OpenAIError
---@field error OpenAIErrorDetails

---@class OpenAIMessage
---@field role string
---@field content string
---@field refusal any

---@class OpenAIRequest
---@field model string
---@field max_tokens? number
---@field stream? boolean
---@field temperature? number
---@field messages OpenAIMessage[]
---@field response_format? OpenAIResponseFormat

---@class OpenAIResponseFormat
---@field type string

-- luacheck: push ignore
local edit_system_prompt = [[
  You are a coding assistant helping a user edit code in Neovim.
  All of your responses should consist of only the code you want to write. Do not include any explanations or summaries. Do not include code block markdown starting with ```.
  Match the current indentation of the code snippet in your response.

  You are given:
  1. Context - Code surrounding the snippet (above and below).
  2. Snippet - The specific block of code the user wants to edit in place in the buffer. If the snippet is empty, your generated code will be inserted here and should not contain code from the surrounding context.
  3. Instructions - User provided instructions for editing the snippet.

  Your job is to rewrite the snippet following the users instructions. Your response will replace the snippet within the wider context.
]]

local chat_system_prompt = [[
  You are a coding assistant helping a software developer edit code in their IDE.
  You are provided a chat transcript between "Developer" and "Assistant" (you). The most recent messages are at the bottom.
  Support the developer by answering questions and following instructions. Keep your explanations concise. Do not repeat any code snippet provided.
]]
-- luacheck: pop

---@class OpenAiProvider: AiProvider
local M = {}

M.name = "OpenAI"
M.endpoint = "https://api.openai.com/v1/chat/completions"
M.api_key_env_var = "OPENAI_API_KEY"

---@return string
function M.get_api_key()
  return os.getenv(M.api_key_env_var) or ""
end

---@param body OpenAIStreamingResponse | OpenAIResponse | OpenAIError
---@return boolean
function M.is_error(body)
  return body.error ~= nil
end

---@param body OpenAIStreamingResponse | OpenAIError
---@return boolean
function M.is_streaming_finished(body)
  local completion = body.choices[1]

  if not completion.finish_reason or completion.finish_reason == vim.NIL then
    return false
  end

  return true
end

---@param body OpenAIError
---@return string
function M.get_error_message(body)
  if M.is_error(body) then
    return body.error.message
  end

  return ""
end

---@param body OpenAIStreamingResponse | OpenAIResponse
---@return string
function M.get_text(body)
  local completion = body.choices[1]

  if completion.delta then -- streaming response
    if not completion.finish_reason or completion.finish_reason == vim.NIL then
      return completion.delta.content
    end
  elseif completion.message then -- regular response
    return completion.message.content
  end

  return ""
end

---@return string[]
function M.build_headers()
  return { "-H", "Authorization: Bearer " .. M.get_api_key() }
end

---@param feature string
---@return string
function M._get_system_prompt(feature)
  local system_prompt = ""
  if feature == "chat" then
    system_prompt = chat_system_prompt
  elseif feature == "edit" then
    system_prompt = edit_system_prompt
  end
  return system_prompt
end

---@param prompt string | AiMessages
---@param opts CompletionOptions
---@return OpenAIRequest
function M.build_request(prompt, opts)
  local messages = type(prompt) == "string"
      and {
        { role = "system", content = M._get_system_prompt(opts.feature) },
        { role = "user", content = prompt },
      }
    or prompt

  local request = {
    model = opts.model,
    stream = opts.stream,
    messages = messages,
  }

  if opts.json then
    request.response_format = { type = "json_object" }
  end

  -- OpenAI reasoning models do not accept max_tokens or temperature
  local reasoning_models = { "o1", "o3-mini" }
  if not vim.tbl_contains(reasoning_models, opts.model) then
    request.max_tokens = opts.tokens
    request.temperature = opts.temperature
  end

  return request
end

return M
