-- lua/memoria/modules/task.lua

local M = {}

function M.toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local lnum = cursor_pos[1]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]

  local new_line

  -- Toggle [x] to no checkbox
  if line:match("^%s*[%-%*%+]%s+%[x%]") then
    new_line = line:gsub("%s*%[x%]%s*", " ", 1)
  -- Toggle [ ] to [x]
  elseif line:match("^%s*[%-%*%+]%s+%[ %]") then
    new_line = line:gsub("%[ %]", "[x]", 1)
  -- Toggle no checkbox to [ ]
  elseif line:match("^%s*[%-%*%+]%s+") then
    new_line = line:gsub("^(%s*[%-%*%+]%s+)(.*)", "%1[ ] %2", 1)
  else
    vim.api.nvim_err_writeln("Not on a list item.")
    return
  end

  if new_line and new_line ~= line then
    vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { new_line })
  end
end

return M
