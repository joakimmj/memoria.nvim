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

  ---@type fun(line: string, markers: { not_done: string[], done: string[] }?): "not_done"|"done"|nil
  parse_checkbox = wrap("syntax", "parse_checkbox"),

  ---@type fun(lines: string[]): table<string, string|table>?, integer?, string?
  parse_frontmatter = wrap("syntax", "parse_frontmatter"),

  ---@type fun(line: string): integer?, string?
  parse_heading = wrap("syntax", "parse_heading"),

  ---@type fun(content: string): { text: string, path: string, col: integer }[]
  parse_links = wrap("syntax", "parse_links"),

  ---@type fun(line: string): string?, string?, string?
  parse_list_item = wrap("syntax", "parse_list_item"),
}

M.section = {
  ---@type fun(lines: string[], name: string): string[]?
  get = wrap("section", "get"),

  ---@type fun(lines: string[], name: string, body: string[], opts: { at?: integer }?): string[]
  set = wrap("section", "set"),
}

return M
