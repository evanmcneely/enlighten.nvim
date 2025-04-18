local ok_scan, scan = pcall(require, "plenary.scandir")
local file_utils = require("enlighten.file")

local PROMPT_TITLE = "(Enlighten) Add a file"

---@alias FileSelectorHandler fun(path:string, content:string[]): nil

--- @class FilePicker
--- @field id integer
--- @field selected_filepaths string[]
--- @field on_file_selected FileSelectorHandler

--- @class FilePicker
local FilePicker = {}

--- Handles user selection of a directory from the file picker
---@param absolute_path string
---@param project_root string
function FilePicker:process_directory(absolute_path, project_root)
  if not ok_scan then
    return
  end

  -- Remove trailing slash from the directory path
  if absolute_path:sub(-1) == file_utils.path_separator() then
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
      local lines, err = file_utils.read_file_from_buf_or_disk(rel_path)
      if not err then
        self.on_file_selected(rel_path, lines)
      end
    end
  end
end

--- Handles user selection of a file path from the field picker
---@param selected_paths string[] | nil
---@return nil
function FilePicker:handle_path_selection(selected_paths)
  if not selected_paths then
    return
  end

  local project_root = file_utils.get_project_root()

  for _, selected_path in ipairs(selected_paths) do
    local absolute_path
    if selected_path:sub(1, 1) == "/" then
      -- Absolute path
      absolute_path = selected_path
    else
      absolute_path = vim.fn.fnamemodify(file_utils.join_paths(project_root, selected_path), ":p")
    end

    local stat = vim.loop.fs_stat(absolute_path)
    if stat and stat.type == "directory" then
      self:process_directory(absolute_path, project_root)
    else
      local uniform_path = file_utils.uniform_path(selected_path)
      table.insert(self.selected_filepaths, uniform_path)

      -- Call the callback with filepath and content
      local lines, err = file_utils.read_file_from_buf_or_disk(uniform_path)
      if not err then
        self.on_file_selected(uniform_path, lines)
      end
    end
  end
end

--- Gets a list of all file paths in the project.
--- Scans the project root directory and returns a list of relative file paths.
--- Directory paths will have a trailing slash.
---@return string[]
local function get_project_filepaths()
  if not ok_scan then
    return {}
  end

  local project_root = file_utils.get_project_root()
  local files = scan.scan_dir(project_root, {
    hidden = false,
    depth = math.huge,
    add_dirs = true,
    respect_gitignore = true,
  })

  -- Make paths relative to the project root.
  local rel_files = {}
  for _, filepath in ipairs(files) do
    table.insert(rel_files, file_utils.make_relative_path(filepath, project_root))
  end

  -- Append trailing slash to directory names.
  rel_files = vim.tbl_map(function(rel_path)
    local stat = vim.loop.fs_stat(file_utils.join_paths(project_root, rel_path))
    if stat and stat.type == "directory" then
      rel_path = rel_path .. "/"
    end
    return rel_path
  end, rel_files)

  return rel_files
end

function FilePicker:new(id, callback)
  return setmetatable({
    id = id,
    selected_filepaths = {},
    on_file_selected = callback or function() end,
  }, { __index = self })
end

function FilePicker:reset()
  self.selected_filepaths = {}
end

---@param filepath string | nil
function FilePicker:add_selected_file(filepath)
  if not filepath or filepath == "" then
    return
  end

  local project_root = file_utils.get_project_root()
  local absolute_path
  if filepath:sub(1, 1) == "/" then
    absolute_path = filepath
  else
    absolute_path = vim.fn.fnamemodify(file_utils.join_paths(project_root, filepath), ":p")
  end
  local stat = vim.loop.fs_stat(absolute_path)

  if stat and stat.type == "directory" then
    self:process_directory(absolute_path, project_root)
    return
  end
  local uniform_path = file_utils.uniform_path(filepath)

  -- Avoid duplicates
  if not vim.tbl_contains(self.selected_filepaths, uniform_path) then
    table.insert(self.selected_filepaths, uniform_path)

    -- Call the callback with filepath and content
    local lines, err = file_utils.read_file_from_buf_or_disk(uniform_path)
    if not err then
      self.on_file_selected(uniform_path, lines)
    end
  end
end

function FilePicker:open_project_files()
  local function handler(selected_paths)
    self:handle_path_selection(selected_paths)
  end

  local filepaths = self:get_project_filepaths()

  vim.schedule(function()
    self.pick(filepaths, handler)
  end)
end

function FilePicker:get_project_filepaths()
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

function FilePicker.pick(filepaths, handler)
  if #filepaths == 0 then
    vim.notify("No files available for selection", vim.log.levels.WARN)
    return
  end

  vim.ui.select(filepaths, {
    prompt = PROMPT_TITLE,
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
function FilePicker:get_selected_files_contents()
  local contents = {}

  for _, filepath in ipairs(self.selected_filepaths) do
    local lines, error = file_utils.read_file_from_buf_or_disk(filepath)
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

function FilePicker:get_selected_filepaths()
  return vim.deepcopy(self.selected_filepaths)
end

---@param buf number
---@return nil
function FilePicker:add_buffer(buf)
  local filepath = vim.api.nvim_buf_get_name(buf)

  local has_scheme = filepath:find("^%w+://") ~= nil
  if filepath and filepath ~= "" and not has_scheme then
    local root = file_utils.get_project_root()
    local relative_path = file_utils.make_relative_path(filepath, root)
    self:add_selected_file(relative_path)
  end
end

---@return nil
function FilePicker:add_quickfix_files()
  local quickfix_list = vim
    .iter(vim.fn.getqflist({ items = 0 }).items)
    :filter(function(item)
      return item.bufnr ~= 0
    end)
    :totable()

  for _, item in ipairs(quickfix_list) do
    self:add_buffer(item.bufnr)
  end
end

---@return nil
function FilePicker:add_buffer_files()
  local buffers = vim.api.nvim_list_bufs()

  for _, bufnr in ipairs(buffers) do
    -- Skip invalid or unlisted buffers
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
      self:add_buffer(bufnr)
    end
  end
end

--- Opens a picker to select files from .enlighten directories
function FilePicker:open_enlighten_files()
  local files = {}
  local search_paths = {
    -- Current working directory
    vim.fn.getcwd() .. "/.enlighten",

    -- Root directory
    -- TODO Windows??
    vim.fn.expand("$HOME") .. "/.enlighten",
  }

  -- Collect files from all locations
  for _, base_path in ipairs(search_paths) do
    local stat = vim.loop.fs_stat(base_path)

    if stat and stat.type == "directory" and ok_scan then
      local path_files = scan.scan_dir(base_path, {
        hidden = false,
        depth = 1,
        add_dirs = false,
      })

      for _, file_path in ipairs(path_files) do
        table.insert(files, file_utils.make_relative_path(file_path, file_utils.get_project_root()))
      end
    end
  end

  local function handler(selected_paths)
    self:handle_path_selection(selected_paths)
  end

  vim.schedule(function()
    self.pick(files, handler)
  end)
end

return FilePicker
