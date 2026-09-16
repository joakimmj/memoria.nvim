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
--- With no field line to write, no block is written: lines come back as given.
--- Frontmatter that cannot be read is an error, not a missing frontmatter.
---@param lines string[] Engram lines
---@param engram { synapses: table<string, memoria.SynapseLink[]> } Values by field name
---@param fields table<string, memoria.SynapseField> Synapse config
---@return string[]? lines Rewritten lines, nil when the frontmatter is unreadable
---@return string? err Why the frontmatter could not be read
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

return M
