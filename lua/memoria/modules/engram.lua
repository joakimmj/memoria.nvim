-- Creating engrams: filename, generated header, prose template.
local M = {}

local atlas = require("memoria.modules.atlas")
local brain = require("memoria.modules.brain")
local concept = require("memoria.modules.concept")
local concept_lib = require("memoria.lib.concept")
local config = require("memoria.config")
local date = require("memoria.lib.date")
local frontmatter = require("memoria.lib.frontmatter")
local slug = require("memoria.lib.slug")
local synapse = require("memoria.lib.synapse")

---@class memoria.CreateEngramOpts
---@field title? string Title as typed; the filename uses its slug
---@field fields? table<string, string|string[]> Values by frontmatter field name
---@field body? string Prose put where %cursor% is
---@field concept? string Concept the filename is prefixed with, and which is written into its field
---@field concept_field? string Which concept field it goes in, when more than one takes its type

---@class memoria.NewEngram
---@field path string Absolute path of the new engram
---@field cursor integer[] { row, col } where writing starts

---@alias memoria.CreateEngramCode
---| "empty_slug" # The title leaves nothing a filename can use
---| "collision" # That filename is already taken
---| "prefix" # The configured filename prefix is not supported
---| "concept" # The configured prefix needs a concept, and none was chosen
---| "concept_field" # No field takes the concept's type, or more than one does

---@class memoria.FilenameOpts
---@field time? integer Epoch seconds, default now
---@field concept? string Concept key the "concept" prefix uses, as it is

---@class memoria.TemplateVars
---@field title string Title as typed
---@field date string Today, per engrams.date_format

---@class memoria.HeaderOpts
---@field vars? memoria.TemplateVars What a value field's default expands with
---@field registry? memoria.ConceptRegistry What concept values resolve against

--- Filename for a slug under the configured prefix, joined with "_", the
--- character the slug is made of.
---@param cfg memoria.Config Brain config
---@param name string Slug of the title
---@param opts? memoria.FilenameOpts
---@return string? filename Nil when the prefix cannot be used
---@return string? err Why not
---@return memoria.CreateEngramCode? code What kind of failure
function M.filename(cfg, name, opts)
  opts = opts or {}
  local filename = cfg.engrams.filename
  local prefix = filename.prefix or "none"

  if prefix == "date" then
    return date.format(filename.date_format, opts.time) .. "_" .. name .. ".md"
  elseif prefix == "none" then
    return name .. ".md"
  elseif prefix == "concept" then
    if not opts.concept or opts.concept == "" then
      return nil, "a concept is required", "concept"
    end
    -- A key is a slug already.
    return opts.concept .. "_" .. name .. ".md"
  end
  return nil, ("filename prefix '%s' is not supported"):format(prefix), "prefix"
end

--- Expand %title% and %date% in a text.
---@param text string
---@param vars memoria.TemplateVars
---@return string
function M.render_placeholders(text, vars)
  -- Function replacements, so "%" in a value is not a pattern escape.
  return (
    text
      :gsub("%%title%%", function()
        return vars.title
      end)
      :gsub("%%date%%", function()
        return vars.date
      end)
  )
end

--- A field's given values as a list of strings.
---@param name string Field name
---@param given any
---@return string[]? values
---@return string? err
local function given_list(name, given)
  if type(given) == "string" then
    return { given }
  elseif given ~= nil and (type(given) ~= "table" or not vim.islist(given)) then
    return nil, ("field '%s' takes strings"):format(name)
  end
  for _, value in ipairs(given or {}) do
    if type(value) ~= "string" then
      return nil, ("field '%s' takes strings"):format(name)
    end
  end
  return given or {}
end

--- Frontmatter and SYNAPSES block, straight from config. A value field holds
--- what `fields` gives it, else its default expanded, else nothing; a concept
--- field holds what `fields` gives it, each concept written in the field's form
--- and of a type the field takes. Each part is left out when it has no fields.
---@param cfg memoria.Config Brain config
---@param fields? table<string, string|string[]> Values by frontmatter field name
---@param opts? memoria.HeaderOpts
---@return string[]? lines
---@return string? err Why a field was refused
function M.header(cfg, fields, opts)
  fields = fields or {}
  opts = opts or {}
  local vars = opts.vars or { title = "", date = date.format(cfg.engrams.date_format) }
  local registry = opts.registry or {}

  for name in pairs(fields) do
    if not cfg.frontmatter[name] then
      return nil, ("no frontmatter field '%s'"):format(name)
    end
  end

  local lines = {}
  local names = frontmatter.field_names(cfg.frontmatter)
  if #names > 0 then
    table.insert(lines, "---")
    for _, name in ipairs(names) do
      local field = cfg.frontmatter[name]
      local values, err = given_list(name, fields[name])
      if not values then
        return nil, err
      end

      if field.kind == "concept" then
        for _, value in ipairs(values) do
          local key = concept_lib.resolve(registry, value)
          local concept_type = key and registry[key].type or nil
          if not concept_lib.accepts(cfg, name, concept_type) then
            return nil, ("%s is a %s, %s takes %s"):format(key, concept_type, name, field.concept_type)
          end
        end
        values = concept_lib.canonical_list(registry, concept_lib.form(cfg, name), values)
      elseif fields[name] == nil and type(field.default) == "string" then
        values = { M.render_placeholders(field.default, vars) }
      end

      local line, line_err = frontmatter.format_field(name, field, values)
      if not line then
        return nil, line_err
      end
      table.insert(lines, line)
    end
    table.insert(lines, "---")
  end

  -- The frontmatter is ours and always readable, so this cannot fail.
  local written = synapse.write_synapse_block(lines, { synapses = {} }, cfg.synapses) --[[@as string[] ]]
  return written
end

--- Header and prose as one file, and where the cursor lands in it. A blank
--- line separates the two, but only when there is a header to separate.
---@param header string[] Generated header, possibly empty
---@param prose string[] Rendered template
---@param cursor integer[] { row, col } within `prose`
---@return string[] lines
---@return integer[] cursor { row, col } within `lines`
function M.compose(header, prose, cursor)
  local lines = vim.deepcopy(header)
  if #lines > 0 then
    table.insert(lines, "")
  end

  local offset = #lines
  vim.list_extend(lines, prose)
  return lines, { offset + cursor[1], cursor[2] }
end

--- Expand a content template.
---@param template string With %title%, %date%, %cursor%
---@param vars memoria.TemplateVars
---@return string[] lines Rendered, %cursor% stripped
---@return integer[] cursor { row, col }: 1-indexed row, 0-indexed col
function M.render_template(template, vars)
  local text = M.render_placeholders(template, vars)

  local lines, cursor
  local at = text:find("%cursor%", 1, true)
  if at then
    local before = text:sub(1, at - 1)
    local row = select(2, before:gsub("\n", "")) + 1
    local col = #before - (before:match(".*\n()") or 1) + 1
    lines = vim.split(before .. text:sub(at + #"%cursor%"), "\n", { plain = true })
    cursor = { row, col }
  else
    lines = vim.split(text, "\n", { plain = true })
    cursor = { #lines, #lines[#lines] }
  end

  return lines, cursor
end

--- Put `body` where the cursor would land, so the template still frames it,
--- and move the cursor past it.
---@param prose string[] Rendered template
---@param cursor integer[] { row, col } within `prose`
---@param body string Body text, newlines splitting lines
---@return string[] lines
---@return integer[] cursor { row, col } after the body
function M.insert_body(prose, cursor, body)
  local lines = vim.deepcopy(prose)
  local row, col = cursor[1], cursor[2]
  local line = lines[row] or ""
  local before, after = line:sub(1, col), line:sub(col + 1)

  local inserted = vim.split(body, "\n", { plain = true })
  inserted[1] = before .. inserted[1]
  local last = #inserted
  local at = { row + last - 1, #inserted[last] }
  inserted[last] = inserted[last] .. after

  local tail = vim.list_slice(lines, row + 1)
  lines = vim.list_slice(lines, 1, row - 1)
  vim.list_extend(lines, inserted)
  vim.list_extend(lines, tail)
  return lines, at
end

--- Create an engram in a brain. Opening it is the view's, which is why this
--- answers where the cursor goes rather than putting it there.
---@param brain_name? string Default: resolved (see brain.resolve)
---@param opts? memoria.CreateEngramOpts
---@return memoria.NewEngram? new
---@return string? err
---@return memoria.CreateEngramCode? code What kind of failure, when re-asking may help
function M.create_engram(brain_name, opts)
  opts = opts or {}

  local target, err = brain.resolve(brain_name)
  if not target then
    return nil, err
  end

  local cfg = config.load_brain_config(target.location)
  local registry = concept_lib.read(target.location)
  local fields = vim.deepcopy(opts.fields or {})

  -- The prefix concept is resolved before anything is written, so the filename
  -- starts with the registry's key whatever mention was given.
  local prefix
  if cfg.engrams.filename.prefix == "concept" then
    if not opts.concept or vim.trim(opts.concept) == "" then
      return nil, "a concept is required", "concept"
    end

    local resolved, resolve_err = concept.resolve_concept(target.name, vim.trim(opts.concept))
    if not resolved then
      return nil, resolve_err, "concept"
    end
    prefix = resolved.key

    -- Never only cosmetic: a prefix the engram does not also name would be
    -- visible in a listing and invisible to everything that searches.
    local candidates = concept_lib.fields_for(cfg, resolved.type)
    local field = opts.concept_field
    if field then
      if not vim.tbl_contains(candidates, field) then
        return nil, ("%s does not take a %s"):format(field, resolved.type), "concept_field"
      end
    elseif #candidates == 0 then
      return nil, ("no concept field takes a %s"):format(resolved.type), "concept_field"
    elseif #candidates > 1 then
      return nil, ("%s take a %s; name one"):format(table.concat(candidates, ", "), resolved.type), "concept_field"
    else
      field = candidates[1]
    end

    local values = given_list(field, fields[field]) or {}
    table.insert(values, prefix)
    fields[field] = cfg.frontmatter[field].list == false and { prefix } or values
  end

  local _, unsupported, code = M.filename(cfg, "", { concept = prefix })
  if unsupported then
    return nil, unsupported, code
  end

  local title = opts.title and vim.trim(opts.title) or ""
  if title == "" then
    return nil, "a title is required"
  end

  local name = slug.slugify(title)
  if name == "" then
    return nil, "the title needs a letter or digit", "empty_slug"
  end

  local vars = { title = title, date = date.format(cfg.engrams.date_format) }
  local header, header_err = M.header(cfg, fields, { vars = vars, registry = registry })
  if not header then
    return nil, header_err
  end

  local filename = M.filename(cfg, name, { concept = prefix }) --[[@as string]]
  local path = target.location .. "/" .. filename
  if vim.uv.fs_stat(path) then
    return nil, ("engram %s already exists"):format(filename), "collision"
  end

  local prose, cursor = M.render_template(cfg.engrams.content_template, vars)
  if opts.body then
    prose, cursor = M.insert_body(prose, cursor, opts.body)
  end

  local lines, at = M.compose(header, prose, cursor)
  if vim.fn.writefile(lines, path) ~= 0 then
    return nil, "could not write " .. path
  end

  -- The file is written; an atlas that could not be refreshed is rebuildable
  -- by definition, and is not this engram's problem.
  atlas.refresh(target)
  return { path = path, cursor = at }
end

return M
