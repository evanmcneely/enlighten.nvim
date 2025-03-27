local api = vim.api

---@alias EnlightenMentionType "edit"
---@alias EnlightenMentionCB fun(args: string, cb?: fun(args: string): nil): nil

---@class EnlightenMention
---@field description string
---@field command EnlightenMentionType
---@field details string
---@field callback? EnlightenMentionCB


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

function cmp_source.execute(item, _)
  item.commands[1].callback()
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
