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

--- Encode a value over several lines, two-space indented, object keys sorted.
--- For a file meant to be read and hand-edited: one key per line is what makes
--- it diffable, and what gives anything pointing at an entry a row to point at.
---@param value any JSON-able value
---@param indent? string Leading whitespace of the lines below the first
---@return string[] lines
function M.encode_pretty(value, indent)
  indent = indent or ""
  local inner = indent .. "  "

  -- An empty table has no shape of its own; vim.json knows which it is.
  if type(value) ~= "table" or next(value) == nil then
    return { vim.json.encode(value) }
  end

  local lines = {}
  local function nest(item)
    local rendered = M.encode_pretty(item, inner)
    rendered[1] = inner .. rendered[1]
    return rendered
  end

  if vim.islist(value) then
    for index, item in ipairs(value) do
      local rendered = nest(item)
      if index < #value then
        rendered[#rendered] = rendered[#rendered] .. ","
      end
      vim.list_extend(lines, rendered)
    end
    table.insert(lines, 1, "[")
    table.insert(lines, indent .. "]")
    return lines
  end

  local keys = vim.tbl_keys(value)
  table.sort(keys)
  for index, key in ipairs(keys) do
    local rendered = nest(value[key])
    rendered[1] = ("%s%s: %s"):format(inner, vim.json.encode(tostring(key)), rendered[1]:gsub("^%s+", ""))
    if index < #keys then
      rendered[#rendered] = rendered[#rendered] .. ","
    end
    vim.list_extend(lines, rendered)
  end
  table.insert(lines, 1, "{")
  table.insert(lines, indent .. "}")
  return lines
end

--- Encode a value to a JSON file, creating its directory.
---@param path string File path
---@param value any Value to encode
---@param opts? { pretty?: boolean } pretty: several lines, for a file meant to be read
---@return boolean ok
---@return string? err Why it could not be written
function M.write(path, value, opts)
  vim.fn.mkdir(vim.fs.dirname(path), "p")

  local lines = (opts or {}).pretty and M.encode_pretty(value) or { vim.json.encode(value) }
  local ok, result = pcall(vim.fn.writefile, lines, path)
  if not ok or result ~= 0 then
    return false, "could not write " .. path
  end
  return true
end

return M
