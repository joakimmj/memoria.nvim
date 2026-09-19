-- The SYNAPSES block: engram-to-engram fields between fixed markers.
local M = {}

local md_drafting = require("memoria.lib.md-drafting")

---@class memoria.SynapseLink
---@field title string Link text
---@field path string Link target

--- Configured field names with the given target, sorted.
---@param fields table<string, memoria.SynapseField> Synapse config
---@param target "engram"|"concept"
---@return string[] names
function M.field_names(fields, target)
  local names = {}
  for name, field in pairs(fields) do
    if field.target == target then
      table.insert(names, name)
    end
  end
  -- Lua tables have no key order; sorting keeps output stable.
  table.sort(names)
  return names
end

--- The link a synapse value is written as: the filename's stem as its text.
---@param filename string Engram filename, e.g. "20260801_project-x.md"
---@return memoria.SynapseLink
function M.link(filename)
  return { title = (filename:gsub("%.md$", "")), path = filename }
end

--- Read the SYNAPSES block's fields. Lines that are not a field item are
--- ignored, and a checkbox on a field item is not part of it.
---@param lines string[] Engram lines
---@return table<string, memoria.SynapseLink[]>? synapses Values by field name, nil when there is no block
function M.parse_synapse_block(lines)
  local body = md_drafting.section.get(lines, "SYNAPSES")
  if not body then
    return nil
  end

  local synapses = {}
  for _, line in ipairs(body) do
    local prefix, _, text = md_drafting.syntax.parse_list_item(line)
    local label, content = (prefix and text or ""):match("^%*%*([%w_]+):%*%*%s*(.*)$")
    if label then
      local values = {}
      for _, link in ipairs(md_drafting.syntax.parse_links(content)) do
        table.insert(values, { title = link.text, path = link.path })
      end
      synapses[label] = values
    end
  end
  return synapses
end

--- Regenerate the SYNAPSES block, placing it under the frontmatter if new.
--- Configured engram fields are written per `show_empty`; any other field in
--- `engram.synapses` (one added by hand) is kept as it is. With no field line
--- to write, no block is written: lines come back as given. Frontmatter that
--- cannot be read is an error, not a missing frontmatter.
---@param lines string[] Engram lines
---@param engram { synapses: table<string, memoria.SynapseLink[]> } Values by field name
---@param fields table<string, memoria.SynapseField> Synapse config
---@return string[]? lines Rewritten lines, nil when the frontmatter is unreadable
---@return string? err Why the frontmatter could not be read
function M.write_synapse_block(lines, engram, fields)
  local names = {}
  for _, name in ipairs(M.field_names(fields, "engram")) do
    local values = engram.synapses[name] or {}
    if #values > 0 or fields[name].show_empty ~= false then
      names[name] = true
    end
  end
  for name in pairs(engram.synapses) do
    local field = fields[name]
    if not field or field.target ~= "engram" then
      names[name] = true
    end
  end

  local sorted = vim.tbl_keys(names)
  table.sort(sorted)

  local body = {}
  for _, name in ipairs(sorted) do
    local links = {}
    for _, value in ipairs(engram.synapses[name] or {}) do
      table.insert(links, md_drafting.syntax.format_link(value.title, value.path))
    end

    local text = ("**%s:**"):format(name)
    if #links > 0 then
      text = text .. " " .. table.concat(links, ", ")
    end
    table.insert(body, md_drafting.syntax.format_list_item("- ", nil, text))
  end

  if #body == 0 then
    return lines
  end
  table.insert(body, "***")

  -- A block at row 1 above unreadable frontmatter would push its "---" off
  -- line 1, and it would stop being frontmatter anywhere.
  local _, fm_end, err = md_drafting.syntax.parse_frontmatter(lines)
  if err then
    return nil, "frontmatter: " .. err
  end

  return md_drafting.section.set(lines, "SYNAPSES", body, { at = (fm_end or 0) + 1 })
end

--- Edit the block's values and write it back: parse, `edit`, regenerate.
---@param lines string[] Engram lines
---@param fields table<string, memoria.SynapseField> Synapse config
---@param edit fun(synapses: table<string, memoria.SynapseLink[]>) Changes values in place
---@return string[]? lines Rewritten lines, nil when the frontmatter is unreadable
---@return string? err Why the frontmatter could not be read
function M.update(lines, fields, edit)
  local synapses = M.parse_synapse_block(lines) or {}
  edit(synapses)
  return M.write_synapse_block(lines, { synapses = synapses }, fields)
end

return M
