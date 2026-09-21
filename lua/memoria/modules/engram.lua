-- Creating engrams: filename, generated header, prose template.
local M = {}

local atlas = require("memoria.modules.atlas")
local brain = require("memoria.modules.brain")
local concept = require("memoria.modules.concept")
local config = require("memoria.config")
local date = require("memoria.lib.date")
local md_drafting = require("memoria.lib.md-drafting")
local synapse = require("memoria.lib.synapse")

---@class memoria.CreateEngramOpts
---@field title? string Title as typed; the filename uses its slug
---@field fields? table<string, string|string[]> Values by concept field name
---@field body? string Prose put where %cursor% is
---@field concept? string Concept the filename is prefixed with, and which is written into its field

---@class memoria.NewEngram
---@field path string Absolute path of the new engram
---@field cursor integer[] { row, col } where writing starts

---@alias memoria.CreateEngramCode
---| "empty_slug" # The title leaves nothing a filename can use
---| "collision" # That filename is already taken
---| "prefix" # The configured filename prefix is not supported
---| "concept" # The configured prefix needs a concept, and none was chosen

---@class memoria.FilenameOpts
---@field time? integer Epoch seconds, default now
---@field concept? string Concept the "concept" prefix uses, slugified

--- Filename for a slug under the configured prefix.
---@param cfg memoria.Config Brain config
---@param slug string User-typed slug
---@param opts? memoria.FilenameOpts
---@return string? filename Nil when the prefix cannot be used
---@return string? err Why not
---@return memoria.CreateEngramCode? code What kind of failure
function M.filename(cfg, slug, opts)
  opts = opts or {}
  local filename = cfg.engrams.filename
  local prefix = filename.prefix or "none"

  if prefix == "date" then
    return date.format(cfg.engrams.date_format, opts.time) .. filename.separator .. slug .. ".md"
  elseif prefix == "none" then
    return slug .. ".md"
  elseif prefix == "concept" then
    if not opts.concept or opts.concept == "" then
      return nil, "a concept is required", "concept"
    end
    return M.slugify(opts.concept, filename.separator) .. filename.separator .. slug .. ".md"
  end
  return nil, ("filename prefix '%s' is not supported"):format(prefix), "prefix"
end

-- Characters no filename may hold on common filesystems.
local UNSAFE = '[/\\:*?"<>|]'

--- Filename-safe slug from a title: lowercased, whitespace to `separator`.
---@param title string e.g. "Note about Java"
---@param separator string e.g. "_"
---@return string slug e.g. "note_about_java"; "" when nothing usable is left
function M.slugify(title, separator)
  local sep = vim.pesc(separator)
  local slug = vim.fn.tolower(vim.trim(title)):gsub(UNSAFE, ""):gsub("%s+", separator)

  -- Repeated separators, and separators or dots at either end.
  slug = slug:gsub(sep .. "+", separator)
  local edge = "[%." .. sep .. "]"
  return (slug:gsub("^" .. edge .. "+", ""):gsub(edge .. "+$", ""))
end

--- Frontmatter and SYNAPSES block, straight from config, with `fields`' values
--- in the frontmatter. Each part is left out when it has no fields.
---@param cfg memoria.Config Brain config
---@param fields? table<string, string|string[]> Values by concept field name
---@return string[]? lines
---@return string? err Why a field was refused
function M.header(cfg, fields)
  local lines = {}
  local concept_fields = synapse.field_names(cfg.synapses, "concept")

  for name in pairs(fields or {}) do
    if not vim.tbl_contains(concept_fields, name) then
      return nil, ("no concept field '%s'"):format(name)
    end
  end

  if #concept_fields > 0 then
    table.insert(lines, "---")
    for _, name in ipairs(concept_fields) do
      local values = (fields or {})[name]
      if type(values) == "string" then
        values = { values }
      elseif values ~= nil and not vim.islist(values) then
        return nil, ("field '%s' takes strings"):format(name)
      end

      for _, value in ipairs(values or {}) do
        if type(value) ~= "string" then
          return nil, ("field '%s' takes strings"):format(name)
        end
      end
      table.insert(lines, ("%s: %s"):format(name, md_drafting.syntax.format_frontmatter_value(values or {})))
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
---@param vars { title: string, date: string }
---@return string[] lines Rendered, %cursor% stripped
---@return integer[] cursor { row, col }: 1-indexed row, 0-indexed col
function M.render_template(template, vars)
  -- Function replacements, so "%" in a value is not a pattern escape.
  local text = template
    :gsub("%%title%%", function()
      return vars.title
    end)
    :gsub("%%date%%", function()
      return vars.date
    end)

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
  local fields = vim.deepcopy(opts.fields or {})

  -- The prefix concept is resolved before anything is written, so the name in
  -- the filename is the registry's own spelling rather than an alias.
  local prefix
  if cfg.engrams.filename.prefix == "concept" then
    if not opts.concept or vim.trim(opts.concept) == "" then
      return nil, "a concept is required", "concept"
    end

    local resolved, resolve_err = concept.resolve_concept(target.name, vim.trim(opts.concept))
    if not resolved then
      return nil, resolve_err, "concept"
    end
    prefix = resolved.name

    -- Never only cosmetic: a prefix the engram does not also name would be
    -- visible in a listing and invisible to everything that searches.
    local field = concept.field_for(cfg, resolved.type)
    if field then
      local given = fields[field]
      ---@type string[]
      local values = {}
      if type(given) == "string" then
        values = { given }
      elseif given then
        values = vim.deepcopy(given)
      end

      if not vim.tbl_contains(values, prefix) then
        table.insert(values, prefix)
      end
      fields[field] = cfg.synapses[field].list == false and { prefix } or values
    end
  end

  local _, unsupported, code = M.filename(cfg, "", { concept = prefix })
  if unsupported then
    return nil, unsupported, code
  end

  local title = opts.title and vim.trim(opts.title) or ""
  if title == "" then
    return nil, "a title is required"
  end

  local slug = M.slugify(title, cfg.engrams.filename.separator)
  if slug == "" then
    return nil, "the title needs a letter or digit", "empty_slug"
  end

  local filename = M.filename(cfg, slug, { concept = prefix }) --[[@as string]]
  local path = target.location .. "/" .. filename
  if vim.uv.fs_stat(path) then
    return nil, ("engram %s already exists"):format(filename), "collision"
  end

  local header, header_err = M.header(cfg, fields)
  if not header then
    return nil, header_err
  end

  local prose, cursor = M.render_template(cfg.engrams.content_template, {
    title = title,
    date = date.format(cfg.engrams.date_format),
  })
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
