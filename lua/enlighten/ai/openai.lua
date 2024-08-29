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
---@field get_text fun(body: table): string
--- A function to get the error message out of the response body (assuming it is an error repsonse).
---@field get_error_message fun(body: table): string
--- A function to build the curl header flags we need to send to the endpoint (usually auth or API version headers).
--- The response is passed straight to curl as command line arguments.
---@field build_headers fun(): string[]
---A function to build a streaming request body to send to the API.
---@field build_request fun(prompt: string|AiMessages, config: EnlightenAiProviderConfig): table

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
local edit_system_prompt = [[
  You are a coding assistant helping a user edit code in Neovim.
  All of your responses should consist of only the code you want to write. Do not include any explanations or summarys. Do not include code block markdown starting with ```.
  Match the current indentation of the code snippet in your response.

  You are given:
  1. Context - Code surrounding the snippet (above and below) as well as the snippet to edit.
  2. Snippet - The specific block of code the user wants to edit in place in the buffer. Marked with "--> snippet start <--" and "--> snippet end <--"
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
function M.get_error_message(body)
  if M.is_error(body) then
    return body.error.message
  end

  return ""
end

---@param body OpenAIStreamingResponse
---@return string
function M.get_text(body)
  local completion = body.choices[1]

  if not completion.finish_reason or completion.finish_reason == vim.NIL then
    return completion.delta.content
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

  return {
    model = opts.model,
    max_tokens = opts.tokens,
    temperature = opts.temperature,
    stream = opts.stream,
    messages = messages,
  }
end

return M
