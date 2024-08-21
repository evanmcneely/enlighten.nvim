---@class AiProvider
--- The proper name of the ai provider (use proper capitalization).
---@field name string
--- The endpoint of the chat model.
---@field endpoint string
--- The name of the environment variable we expect an API key to saved to.
---@field api_key_env_var string
--- A function to get the API key from the environment.
---@field get_api_key fun(): string
--- A function to interpret a response from the API and determine if it is an error.
---@field is_error fun(body: table): boolean
--- A function to interpret a response from the API and determine if the streaming is finished.
---@field is_streaming_finished fun(body: table): boolean
--- A function to get the generated text out of the response body (assuming it is a successful response).
---@field get_streamed_text fun(body: table): string
--- A function to get the error message out of the response body (assuming it is an error repsonse).
---@field get_error_text fun(body: table): string
--- A function to build the curl header flags we need to send to the endpoint (usually auth or API version headers).
--- The response is passed straight to curl as command line arguments.
---@field build_stream_headers fun(): string[]
---A function to build a streaming request body to send to the API.
---@field build_stream_request fun(feat: string, prompt: string|AiMessages, config: EnlightenAiProviderConfig): table

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

---@class OpenAIMessage
---@field role string
---@field content string

---@class OpenAIRequest
---@field model string
---@field prompt string
---@field max_tokens number
---@field stream? boolean
---@field temperature number
---@field messages OpenAIMessage[]

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
M.endpoint = "https://api.openai.com/v1/chat/completions"
M.api_key_env_var = "OPENAI_API_KEY"

---@return string
function M.get_api_key()
  return os.getenv(M.api_key_env_var) or ""
end

---@param body OpenAIStreamingResponse | OpenAIError
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
function M.get_error_text(body)
  if M.is_error(body) then
    return body.error.message
  end

  return ""
end

---@param body OpenAIStreamingResponse
---@return string
function M.get_streamed_text(body)
  local completion = body.choices[1]

  if not completion.finish_reason or completion.finish_reason == vim.NIL then
    return completion.delta.content
  end

  return ""
end

---@return string[]
function M.build_stream_headers()
  return { "-H", "Authorization: Bearer " .. M.get_api_key() }
end

---@param feature string
---@return string
function M.get_system_prompt(feature)
  local system_prompt = ""
  if feature == "chat" then
    system_prompt = chat_system_prompt
  elseif feature == "edit" then
    system_prompt = prompt_system_prompt
  end
  return system_prompt
end

---@param feat string
---@param prompt string | AiMessages
---@param config EnlightenAiProviderConfig
---@return OpenAIRequest
function M.build_stream_request(feat, prompt, config)
  local messages = type(prompt) == "string"
      and {
        { role = "system", content = M.get_system_prompt(feat) },
        { role = "user", content = prompt },
      }
    or prompt

  return {
    model = config.model,
    max_tokens = config.tokens,
    temperature = config.temperature,
    stream = true,
    messages = messages,
  }
end

return M
