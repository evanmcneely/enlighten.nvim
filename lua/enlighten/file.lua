local M = {}

local fn = vim.fn

---@param filepath string
---@return string[] | nil
function M.read_content(filepath)
  local content = fn.readfile(filepath)
  if content then
    return content
  end
  return nil
end

---@param options { directory: string, add_dirs?: boolean, max_depth?: integer }
---@return string[]
function M.scan_directory(options)
  local cmd_supports_max_depth = true
  local cmd = (function()
    if vim.fn.executable("rg") == 1 then
      local cmd = { "rg", "--files", "--color", "never", "--no-require-git" }
      if options.max_depth ~= nil then
        vim.list_extend(cmd, { "--max-depth", options.max_depth })
      end
      table.insert(cmd, options.directory)
      return cmd
    end
    if vim.fn.executable("fd") == 1 then
      local cmd = { "fd", "--type", "f", "--color", "never", "--no-require-git" }
      if options.max_depth ~= nil then
        vim.list_extend(cmd, { "--max-depth", options.max_depth })
      end
      vim.list_extend(cmd, { "--base-directory", options.directory })
      return cmd
    end
    if vim.fn.executable("fdfind") == 1 then
      local cmd = { "fdfind", "--type", "f", "--color", "never", "--no-require-git" }
      if options.max_depth ~= nil then
        vim.list_extend(cmd, { "--max-depth", options.max_depth })
      end
      vim.list_extend(cmd, { "--base-directory", options.directory })
      return cmd
    end
  end)()

  if not cmd then
    if M.path_exists(M.join_paths(options.directory, ".git")) and vim.fn.executable("git") == 1 then
      if vim.fn.has("win32") == 1 then
        cmd = {
          "powershell",
          "-NoProfile",
          "-NonInteractive",
          "-Command",
          string.format(
            "Push-Location '%s'; (git ls-files --exclude-standard), (git ls-files --exclude-standard --others)",
            options.directory:gsub("/", "\\")
          ),
        }
      else
        cmd = {
          "bash",
          "-c",
          string.format("cd %s && git ls-files -co --exclude-standard", options.directory),
        }
      end
      cmd_supports_max_depth = false
    else
      M.error("No search command found")
      return {}
    end
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

function M.get_parent_path(filepath)
  if filepath == nil then error("filepath cannot be nil") end
  if filepath == "" then return "" end
  local is_abs = M.is_absolute_path(filepath)
  if filepath:sub(-1) == M.path_sep then filepath = filepath:sub(1, -2) end
  if filepath == "" then return "" end
  local parts = vim.split(filepath, M.path_sep())
  local parent_parts = vim.list_slice(parts, 1, #parts - 1)
  local res = table.concat(parent_parts, M.path_sep())
  if res == "" then
    if is_abs then return M.path_sep end
    return "."
  end
  return res
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

---@return string
function M.path_sep()
  if M.is_win() then
    return "\\"
  else
    return "/"
  end
end

function M.make_relative_path(filepath, base_dir)
  if filepath:sub(-2) == M.path_sep() .. "." then filepath = filepath:sub(1, -3) end
  if base_dir:sub(-2) == M.path_sep() .. "." then base_dir = base_dir:sub(1, -3) end
  if filepath == base_dir then return "." end
  if filepath:sub(1, #base_dir) == base_dir then
    filepath = filepath:sub(#base_dir + 1)
    if filepath:sub(1, 2) == "." .. M.path_sep() then
      filepath = filepath:sub(3)
    elseif filepath:sub(1, 1) == M.path_sep() then
      filepath = filepath:sub(2)
    end
  end
  return filepath
end

function M.is_absolute_path(path)
  if not path then return false end
  if M.is_win() then return path:match("^%a:[/\\]") ~= nil end
  return path:match("^/") ~= nil
end
local _is_win = nil
function M.is_win()
  if _is_win == nil then _is_win = jit.os:find("Windows") ~= nil end
  return _is_win
end

function M.join_paths(...)
  local paths = { ... }
  local result = paths[1] or ""
  for i = 2, #paths do
    local path = paths[i]
    if path == nil or path == "" then goto continue end

    if M.is_absolute_path(path) then
      result = path
      goto continue
    end

    if path:sub(1, 2) == "." .. M.path_sep() then path = path:sub(3) end

    if result ~= "" and result:sub(-1) ~= M.path_sep() then result = result .. M.path_sep() end
    result = result .. path
    ::continue::
  end
  return result
end

function M.path_exists(path) return vim.loop.fs_stat(path) ~= nil end

function M.get_project_root()
  return vim.uv.cwd()
end

function M.uniform_path(path)
  if type(path) ~= "string" then path = tostring(path) end
  if not M.is_in_cwd(path) then return path end
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
