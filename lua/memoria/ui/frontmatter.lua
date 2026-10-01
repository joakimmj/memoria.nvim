-- Editing a frontmatter value from the editor: pick the field, ask the value.
local M = {}

local config = require("memoria.config")
local frontmatter = require("memoria.modules.frontmatter")
local frontmatter_lib = require("memoria.lib.frontmatter")
local md_drafting = require("memoria.lib.md-drafting")
local message = require("memoria.ui.message")
local synapse = require("memoria.modules.synapse")

--- Set a value field on the current engram, asking for whatever `opts` leaves
--- out: the field, then the value — filled in with the current one for a
--- single-value field. The engram decides the brain.
---@param opts? { source?: string, field?: string, value?: string }
function M.edit_frontmatter_field(opts)
  opts = opts or {}

  local source = opts.source or vim.api.nvim_buf_get_name(0)
  local located, err = synapse.locate(source)
  if not located then
    return message.error(err --[[@as string]])
  end

  local target = located.brain
  local cfg = config.load_brain_config(target.location)

  ---@param field string
  local function ask_value(field)
    local value = opts.value
    if not value then
      local current
      if cfg.frontmatter[field].list == false then
        local lines = vim.fn.readfile(target.location .. "/" .. located.filename)
        local fields = md_drafting.syntax.parse_frontmatter(lines) or {}
        local held = fields[field]
        current = type(held) == "string" and held or nil
      end
      value = message.ask(message.in_brain(target.name, field .. ": "), current)
      if not value then
        return
      end
    end

    local edited, edit_err = frontmatter.edit_frontmatter_field({ source = source, field = field, value = value })
    if not edited then
      return message.error(message.in_brain(target.name, edit_err --[[@as string]]))
    end
    local shown = edited.value
    if type(shown) == "table" then
      shown = table.concat(shown, ", ")
    end
    message.info(message.in_brain(target.name, ("%s %s → %s"):format(edited.source, edited.field, shown)))
  end

  local fields = frontmatter_lib.field_names(cfg.frontmatter, "value")
  if opts.field then
    if not vim.tbl_contains(fields, opts.field) then
      return message.error(message.in_brain(target.name, ("no value field '%s'"):format(opts.field)))
    end
    ask_value(opts.field)
  elseif #fields == 0 then
    message.warn(message.in_brain(target.name, "no value fields configured"))
  elseif #fields == 1 then
    ask_value(fields[1])
  else
    vim.ui.select(fields, { prompt = message.in_brain(target.name, "Frontmatter field:") }, function(choice)
      if choice then
        ask_value(choice)
      end
    end)
  end
end

return M
