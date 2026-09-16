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

--- Regenerate the SYNAPSES block, placing it under the frontmatter if new.
---@param lines string[] Engram lines
---@param engram { synapses: table<string, memoria.SynapseLink[]> } Values by field name
---@param fields table<string, memoria.SynapseField> Synapse config
---@return string[] lines Rewritten lines
function M.write_synapse_block(lines, engram, fields)
  local body = {}

  for _, name in ipairs(M.field_names(fields, "engram")) do
    local values = engram.synapses[name] or {}
    if #values > 0 or fields[name].show_empty ~= false then
      local links = {}
      for _, value in ipairs(values) do
        table.insert(links, md_drafting.syntax.format_link(value.title, value.path))
      end

      local text = ("**%s:**"):format(name)
      if #links > 0 then
        text = text .. " " .. table.concat(links, ", ")
      end
      table.insert(body, md_drafting.syntax.format_list_item("- ", nil, text))
    end
  end
  table.insert(body, "***")

  local _, fm_end = md_drafting.syntax.parse_frontmatter(lines)
  return md_drafting.section.set(lines, "SYNAPSES", body, { at = (fm_end or 0) + 1 })
end

return M
