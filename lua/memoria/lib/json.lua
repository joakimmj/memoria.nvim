-- Reading and writing JSON files.
local M = {}

--- Decode a JSON file.
---@param path string File path
---@return any? value Decoded value, or nil on failure
---@return string? err Why it could not be read
function M.read(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, "unreadable"
  end

  local decoded, value = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not decoded then
    return nil, "invalid JSON"
  end
  return value
end

--- Encode a value to a JSON file, creating its directory.
---@param path string File path
---@param value any Value to encode
---@return boolean ok
---@return string? err Why it could not be written
function M.write(path, value)
  vim.fn.mkdir(vim.fs.dirname(path), "p")

  local ok, result = pcall(vim.fn.writefile, { vim.json.encode(value) }, path)
  if not ok or result ~= 0 then
    return false, "could not write " .. path
  end
  return true
end

return M
