-- Reading and writing engram files, through their buffer when one is loaded.
local M = {}

--- The loaded buffer holding a file.
---@param path string Absolute path
---@return integer? bufnr
local function loaded_buffer(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    return bufnr
  end
end

--- A file's lines: its buffer's when loaded, else what is on disk. A buffer
--- is checked against the disk first, so one changed underneath it is reloaded
--- (or asked about, when it has changes of its own) rather than written over.
---@param path string Absolute path
---@return string[]? lines Nil when it cannot be read
function M.read_lines(path)
  local bufnr = loaded_buffer(path)
  if bufnr then
    vim.cmd.checktime(bufnr)
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and lines or nil
end

--- Write lines into a buffer, replacing only the span that differs, so marks
--- outside it stay where they are.
---@param bufnr integer
---@param lines string[] New buffer contents
local function replace_lines(bufnr, lines)
  local old = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local first = 1
  while first <= #old and first <= #lines and old[first] == lines[first] do
    first = first + 1
  end
  if first > #old and first > #lines then
    return
  end

  local old_last, new_last = #old, #lines
  while old_last >= first and new_last >= first and old[old_last] == lines[new_last] do
    old_last = old_last - 1
    new_last = new_last - 1
  end

  vim.api.nvim_buf_set_lines(bufnr, first - 1, old_last, false, vim.list_slice(lines, first, new_last))
end

--- Write a file: through its buffer, saved, when one is loaded, so the buffer
--- does not go stale under it.
---@param path string Absolute path
---@param lines string[] New contents
---@return boolean ok
---@return string? err Why it could not be written
function M.write_lines(path, lines)
  local bufnr = loaded_buffer(path)
  if not bufnr then
    local ok, result = pcall(vim.fn.writefile, lines, path)
    if not ok or result ~= 0 then
      return false, "could not write " .. path
    end
    return true
  end

  replace_lines(bufnr, lines)
  local ok = pcall(vim.api.nvim_buf_call, bufnr, function()
    vim.cmd("silent write")
  end)
  if not ok then
    return false, "could not save " .. path
  end
  return true
end

return M
