-- Modified from https://github.com/aduros/ai.vim/blob/main/lua/_ai/openai.lua

local Logger = require("enlighten/logger")

---@class AI
---@field config EnlightenAiConfig
local AI = {}

-- Try's to extract as many complete JSON strings out of the input
-- string and returns them along with whatever junk si left over.
---@param s string
---@return string[], string
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

---@param body table
---@param writer Writer
---@param provider AiProvider
function AI:request(body, writer, provider)
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
    self.config.timeout,
    "-L",
    provider.endpoint,
    "-X",
    "POST",
    "-H",
    "Content-Type: application/json",
    "-d",
    vim.json.encode(body),
  }
  for _, arg in ipairs(provider.build_stream_headers()) do
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
        writer:on_complete(provider.get_error_text(json))
      elseif not provider.is_streaming_finished(json) then
        local text = provider.get_streamed_text(json)
        if #text > 0 then
          writer:on_data(text)
        end
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
  ---@type AiProvider
  local provider = require("enlighten.ai." .. self.config.edit.provider)
  local body = provider.build_stream_request("prompt", prompt, self.config.edit)
  self:request(body, writer, provider)
end

---@param writer Writer
---@param prompt AiMessages
function AI:chat(prompt, writer)
  ---@type AiProvider
  local provider = require("enlighten.ai." .. self.config.chat.provider)
  local body = provider.build_stream_request("chat", prompt, self.config.chat)
  self:request(body, writer, provider)
end

return AI
