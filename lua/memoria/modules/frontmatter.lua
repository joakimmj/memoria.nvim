-- Frontmatter values: the plain fields an engram carries beside its concepts.
-- See |memoria-frontmatter|.
local M = {}

local atlas = require("memoria.modules.atlas")
local config = require("memoria.config")
local file = require("memoria.lib.file")
local frontmatter = require("memoria.lib.frontmatter")
local md_drafting = require("memoria.lib.md-drafting")
local synapse_module = require("memoria.modules.synapse")

---@class memoria.EditFrontmatterOpts
---@field source? string Engram path, default: the current buffer's file
---@field field string Value field on the engram
---@field value string What to write; "" clears the field

---@class memoria.EditedFrontmatter
---@field brain string Brain name
---@field source string Engram filename
---@field field string Value field written
---@field value string|string[] What the field holds now

--- Set a value field on an engram: a single-value field takes the value, a
--- list appends it once, and "" clears either. A concept field is refused:
--- attach_concept resolves and type-checks what this would write as given.
---@param opts memoria.EditFrontmatterOpts
---@return memoria.EditedFrontmatter? edited
---@return string? err
function M.edit_frontmatter_field(opts)
  local located, err = synapse_module.locate(opts.source or vim.api.nvim_buf_get_name(0))
  if not located then
    return nil, err
  end
  local target = located.brain

  local cfg = config.load_brain_config(target.location)
  local field = opts.field and cfg.frontmatter[opts.field]
  if not field or field.kind ~= "value" then
    return nil, ("no value field '%s'"):format(opts.field or "")
  end
  if type(opts.value) ~= "string" then
    return nil, "a value is required"
  end

  local path = target.location .. "/" .. located.filename
  local lines = file.read_lines(path)
  if not lines then
    return nil, "cannot read " .. located.filename
  end

  local fields, _, fm_err = md_drafting.syntax.parse_frontmatter(lines)
  if fm_err then
    return nil, ("%s: frontmatter: %s"):format(located.filename, fm_err)
  end

  local text = vim.trim(opts.value)
  local values = frontmatter.as_list(fields and fields[opts.field])
  if text == "" then
    values = {}
  elseif field.list == false then
    values = { text }
  elseif not vim.tbl_contains(values, text) then
    table.insert(values, text)
  end
  local value = frontmatter.value_of(field, values) --[[@as string|string[] ]]

  -- md-drafting refuses a field it cannot rewrite whole rather than leave half
  -- of it behind.
  local written, set_err = frontmatter.set_field(lines, opts.field, field, values)
  if not written then
    return nil, ("%s: %s"):format(located.filename, set_err)
  end
  if not vim.deep_equal(written, lines) then
    local ok, write_err = file.write_lines(path, written)
    if not ok then
      return nil, write_err
    end
  end

  local _, refresh_err = atlas.refresh(target)
  if refresh_err then
    return nil, refresh_err
  end
  return { brain = target.name, source = located.filename, field = opts.field, value = value }
end

return M
