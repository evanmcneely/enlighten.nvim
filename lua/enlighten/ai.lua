local Logger = require("enlighten/logger")
local utils = require("enlighten/utils")

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

	-- A queue of JSON object strings to handle. Add to the end and take from the front.
	local buffered_chunks = {}

	local function on_stdout_chunk(chunk)
		-- A chunk here can look like three known things
		--  1. "data: {...} data: [done]" : a single JSON object with data and prefix/suffix
		--  2. "data: {...} data: {...} data: {...} ... data: [done]" : multiple JSON objects with data and prefix/suffix
		--  3. {...} : a single JSON object with no prefix or suffix
		--
		--  This first case handles chunks that start with "data" and iterates over
		--  all possible JSON objects in the string. The else case assumes the chunk is
		--  valid JSON already.
		if utils.starts_with(chunk, "data:") then
			for json_str in chunk:gmatch("data:%s*(%b{})") do
				table.insert(buffered_chunks, json_str)
			end
		else
			table.insert(buffered_chunks, chunk)
		end

		-- Decode and use all JSON objects here until none remain.
		while buffered_chunks[1] ~= nil do
			local json_str = table.remove(buffered_chunks, 1)

			---@type OpenAIStreamingResponse | OpenAIError
			local json = vim.json.decode(json_str)

			if json.error then
				---@diagnostic disable-next-line: param-type-mismatch
				writer:on_complete(json.error.message)
			else
				---@diagnostic disable-next-line: param-type-mismatch
				writer:on_data(json)
			end
		end
	end

	self.exec("curl", curl_args, on_stdout_chunk, function(err)
		---@diagnostic disable-next-line: param-type-mismatch
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
