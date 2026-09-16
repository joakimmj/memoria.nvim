local M = {}

--- md-drafting's api table, looked up on use.
---@return table? api Nil when md-drafting is missing or predates `api`
local function api()
  local ok, md_drafting = pcall(require, "md-drafting")
  if ok and type(md_drafting) == "table" then
    return md_drafting.api
  end
end

--- A function that calls md-drafting's `api[group][name]` when invoked.
---@param group string e.g. "syntax"
---@param name string e.g. "format_link"
---@return function
local function wrap(group, name)
  return function(...)
    return api()[group][name](...)
  end
end

--- Whether md-drafting is installed with its api table.
---@return boolean
function M.available()
  return api() ~= nil
end

M.syntax = {
  ---@type fun(text: string, path: string): string
  format_link = wrap("syntax", "format_link"),

  ---@type fun(prefix: string, marker: string?, text: string): string
  format_list_item = wrap("syntax", "format_list_item"),

  ---@type fun(lines: string[]): table<string, string|table>?, integer?
  parse_frontmatter = wrap("syntax", "parse_frontmatter"),
}

M.section = {
  ---@type fun(lines: string[], name: string, body: string[], opts: { at?: integer }?): string[]
  set = wrap("section", "set"),
}

return M
