local Path = require("plenary.path")
local scan = require("plenary.scandir")
local file_utils = require("enlighten.file")

local PROMPT_TITLE = "(Enlighten) Add a file"

--- @class FilePicker
local FileSelector = {}

--- @class FilePicker
--- @field id integer
--- @field selected_filepaths string[]
--- @field on_file_selected fun(path:string, content:string[]): nil

---@alias FileSelectorHandler fun(self: FilePicker, on_select: fun(filepaths: string[] | nil)): nil

local function has_scheme(path)
  return path:find("^%w+://") ~= nil
end

function FileSelector:process_directory(absolute_path, project_root)
  if absolute_path:sub(-1) == file_utils.path_sep() then
    absolute_path = absolute_path:sub(1, -2)
  end
  local files = scan.scan_dir(absolute_path, {
    hidden = false,
    depth = math.huge,
    add_dirs = false,
    respect_gitignore = true,
  })

  for _, file in ipairs(files) do
    local rel_path = file_utils.make_relative_path(file, project_root)
    if not vim.tbl_contains(self.selected_filepaths, rel_path) then
      table.insert(self.selected_filepaths, rel_path)

      -- Call the callback with filepath and content
      local lines, _ = file_utils.read_file_from_buf_or_disk(rel_path)
      if lines then
        self.on_file_selected(rel_path, lines)
      end
    end
  end
end

---@param selected_paths string[] | nil
---@return nil
function FileSelector:handle_path_selection(selected_paths)
  if not selected_paths then
    return
  end
  local project_root = file_utils.get_project_root()

  for _, selected_path in ipairs(selected_paths) do
    local absolute_path = Path:new(project_root):joinpath(selected_path):absolute()

    local stat = vim.loop.fs_stat(absolute_path)
    if stat and stat.type == "directory" then
      self:process_directory(absolute_path, project_root)
    else
      local uniform_path = file_utils.uniform_path(selected_path)
      table.insert(self.selected_filepaths, uniform_path)

      -- Call the callback with filepath and content
      local lines, _ = file_utils.read_file_from_buf_or_disk(uniform_path)
      if lines then
        self.on_file_selected(uniform_path, lines)
      end
    end
  end
end

local function get_project_filepaths()
  local project_root = file_utils.get_project_root()
  local files = file_utils.scan_directory({ directory = project_root, add_dirs = true })
  files = vim
    .iter(files)
    :map(function(filepath)
      return file_utils.make_relative_path(filepath, project_root)
    end)
    :totable()

  return vim.tbl_map(function(path)
    local rel_path = file_utils.make_relative_path(path, project_root)
    local stat = vim.loop.fs_stat(path)
    if stat and stat.type == "directory" then
      rel_path = rel_path .. "/"
    end
    return rel_path
  end, files)
end

function FileSelector:new(id, callback)
  return setmetatable({
    id = id,
    selected_filepaths = {},
    on_file_selected = callback or function() end,
  }, { __index = self })
end

function FileSelector:reset()
  self.selected_filepaths = {}
end

---@param filepath string | nil
function FileSelector:add_selected_file(filepath)
  if not filepath or filepath == "" then
    return
  end

  local absolute_path = filepath:sub(1, 1) == "/" and filepath
    or Path:new(file_utils.get_project_root()):joinpath(filepath):absolute()
  local stat = vim.loop.fs_stat(absolute_path)

  if stat and stat.type == "directory" then
    self:process_directory(absolute_path, file_utils.get_project_root())
    return
  end
  local uniform_path = file_utils.uniform_path(filepath)

  -- Avoid duplicates
  if not vim.tbl_contains(self.selected_filepaths, uniform_path) then
    table.insert(self.selected_filepaths, uniform_path)

    -- Call the callback with filepath and content
    local lines, _ = file_utils.read_file_from_buf_or_disk(uniform_path)
    if lines then
      self.on_file_selected(uniform_path, lines)
    end
  end
end

function FileSelector:add_current_buffer()
  local current_buf = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(current_buf)

  if filepath and filepath ~= "" and not has_scheme(filepath) then
    local relative_path = file_utils.relative_path(filepath)
    self:add_selected_file(relative_path)
    return true
  end

  return false
end

function FileSelector:open()
  local function handler(selected_paths)
    self:handle_path_selection(selected_paths)
  end

  vim.schedule(function()
    self:native_ui(handler)
  end)
end

function FileSelector:get_filepaths()
  local filepaths = get_project_filepaths()

  table.sort(filepaths, function(a, b)
    local a_stat = vim.loop.fs_stat(a)
    local b_stat = vim.loop.fs_stat(b)
    local a_is_dir = a_stat and a_stat.type == "directory"
    local b_is_dir = b_stat and b_stat.type == "directory"

    if a_is_dir and not b_is_dir then
      return true
    elseif not a_is_dir and b_is_dir then
      return false
    else
      return a < b
    end
  end)

  return vim
    .iter(filepaths)
    :filter(function(filepath)
      return not vim.tbl_contains(self.selected_filepaths, filepath)
    end)
    :totable()
end

function FileSelector:native_ui(handler)
  local filepaths = self:get_filepaths()

  vim.ui.select(filepaths, {
    prompt = string.format("%s:", PROMPT_TITLE),
    format_item = function(item)
      return item
    end,
  }, function(item)
    if item then
      handler({ item })
    else
      handler(nil)
    end
  end)
end

---@return { path: string, content: string, file_type: string }[]
function FileSelector:get_selected_files_contents()
  local contents = {}
  for _, filepath in ipairs(self.selected_filepaths) do
    local lines, error = file_utils.read_file_from_buf_or_disk(filepath)
    lines = lines or {}
    local filetype = file_utils.get_filetype(filepath)
    if error ~= nil then
      vim.notify("Error reading file: " .. error, vim.log.levels.ERROR)
    else
      local content = table.concat(lines, "\n")
      table.insert(contents, { path = filepath, content = content, file_type = filetype })
    end
  end
  return contents
end

function FileSelector:get_selected_filepaths()
  return vim.deepcopy(self.selected_filepaths)
end

---@return nil
function FileSelector:add_quickfix_files()
  local quickfix_files = vim
    .iter(vim.fn.getqflist({ items = 0 }).items)
    :filter(function(item)
      return item.bufnr ~= 0
    end)
    :map(function(item)
      return file_utils.relative_path(vim.api.nvim_buf_get_name(item.bufnr))
    end)
    :totable()
  for _, filepath in ipairs(quickfix_files) do
    self:add_selected_file(filepath)
  end
end

---@return nil
function FileSelector:add_buffer_files()
  local buffers = vim.api.nvim_list_bufs()
  for _, bufnr in ipairs(buffers) do
    -- Skip invalid or unlisted buffers
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
      local filepath = vim.api.nvim_buf_get_name(bufnr)
      -- Skip empty paths and special buffers (like terminals)
      if filepath ~= "" and not has_scheme(filepath) then
        local relative_path = file_utils.relative_path(filepath)
        self:add_selected_file(relative_path)
      end
    end
  end
end

return FileSelector
