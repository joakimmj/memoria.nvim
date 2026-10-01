-- Frontmatter fields: the configured ones, and reading and writing a value.
local M = {}

local md_drafting = require("memoria.lib.md-drafting")

--- Configured field names, of one kind when given, sorted.
---@param fields table<string, memoria.FrontmatterField> Frontmatter config
---@param kind? "concept"|"value"
---@return string[] names
function M.field_names(fields, kind)
  local names = {}
  for name, field in pairs(fields) do
    if not kind or field.kind == kind then
      table.insert(names, name)
    end
  end
  -- Lua tables have no key order; sorting keeps output stable.
  table.sort(names)
  return names
end

--- A frontmatter value as a list: nil and "" are empty, a scalar is one item.
---@param value any Frontmatter field value
---@return string[]
function M.as_list(value)
  if type(value) == "table" then
    return vim.tbl_filter(function(item)
      return type(item) == "string"
    end, value)
  elseif type(value) == "string" and value ~= "" then
    return { value }
  end
  return {}
end

--- The value a field is written with: a list, or for `list = false` the value
--- itself, and "" when there is none.
---@param field memoria.FrontmatterField
---@param values string[]
---@return string|string[]? value Nil when a single-value field is given more
---@return string? err
function M.value_of(field, values)
  if field.list ~= false then
    return values
  elseif #values > 1 then
    return nil, "takes one value"
  end
  return values[1] or ""
end

--- One frontmatter line. A field holding one value is written as one, not as
--- a list of one; with nothing in it the key stands alone, which reads back as
--- empty.
---@param name string Field name
---@param field memoria.FrontmatterField
---@param values string[]
---@return string? line
---@return string? err
function M.format_field(name, field, values)
  local value, err = M.value_of(field, values)
  if value == nil then
    return nil, ("field '%s' %s"):format(name, err)
  elseif value == "" then
    return name .. ":"
  end
  return ("%s: %s"):format(name, md_drafting.syntax.format_frontmatter_value(value))
end

--- Rewrite one field in an engram's frontmatter, every other line kept, the
--- same way `format_field` writes it in a new header: an empty single value
--- is the bare key, which YAML reads as no value.
---@param lines string[] Engram lines
---@param name string Field name
---@param field memoria.FrontmatterField
---@param values string[]
---@return string[]? lines Nil when md-drafting cannot rewrite the field whole
---@return string? err
function M.set_field(lines, name, field, values)
  local value, err = M.value_of(field, values)
  if value == nil then
    return nil, ("field '%s' %s"):format(name, err)
  end
  return md_drafting.syntax.set_frontmatter_field(lines, name, value == "" and vim.NIL or value)
end

return M
