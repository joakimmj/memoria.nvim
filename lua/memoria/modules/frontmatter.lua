-- Frontmatter fields on an engram: the one way a field is read, changed and
-- written back, and the plain value fields beside its concepts. See
-- |memoria-frontmatter|.
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

---@class memoria.UpdatedField
---@field brain memoria.Brain The engram's brain
---@field source string Engram filename
---@field values string[] What the field holds now

---@alias memoria.FieldEdit fun(values: string[], target: memoria.Brain, cfg: memoria.Config): string[]?, string?

--- Change one frontmatter field of an engram: `edit` gets its values as a list
--- and answers the new ones, or nil and why not. Written only when it changed,
--- through a loaded buffer, then the atlas is refreshed. The engram decides the
--- brain; a field not of `kind` is refused, and so is frontmatter that cannot
--- be read.
---@param source? string Engram path, default: the current buffer's file
---@param name string Field name
---@param kind "concept"|"value"
---@param edit memoria.FieldEdit
---@return memoria.UpdatedField? updated
---@return string? err
function M.update_field(source, name, kind, edit)
  local located, err = synapse_module.locate(source or vim.api.nvim_buf_get_name(0))
  if not located then
    return nil, err
  end
  local target = located.brain

  local cfg = config.load_brain_config(target.location)
  local field = name and cfg.frontmatter[name]
  if not field or field.kind ~= kind then
    return nil, ("no %s field '%s'"):format(kind, name or "")
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

  local values, edit_err = edit(frontmatter.as_list(fields and fields[name]), target, cfg)
  if not values then
    return nil, edit_err
  end

  -- md-drafting refuses a field it cannot rewrite whole (a block scalar, a
  -- nested mapping, a key written twice) rather than leave half of it behind.
  local written, set_err = frontmatter.set_field(lines, name, field, values)
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
  return { brain = target, source = located.filename, values = values }
end

--- Set a value field on an engram: a single-value field takes the value, a
--- list appends it once, and "" clears either. A concept field is refused:
--- attach_concept resolves and type-checks what this would write as given.
---@param opts memoria.EditFrontmatterOpts
---@return memoria.EditedFrontmatter? edited
---@return string? err
function M.edit_frontmatter_field(opts)
  if type(opts.value) ~= "string" then
    return nil, "a value is required"
  end
  local text = vim.trim(opts.value)

  local field
  local updated, err = M.update_field(opts.source, opts.field, "value", function(values, _, cfg)
    field = cfg.frontmatter[opts.field]
    if text == "" then
      return {}
    elseif field.list == false then
      return { text }
    elseif not vim.tbl_contains(values, text) then
      table.insert(values, text)
    end
    return values
  end)
  if not updated then
    return nil, err
  end

  return {
    brain = updated.brain.name,
    source = updated.source,
    field = opts.field,
    value = frontmatter.value_of(field, updated.values) --[[@as string|string[] ]],
  }
end

return M
