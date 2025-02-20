-- Modified from https://github.com/aduros/ai.vim/blob/main/lua/_ai/openai.lua

local Logger = require("enlighten/logger")

--- The interface that any new AI provider must implement to be integrated as the
--- AI backend for plugin features.
---@class AiProvider
--- The proper name of the AI provider (use proper capitalization).
---@field name string
--- The API endpoint of the chat model for the AI provider
---@field endpoint string
--- The name of the environment variable we expect an API key to saved to.
---@field api_key_env_var string
--- A function to get the API key from the environment.
---@field get_api_key fun(): string
--- A function to interpret a response from the provider API and determine if it is an error.
---@field is_error fun(body: table): boolean
--- A function to interpret a response from the API and determine if streaming is finished.
---@field is_streaming_finished fun(body: table): boolean
--- A function to get the generated text out of the response body (assuming it is a successful response).
---@field get_text fun(body: table): string
--- A function to get the error message out of the response body (assuming it is an error response).
---@field get_error_message fun(body: table): string
--- A function to build the curl header flags we need to send to the endpoint (usually auth or API version headers).
--- The response is passed straight to curl as command line arguments.
---@field build_headers fun(): string[]
---A function to build a streaming request body to send to the API.
---@field build_request fun(prompt: string|AiMessages, config: EnlightenAiProviderConfig): table

---@class CompletionOptions
--- The AI model provider.
---@field provider string
--- The name of the AI model hosted by the provider.
---@field model string
--- Model temperature (only used if the provider API permits).
---@field temperature number
--- Max tokens for generation (only used if the provider API permits).
---@field tokens number
--- Completion timeout in seconds.
---@field timeout number
--- The name of the plugin feature initiating this request (ex. chat).
---@field feature string
--- Whether or not to stream text (for future use).
---@field stream? boolean
--- Whether or not request the response format as JSON (for future use).
---@field json? boolean

---@class PartialCompletionOptions
---@field provider? string
---@field model? string
---@field temperature? number
---@field tokens? number
---@field timeout? number
---@field feature? string
---@field stream? boolean
---@field json? boolean

local M = {}

--- Try's to extract as many complete JSON strings out of the input
--- string and returns them along with whatever junk is left over.
---@param s string
---@return string[], string
--- TODO export function and test
local function extract_json(s)
  local open = 0
  local complete_json_strings = {}
  local json_start = nil
  local in_quotes = false
  local escape = false

  for i = 1, #s do
    local char = s:sub(i, i)
    if not escape then
      if char == '"' then
        in_quotes = not in_quotes -- Flip the in_quotes flag when we see a quote, unless it's escaped
      elseif not in_quotes then
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
    end
    escape = (char == "\\" and not escape) -- Handle escape characters
  end

  -- Handle any remaining part of the string that might be an incomplete JSON string
  local remaining_string = ""
  if json_start then
    remaining_string = s:sub(json_start) -- Unhandled part starts from the last JSON start
  end

  return complete_json_strings, remaining_string
end

---@param cmd string
---@param args string[]
---@param on_stdout_chunk fun(chunk: string): nil
---@param on_complete fun(err: string?, output: string?): nil
function M.exec(cmd, args, on_stdout_chunk, on_complete)
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

  local handle, error

  ---@diagnostic disable-next-line: missing-fields
  handle, error = vim.loop.spawn(cmd, {
    args = args,
    stdio = { nil, stdout, stderr },
  }, function(code)
    if stdout then
      stdout:close()
    end
    if stderr then
      stderr:close()
    end
    if handle then
      handle:close()
    end

    vim.schedule(function()
      if code ~= 0 then
        on_complete(vim.trim(table.concat(stderr_chunks, "")))
      else
        on_complete()
      end
    end)
  end)

  if not handle then
    on_complete("request could not be started: " .. (error or "unknown error"))
    if stdout then
      stdout:close()
    end
    if stderr then
      stderr:close()
    end
    return
  end

  if stdout then
    stdout:read_start(on_stdout_read)
  end
  if stderr then
    stderr:read_start(on_stderr_read)
  end
end

---@param body table
---@param writer Writer
---@param provider AiProvider
---@param opts CompletionOptions
function M.request(body, writer, provider, opts)
  local api_key = provider.get_api_key()
  if not api_key then
    Logger:log("ai:request - no api key")
    writer:on_complete(provider.api_key_env_var .. " environment variable must be set")
    return
  end

  local curl_args = {
    "--silent",
    "--show-error",
    "--no-buffer",
    "--max-time",
    opts.timeout,
    "-L",
    provider.endpoint,
    "-X",
    "POST",
    "-H",
    "Content-Type: application/json",
    "-d",
    vim.json.encode(body),
  }
  for _, arg in ipairs(provider.build_headers()) do
    table.insert(curl_args, arg)
  end

  Logger:log("ai:request - curl_args", curl_args)

  writer:start()

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

      ---@type table
      local json = vim.json.decode(json_str)

      if provider.is_error(json) then
        writer:on_complete(provider.get_error_message(json))
      elseif not provider.is_streaming_finished(json) then
        local text = provider.get_text(json)
        if #text > 0 then
          writer:on_data(text)
        end
      end
    end
  end

  M.exec("curl", curl_args, on_stdout_chunk, function(err)
    writer:on_complete(err)
  end)
end

---@param writer Writer
---@param prompt string | AiMessages
---@param opts CompletionOptions
function M.complete(prompt, writer, opts)
  -- TODO implement streaming false for use in background work / automations
  -- TODO implement JSON format for use in background work / automations
  local defaults = { stream = true, json = false }
  opts = vim.tbl_extend("force", defaults, opts)

  ---@type AiProvider
  local provider
  local success, _ = pcall(function()
    -- TODO how can we allow user written providers for local models
    provider = require("enlighten.ai." .. opts.provider)
  end)

  if not success then
    vim.notify(
      "AI provider " .. opts.provider .. " is unknown. Try something else.",
      vim.log.levels.ERROR
    )
    return
  end

  local body = provider.build_request(prompt, opts)
  M.request(body, writer, provider, opts)
end

return M
