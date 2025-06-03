local M = {}

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
  if filepath:sub(-2) == M.path_separator() .. "." then
    filepath = filepath:sub(1, -3)
  end
  if base_dir:sub(-2) == M.path_separator() .. "." then
    base_dir = base_dir:sub(1, -3)
  end

  if filepath == base_dir then
    return "."
  end

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
  if not path then
    return false
  end
  if M.is_win() then
    return path:match("^%a:[/\\]") ~= nil
  end
  return path:match("^/") ~= nil
end

local _is_win = nil
---@return boolean
function M.is_win()
  if _is_win == nil then
    _is_win = jit.os:find("Windows") ~= nil
  end
  return _is_win
end

---@param ... string
---@return string
function M.join_paths(...)
  local paths = { ... }
  local result = paths[1] or ""

  for i = 2, #paths do
    local path = paths[i]

    -- Skip the junk
    if path ~= nil and path ~= "" then
      -- If path is absolute, it becomes the new base path
      if M.is_absolute_path(path) then
        result = path
      else
        -- Remove leading "./" if present
        if path:sub(1, 2) == "." .. M.path_separator() then
          path = path:sub(3)
        end

        -- Add separator if needed
        if result ~= "" and result:sub(-1) ~= M.path_separator() then
          result = result .. M.path_separator()
        end

        result = result .. path
      end
    end
  end

  return result
end

function M.get_project_root()
  -- Try to find the project root using common methods
  local methods = {
    -- Try finding git directory
    function()
      local git_dir = vim.fn.finddir(".git", ".;")
      if git_dir ~= "" then
        return vim.fn.fnamemodify(git_dir, ":h")
      end
      return nil
    end,

    -- Try finding common project files
    function()
      for _, file in ipairs({
        ".gitignore", -- Git
        "Cargo.toml", -- Rust
        "package.json", -- Node
        "go.mod", -- Go
        "Makefile", -- Make
        "CMakeLists.txt", -- CMake
        "pyproject.toml",
        "setup.py", -- Python
        "composer.json", -- PHP
      }) do
        local found = vim.fn.findfile(file, ".;")
        if found ~= "" then
          return vim.fn.fnamemodify(found, ":h")
        end
      end
      return nil
    end,

    -- Fallback to cwd
    function()
      return vim.uv.cwd()
    end,
  }

  -- Try each method in order
  for _, method in ipairs(methods) do
    local result = method()
    if result then
      return result
    end
  end

  -- Final fallback
  return vim.uv.cwd()
end

---@param path string
---@return string
function M.uniform_path(path)
  -- If the path is not within the current working directory, return it as is
  if not M.is_in_cwd(path) then
    return path
  end

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
