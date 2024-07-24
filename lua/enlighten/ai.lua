local Logger = require("enlighten/logger")

---@class AI
---@field config EnlightenAiConfig
local AI = {}

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
---@field error { message:string }

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

-- Try's to extract as many complete JSON strings out of the input
-- string and returns them along with whatever junk si left over.
---@param s string
---@return string[], string
local function extract_json(s)
  local open = 0
  local complete_json_strings = {}
  local json_start = nil

  for i = 1, #s do
    local char = s:sub(i, i)
    if char == "{" then
      if open == 0 then
        json_start = i -- Mark the start of a JSON string when we see the first '{'
      end
      open = open + 1
    elseif char == "}" then
      open = open - 1
      if open == 0 and json_start then
        local json_string = s:sub(json_start, i)
        table.insert(complete_json_strings, json_string)
        json_start = nil -- Reset the start marker for the next JSON string
      end
    end
  end

  -- Handle any remaining part of the string that might be an incomplete JSON string
  local remaining_string = ""
  if json_start then
    remaining_string = s:sub(json_start) -- Unhandled part starts from the last JSON start
  end

  return complete_json_strings, remaining_string
end

---@param config EnlightenAiConfig
---@return AI
function AI:new(config)
  self.__index = self
  self.config = config
  return self
end

---@param cmd string
---@param args string[]
---@param on_stdout_chunk fun(chunk: string): nil
---@param on_complete fun(err: string?, output: string?): nil
function AI.exec(cmd, args, on_stdout_chunk, on_complete)
  local stdout = vim.loop.new_pipe()
  local function on_stdout_read(_, chunk)
    if chunk then
      vim.schedule(function()
        on_stdout_chunk(chunk)
      end)
    end
  end

  local stderr = vim.loop.new_pipe()
  local stderr_chunks = {}
  local function on_stderr_read(_, chunk)
    if chunk then
      table.insert(stderr_chunks, chunk)
    end
  end

  local handle

  -- luacheck: ignore
  handle, error = vim.loop.spawn(cmd, {
    args = args,
    stdio = { nil, stdout, stderr },
  }, function(code)
    stdout:close()
    stderr:close()
    handle:close()

    vim.schedule(function()
      if code ~= 0 then
        on_complete(vim.trim(table.concat(stderr_chunks, "")))
      else
        on_complete()
      end
    end)
  end)

  if not handle then
    on_complete(cmd .. " could not be started: " .. error)
  else
    stdout:read_start(on_stdout_read)
    stderr:read_start(on_stderr_read)
  end
end

---@param writer Writer
---@param endpoint string
---@param body OpenAIRequest
function AI:request(endpoint, body, writer)
  local api_key = os.getenv("OPENAI_API_KEY")
  if not api_key then
    Logger:log("ai:request - no api key")
    ---@diagnostic disable-next-line: param-type-mismatch
    writer:on_complete("$OPENAI_API_KEY environment variable must be set")
    return
  end

  local curl_args = {
    "--silent",
    "--show-error",
    "--no-buffer",
    "--max-time",
    self.config.timeout,
    "-L",
    "https://api.openai.com/v1/" .. endpoint,
    "-H",
    "Authorization: Bearer " .. api_key,
    "-X",
    "POST",
    "-H",
    "Content-Type: application/json",
    "-d",
    vim.json.encode(body),
  }

  -- Chunks of text to be processed. Can be incomplete JSON strings mixed with "data:" prefixes.
  local buffered_chunks = ""
  -- A queue of JSON object strings to handle. Add to the end and take from the front.
  local processed_chunks = {}

  ---@param chunk string
  local function on_stdout_chunk(chunk)
    -- A chunk here can look like three known things
    --  1. "data: {...} data: [done]" : a single JSON object with data and prefix/suffix
    --  2. "data: {...} data: {...} data: {...} ... data: [done]" : multiple JSON objects with data and prefix/suffix
    --  3. {...} : a single JSON object with no prefix or suffix
    --  4. "data: {.." : an incomplete string of text
    --
    --  To handle incomplete chunks (a rarity) we assemble all the text we have in
    --  buffered_chunks before trying to extract as many complete JSON strings out
    --  of it as we can. Those get processed, leaving the rest for next time.
    buffered_chunks = buffered_chunks .. chunk
    local c, s = extract_json(buffered_chunks)
    buffered_chunks = s

    for _, json_str in ipairs(c) do
      table.insert(processed_chunks, json_str)
    end

    -- Decode and use all JSON objects here until none remain.
    while processed_chunks[1] ~= nil do
      local json_str = table.remove(processed_chunks, 1)

      ---@type OpenAIStreamingResponse | OpenAIError
      local json = vim.json.decode(json_str)

      if json.error then
        writer:on_complete(json.error.message)
      else
        ---@diagnostic disable-next-line: param-type-mismatch
        writer:on_data(json)
      end
    end
  end

  self.exec("curl", curl_args, on_stdout_chunk, function(err)
    writer:on_complete(err)
  end)
end

---@param writer Writer
---@param prompt string
function AI:complete(prompt, writer)
  local body = {
    model = self.config.model,
    max_tokens = self.config.tokens,
    temperature = self.config.temperature,
    stream = true,
    messages = {
      { role = "system", content = prompt_system_prompt },
      {
        role = "user",
        content = prompt,
      },
    },
  }
  Logger:log("ai:complete - request", { body = body })

  self:request("chat/completions", body, writer)
end

---@param writer Writer
---@param prompt string
function AI:chat(prompt, writer)
  local body = {
    model = self.config.model,
    max_tokens = self.config.tokens,
    temperature = self.config.temperature,
    stream = true,
    messages = {
      { role = "system", content = chat_system_prompt },
      {
        role = "user",
        content = prompt,
      },
    },
  }
  Logger:log("ai:chat - request", { body = body })
  self:request("chat/completions", body, writer)
end

return AI
