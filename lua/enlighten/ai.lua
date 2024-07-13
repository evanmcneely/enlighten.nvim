local M = {}

local config = require("enlighten/config")

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

local system_prompt = [[
      Your are a coding assistant helping an software developer edit code in there IDE.
      All of you responses should consist of only the code you want to write. Do not include any
      explanations or summarys. Do not include code block markdown starting with ```.
]]

---@param cmd string
---@param args string[]
---@param on_stdout_chunk fun(chunk: string): nil
---@param on_complete fun(err: string?, output: string?): nil
local function exec(cmd, args, on_stdout_chunk, on_complete)
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

---@param endpoint string
---@param body OpenAIRequest
---@param writer Writer
local function request(endpoint, body, writer)
	local api_key = os.getenv("OPENAI_API_KEY")
	if not api_key then
		writer:on_complete("$OPENAI_API_KEY environment variable must be set")
		return
	end

	local curl_args = {
		"--silent",
		"--show-error",
		"--no-buffer",
		"--max-time",
		config.timeout,
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

	local buffered_chunks = ""
	local function on_stdout_chunk(chunk)
		buffered_chunks = buffered_chunks .. chunk

		-- Extract complete JSON objects from the buffered_chunks
		local json_start, json_end = buffered_chunks:find("}\n")
		while json_start do
			local json_str = buffered_chunks:sub(1, json_end)
			buffered_chunks = buffered_chunks:sub(json_end + 1)

			-- Remove the "data: " prefix
			json_str = json_str:gsub("data: ", "")

			---@type OpenAIStreamingResponse | OpenAIError
			local json = vim.json.decode(json_str)
			if json.error then
				writer:on_complete(json.error.message)
			else
				---@diagnostic disable-next-line: param-type-mismatch
				writer:on_data(json)
			end

			json_start, json_end = buffered_chunks:find("}\n")
		end
	end

	exec("curl", curl_args, on_stdout_chunk, function(err)
		writer:on_complete(err)
	end)
end

---@param prompt string
function M.complete(prompt, writer)
	local body = {
		model = config.completions_model,
		max_tokens = config.tokens,
		temperature = config.temperature,
		stream = true,
		messages = {
			{ role = "system", content = system_prompt },
			{
				role = "user",
				content = "Write the code for these instructions: " .. prompt,
			},
		},
	}
	request("chat/completions", body, writer)
end

return M