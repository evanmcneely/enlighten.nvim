local M = {}

--- Print out a concise overview of our diff highlights in the buffer
function M.hl()
  local namespaces = vim.api.nvim_get_namespaces()
  local ns_id = namespaces["EnlightenDiffHighlights"]
  if not ns_id then
    print("No namespace id for highlight group")
    return
  end

  local extmarks = vim.api.nvim_buf_get_extmarks(0, ns_id, 0, -1, { details = true })

  if not extmarks then
    print("No highlights in buffer")
    return
  end

  for _, extmark in ipairs(extmarks) do
    local id = extmark[1]
    local start_line = extmark[2]
    local end_line = extmark[4].end_row or start_line
    local hl_group = extmark[4].hl_group
    local virt_lines = extmark[4].virt_lines

    if virt_lines then
      print(
        string.format(
          "Mark ID: %d, Start Line: %d, Highlight Group: EnlightenDiffDelete",
          id,
          start_line,
          hl_group or "None"
        )
      )
    else
      print(
        string.format(
          "Mark ID: %d, Start Line: %d, End Line: %d, Highlight Group: %s",
          id,
          start_line,
          end_line,
          hl_group or "None"
        )
      )
    end
  end
end

--- Print out raw extmark details for our diff highlight group
function M.hl_extmarks()
  local namespaces = vim.api.nvim_get_namespaces()
  local ns_id = namespaces["EnlightenDiffHighlights"]
  if not ns_id then
    print("No highlights in buffer")
    return
  end

  local extmarks = vim.api.nvim_buf_get_extmarks(0, ns_id, 0, -1, { details = true })
  print(vim.inspect(extmarks))
end


return M
