---@class AiProvider
---@field name string
---@field api_key_env_var string
---@field is_error fun(body: table): boolean
---@field extract_stream_text fun(body: table): string
---@field get_error_text fun(body: table): string
---@field get_api_key fun(): string
---@field build_stream_request fun(feat: string, prompt: string, config: EnlightenAiProviderConfig): OpenAIRequest

---@class OpenAIStreamingResponse
---@field id string
---@field object string
---@field created number
---@field model string
---@field system_fingerprint string
---@field choices OpenAIStreamingChoice[]

---@class OpenAIStreamingChoice
---@field index number
---@field delta OpenAIDelta
---@field logprobs any
---@field finish_reason any

---@class OpenAIDelta
---@field role string
---@field content string

---@class OpenAIError
---@field error { message: string }

---@class OpenAIRequest
---@field model string
---@field prompt string
---@field max_tokens number
---@field temperature number

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

---@class OpenAiProvider: AiProvider
local M = {}

M.name = "OpenAI"
M.api_key_env_var = "OPENAI_API_KEY"

---@param body OpenAIStreamingResponse | OpenAIError
---@return boolean
function M.is_error(body)
  return body.error ~= nil
end

---@param body OpenAIError
---@return string
function M.get_error_text(body)
  if M.is_error(body) then
    return body.error.message
  end

  return ""
end

---@param body OpenAIStreamingResponse
---@return string
function M.extract_stream_text(body)
  local completion = body.choices[1]

  if not completion.finish_reason or completion.finish_reason == vim.NIL then
    return completion.delta.content
  end

  return ""
end

---@return string
function M.get_api_key()
  return os.getenv(M.api_key_env_var) or ""
end

---@param feat string
---@param prompt string
---@param config EnlightenAiProviderConfig
---@return OpenAIRequest
function M.build_stream_request(feat, prompt, config)
  local system_prompt = ""
  if feat == "chat" then
    system_prompt = chat_system_prompt
  elseif feat == "prompt" then
    system_prompt = prompt_system_prompt
  end

  return {
    model = config.model,
    max_tokens = config.tokens,
    temperature = config.temperature,
    stream = true,
    messages = {
      { role = "system", content = system_prompt },
      {
        role = "user",
        content = prompt,
      },
    },
  }
end

return M
