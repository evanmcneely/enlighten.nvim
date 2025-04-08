local api = vim.api

---@class cmp_source
---@field commands EnlightenMention[]
---@field buffer integer
local cmp_source = {}
cmp_source.__index = cmp_source

---@param commands EnlightenMention[]
---@param buffer integer
function cmp_source.new(commands, buffer)
  local instance = setmetatable({}, cmp_source)

  instance.commands = commands
  instance.buffer = buffer

  return instance
end

function cmp_source:is_available()
  return api.nvim_get_current_buf() == self.buffer
end

function cmp_source.get_position_encoding_kind()
  return "utf-8"
end

function cmp_source.get_trigger_characters()
  return { "@" }
end

function cmp_source.get_keyword_pattern()
  return [[\%(@\|#\|/\)\k*]]
end

---@param completion {detail: string, kind: string, label: string}
---@param callback fun()
function cmp_source:execute(completion, callback)
  ---@type string
  local label = completion.label:match("^@(%S+)") -- Extract mention command without '@' and space

  -- Find the corresponding command
  local selected_mention
  for _, mention in ipairs(self.commands) do
    if mention.command == label then
      selected_mention = mention
      break
    end
  end

  -- Execute the commands's callback if it exists
  if selected_mention and type(selected_mention.callback) == "function" then
    selected_mention.callback(selected_mention)
  end

  callback()
end

function cmp_source:complete(_, callback)
  local kind = require("cmp").lsp.CompletionItemKind.Keyword

  local items = {}

  for _, command in ipairs(self.commands) do
    table.insert(items, {
      label = "@" .. command.command,
      kind = kind,
      detail = command.details,
    })
  end

  callback({
    items = items,
    isIncomplete = false,
  })
end

return cmp_source
