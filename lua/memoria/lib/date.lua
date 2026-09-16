-- Dates in the `date_format` token syntax.
local M = {}

-- Longest tokens first, so "YYYY" is not read as two "YY".
local TOKENS = {
  { "YYYY", "%Y" },
  { "YY", "%y" },
  { "MM", "%m" },
  { "DD", "%d" },
  { "HH", "%H" },
  { "mm", "%M" },
  { "ss", "%S" },
}

--- Format a time with `date_format` tokens; other text is literal.
---@param format string e.g. "YYYYMMDD"
---@param time? integer Epoch seconds, default now
---@return string
function M.format(format, time)
  local parts = {}
  local i = 1

  while i <= #format do
    local matched = false
    for _, token in ipairs(TOKENS) do
      if format:sub(i, i + #token[1] - 1) == token[1] then
        table.insert(parts, token[2])
        i = i + #token[1]
        matched = true
        break
      end
    end

    if not matched then
      -- Escape "%" so it stays literal for os.date.
      table.insert(parts, (format:sub(i, i):gsub("%%", "%%%%")))
      i = i + 1
    end
  end

  return tostring(os.date(table.concat(parts), time))
end

return M
