local M = {}


---@param options { directory: string, add_dirs?: boolean, max_depth?: integer }
---@return table|nil cmd
---@return boolean cmd_supports_max_depth
function M.get_scan_command(options)
  local cmd_supports_max_depth = true

  if vim.fn.executable("rg") == 1 then
    local cmd = { "rg", "--files", "--color", "never", "--no-require-git" }
    if options.max_depth ~= nil then
      vim.list_extend(cmd, { "--max-depth", options.max_depth })
    end
    table.insert(cmd, options.directory)
    return cmd, cmd_supports_max_depth
  end

  if vim.fn.executable("fd") == 1 then
    local cmd = { "fd", "--type", "f", "--color", "never", "--no-require-git" }
    if options.max_depth ~= nil then
      vim.list_extend(cmd, { "--max-depth", options.max_depth })
    end
    vim.list_extend(cmd, { "--base-directory", options.directory })
    return cmd, cmd_supports_max_depth
  end

  if vim.fn.executable("fdfind") == 1 then
    local cmd = { "fdfind", "--type", "f", "--color", "never", "--no-require-git" }
    if options.max_depth ~= nil then
      vim.list_extend(cmd, { "--max-depth", options.max_depth })
    end
    vim.list_extend(cmd, { "--base-directory", options.directory })
    return cmd, cmd_supports_max_depth
  end

  if M.exists(M.join_paths(options.directory, ".git")) and vim.fn.executable("git") == 1 then
    cmd_supports_max_depth = false
    if vim.fn.has("win32") == 1 then
      return {
        "powershell",
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        string.format(
          "Push-Location '%s'; (git ls-files --exclude-standard), (git ls-files --exclude-standard --others)",
          options.directory:gsub("/", "\\")
        ),
      }, cmd_supports_max_depth
    else
      return {
        "bash",
        "-c",
        string.format("cd %s && git ls-files -co --exclude-standard", options.directory),
      }, cmd_supports_max_depth
    end
  end

  return nil, cmd_supports_max_depth
end


---@param options { directory: string, add_dirs?: boolean, max_depth?: integer }
---@return string[]
function M.scan_directory(options)
  local cmd, cmd_supports_max_depth = M.get_scan_command(options)

  if not cmd then
    M.error("No search command found")
    return {}
  end

  local files = vim.fn.systemlist(cmd)
  files = vim
    .iter(files)
    :map(function(file)
      if not M.is_absolute_path(file) then
        return M.join_paths(options.directory, file)
      end
      return file
    end)
    :totable()

  if options.max_depth ~= nil and not cmd_supports_max_depth then
    files = vim
      .iter(files)
      :filter(function(file)
        local base_dir = options.directory
        if base_dir:sub(-2) == "/." then
          base_dir = base_dir:sub(1, -3)
        end
        local rel_path = M.make_relative_path(file, base_dir)
        local pieces = vim.split(rel_path, "/")
        return #pieces <= options.max_depth
      end)
      :totable()
  end

  if options.add_dirs then
    local dirs = {}
    local dirs_seen = {}
    for _, file in ipairs(files) do
      local dir = M.get_parent_path(file)
      if not dirs_seen[dir] then
        table.insert(dirs, dir)
        dirs_seen[dir] = true
      end
    end
    files = vim.list_extend(dirs, files)
  end

  return files
end

--- Returns the parent directory of the given filepath. If the filepath is a root directory,
--- returns the path separator for absolute paths or "." for relative paths.
--- If filepath is empty, returns an empty string.
---@param filepath string | nil
---@return string
function M.get_parent_path(filepath)
  if filepath == nil then error("filepath cannot be nil") end
  if filepath == "" then return "" end

  local is_abs = M.is_absolute_path(filepath)

  -- If filepath ends with a path separator, remove it before processing
  if filepath:sub(-1) == M.path_separator() then filepath = filepath:sub(1, -2) end
  if filepath == "" then return "" end

  -- Get the parent path by splitting the string, removing the last part, and joining it all together again
  local parts = vim.split(filepath, M.path_separator())
  local parent_parts = vim.list_slice(parts, 1, #parts - 1)
  local parent_path = table.concat(parent_parts, M.path_separator())

  if parent_path == "" then
    if is_abs then return M.path_separator() end
    return "."
  end

  return parent_path
end

---@param filepath string
---@return boolean
function M.exists(filepath)
  local stat = vim.loop.fs_stat(filepath)
  return stat ~= nil
end

---@param filepath string
---@return boolean
function M.is_in_cwd(filepath)
  local cwd = vim.fn.getcwd()

  -- Make both paths absolute for comparison
  local abs_filepath = vim.fn.fnamemodify(filepath, ":p")
  local abs_cwd = vim.fn.fnamemodify(cwd, ":p")

  -- Check if filepath starts with cwd
  return abs_filepath:sub(1, #abs_cwd) == abs_cwd
end

--- Returns the path separator for the os
---@return string
function M.path_separator()
  if M.is_win() then
    return "\\"
  else
    return "/"
  end
end

---@param filepath string
---@param base_dir string
---@return string The
function M.make_relative_path(filepath, base_dir)

  -- Normalize paths by removing trailing '/.' or '\.' if present
  if filepath:sub(-2) == M.path_separator() .. "." then filepath = filepath:sub(1, -3) end
  if base_dir:sub(-2) == M.path_separator() .. "." then base_dir = base_dir:sub(1, -3) end

  if filepath == base_dir then return "." end

  -- If the filepath starts with the base directory, make it relative
  if filepath:sub(1, #base_dir) == base_dir then
    -- Remove the base directory prefix from the filepath
    filepath = filepath:sub(#base_dir + 1)

    -- Handle edge cases in the resulting path:
    -- 1. If it starts with "./" remove that prefix
    -- 2. If it starts with a path separator, remove that too
    if filepath:sub(1, 2) == "." .. M.path_separator() then
      filepath = filepath:sub(3)
    elseif filepath:sub(1, 1) == M.path_separator() then
      filepath = filepath:sub(2)
    end
  end

  return filepath
end

--- Returns whether the provided path is an absolute path by:
--- 1.checking if it starts with a drive letter followed by a colon and a path separator on Windows.
--- 2. checknig if it starts with a forward slash on Unix systems.
---@param path string
---@return boolean
function M.is_absolute_path(path)
  if not path then return false end
  if M.is_win() then return path:match("^%a:[/\\]") ~= nil end
  return path:match("^/") ~= nil
end


local _is_win = nil
---@return boolean
function M.is_win()
  if _is_win == nil then _is_win = jit.os:find("Windows") ~= nil end
  return _is_win
end

---@param ... string
---@return string
function M.join_paths(...)
  local paths = { ... }
  local result = paths[1] or ""

  for i = 2, #paths do
    local path = paths[i]
    if path == nil or path == "" then goto continue end

    -- If path is absolute, it becomes the new base path
    if M.is_absolute_path(path) then
      result = path
      goto continue
    end

    -- Remove leading "./" if present
    if path:sub(1, 2) == "." .. M.path_separator() then path = path:sub(3) end

    -- Add separator if needed
    if result ~= "" and result:sub(-1) ~= M.path_separator() then result = result .. M.path_separator() end
    result = result .. path
    ::continue::
  end

  return result
end

function M.get_project_root()
  -- Treat the cwd as the project root
  -- TODO should correct this later
  return vim.uv.cwd()
end

---@param path string
---@return string
function M.uniform_path(path)
  -- If the path is not within the current working directory, return it as is
  if not M.is_in_cwd(path) then return path end

  -- Convert the path to an absolute path and then back to a relative from the CMD
  local project_root = M.get_project_root()
  local abs_path = M.is_absolute_path(path) and path or M.join_paths(project_root, path)
  local relative_path = M.make_relative_path(abs_path, project_root)

  return relative_path
end

---@param filepath string
---@return string[]|nil lines
---@return string|nil error
function M.read_file_from_buf_or_disk(filepath)
  --- Lookup if the file is loaded in a buffer
  local bufnr = vim.fn.bufnr(filepath)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    -- If buffer exists and is loaded, get buffer content
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return lines, nil
  end

  -- Fallback: read file from disk
  local file, open_err = io.open(filepath, "r")
  if file then
    local content = file:read("*all")
    file:close()
    content = content:gsub("\r\n", "\n")
    return vim.split(content, "\n"), nil
  else
    return {}, open_err
  end
end

return M
