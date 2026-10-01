-- Concepts: the persons, tags and topics an engram references without one
-- being a file of its own. See |memoria-concepts|.
local M = {}

local atlas = require("memoria.modules.atlas")
local brain = require("memoria.modules.brain")
local concept = require("memoria.lib.concept")
local config = require("memoria.config")
local frontmatter_module = require("memoria.modules.frontmatter")
local slug = require("memoria.lib.slug")

---@class memoria.Concept
---@field key string Registry key, a slug
---@field display_name string The natural name
---@field type? string What kind of thing it is
---@field aliases string[] Other names it answers to
---@field note? string Free text
---@field meta table<string, string> Free-form values

---@class memoria.CreateConceptOpts
---@field slug? string Key to register it under, instead of the display name's slug

---@class memoria.AttachConceptOpts
---@field source? string Engram path, default: the current buffer's file
---@field field string Concept field on the engram
---@field concept string Any mention of a concept

---@class memoria.AttachedConcept
---@field brain string Brain name
---@field source string Engram filename
---@field field string Concept field written
---@field concept string Text written into it

---@class memoria.UndeclaredConcept
---@field name string The mention, as written in the engrams
---@field count integer How many engrams name it
---@field engrams string[] Those filenames, sorted

--- A stored entry as it is handed out.
---@param key string Registry key
---@param entry memoria.ConceptEntry
---@return memoria.Concept
local function concept_of(key, entry)
  return {
    key = key,
    display_name = concept.display_name(key, entry),
    type = entry.type,
    aliases = entry.aliases or {},
    note = entry.note,
    meta = entry.meta or {},
  }
end

--- The brain a concept function acts in, and its registry.
---@param brain_name? string Default: resolved (see brain.resolve)
---@return memoria.Brain? target
---@return memoria.ConceptRegistry? registry
---@return string? err Why neither could be had
local function registry_of(brain_name)
  local target, err = brain.resolve(brain_name)
  if not target then
    return nil, nil, err
  end

  local registry, read_err = concept.read(target.location)
  if read_err then
    return nil, nil, read_err
  end
  return target, registry
end

--- Refuse a type the brain does not have: one with a schema, or one the
--- registry already uses. A typo would otherwise coin a type.
---@param target memoria.Brain
---@param registry memoria.ConceptRegistry
---@param concept_type string
---@return string? err
local function unknown_type(target, registry, concept_type)
  local known = concept.types(config.load_brain_config(target.location), registry)
  if not vim.tbl_contains(known, concept_type) then
    return ("no concept type '%s'; this brain has %s"):format(
      concept_type,
      #known > 0 and table.concat(known, ", ") or "none"
    )
  end
end

--- Every registered concept, sorted by key.
---@param brain_name? string Default: resolved (see brain.resolve)
---@return memoria.Concept[]? concepts
---@return string? err
function M.list(brain_name)
  local target, registry, err = registry_of(brain_name)
  if not target then
    return nil, err
  end
  ---@cast registry memoria.ConceptRegistry

  local keys = vim.tbl_keys(registry)
  table.sort(keys)

  local concepts = {}
  for _, key in ipairs(keys) do
    table.insert(concepts, concept_of(key, registry[key]))
  end
  return concepts
end

--- A registered concept, by its key.
---@param brain_name? string Default: resolved (see brain.resolve)
---@param key string Registry key
---@return memoria.Concept? found
---@return string? err
function M.get(brain_name, key)
  local target, registry, err = registry_of(brain_name)
  if not target then
    return nil, err
  end
  ---@cast registry memoria.ConceptRegistry

  local entry = registry[key]
  if not entry then
    return nil, ("no concept '%s'"):format(key)
  end
  return concept_of(key, entry)
end

--- The concept a mention names: its key, a text slugifying to it, its display
--- name, or an alias. A mention nothing answers to is undeclared, which is a
--- state to fix rather than a failure.
---@param brain_name? string Default: resolved (see brain.resolve)
---@param mention string As written in an engram
---@return memoria.Concept? found
---@return string? err
function M.resolve_concept(brain_name, mention)
  local target, registry, err = registry_of(brain_name)
  if not target then
    return nil, err
  end
  ---@cast registry memoria.ConceptRegistry

  local key = concept.resolve(registry, mention)
  if not key then
    return nil, ("undeclared concept '%s'"):format(mention)
  end
  return concept_of(key, registry[key])
end

--- Create a concept under the slug of its display name, or the slug given. A
--- key taken, or a display name that already resolves to a concept, is an
--- error: filling one in is what set_concept_meta is for.
---@param brain_name? string Default: resolved (see brain.resolve)
---@param display_name string The natural name
---@param type string What kind of thing it is; one the brain has
---@param fields? table<string, string> Meta values
---@param opts? memoria.CreateConceptOpts
---@return memoria.Concept? added
---@return string? err
function M.create_concept(brain_name, display_name, type, fields, opts)
  opts = opts or {}
  local target, registry, err = registry_of(brain_name)
  if not target then
    return nil, err
  end
  ---@cast registry memoria.ConceptRegistry

  display_name = display_name and vim.trim(display_name) or ""
  if display_name == "" then
    return nil, "a concept name is required"
  end

  local key = slug.slugify(opts.slug and opts.slug ~= "" and opts.slug or display_name)
  if key == "" then
    return nil, ("'%s' needs a letter or digit for its slug"):format(opts.slug or display_name)
  end
  if registry[key] then
    return nil, ("concept '%s' already exists"):format(key)
  end
  local taken = concept.index(registry)[display_name]
  if taken then
    return nil, ("'%s' already names %s"):format(display_name, taken)
  end

  type = type and vim.trim(type) or ""
  if type == "" then
    return nil, ("a type is required for the new concept '%s'"):format(display_name)
  end
  local type_err = unknown_type(target, registry, type)
  if type_err then
    return nil, type_err
  end

  local meta = {}
  for k, value in pairs(fields or {}) do
    meta[k] = value ~= "" and value or nil
  end

  registry[key] = { display_name = display_name, type = type, meta = meta }
  local ok, write_err = concept.write(target.location, registry)
  if not ok then
    return nil, write_err
  end
  return concept_of(key, registry[key])
end

--- Write a registered concept's meta, and its type when given. Values are
--- merged one key at a time, so a key the schema does not name survives; an
--- empty value removes its key.
---@param brain_name? string Default: resolved (see brain.resolve)
---@param key string Registry key
---@param type? string New type; one the brain has
---@param fields? table<string, string> Meta values
---@return memoria.Concept? written
---@return string? err
function M.set_concept_meta(brain_name, key, type, fields)
  local target, registry, err = registry_of(brain_name)
  if not target then
    return nil, err
  end
  ---@cast registry memoria.ConceptRegistry

  local entry = registry[key]
  if not entry then
    return nil, ("no concept '%s'"):format(key or "")
  end

  if type and vim.trim(type) ~= "" then
    local type_err = unknown_type(target, registry, vim.trim(type))
    if type_err then
      return nil, type_err
    end
    entry.type = vim.trim(type)
  end

  entry.meta = entry.meta or {}
  for k, value in pairs(fields or {}) do
    entry.meta[k] = value ~= "" and value or nil
  end

  local ok, write_err = concept.write(target.location, registry)
  if not ok then
    return nil, write_err
  end
  return concept_of(key, entry)
end

--- Have a concept answer to another name as well, so a mention written that
--- way stops being undeclared. The engrams are not touched.
---@param brain_name? string Default: resolved (see brain.resolve)
---@param key string Registry key
---@param alias string Text that should resolve to it
---@return memoria.Concept? written
---@return string? err
function M.add_alias(brain_name, key, alias)
  local target, registry, err = registry_of(brain_name)
  if not target then
    return nil, err
  end
  ---@cast registry memoria.ConceptRegistry

  local entry = registry[key]
  if not entry then
    return nil, ("no concept '%s'"):format(key)
  end
  if not alias or vim.trim(alias) == "" then
    return nil, "an alias is required"
  end

  alias = vim.trim(alias)
  local answers = concept.resolve(registry, alias)
  if answers and answers ~= key then
    return nil, ("'%s' already resolves to %s"):format(alias, answers)
  end

  entry.aliases = entry.aliases or {}
  if not vim.tbl_contains(concept.mentions(key, entry), alias) then
    table.insert(entry.aliases, alias)
    table.sort(entry.aliases)
  end

  local ok, write_err = concept.write(target.location, registry)
  if not ok then
    return nil, write_err
  end
  return concept_of(key, entry)
end

--- A brain's registry, written as `{}` when it has none. What the file may
--- hold is |memoria-concepts|. Opening it is the view's.
---@param brain_name? string Default: resolved (see brain.resolve)
---@return string? path
---@return string? err
function M.ensure_registry(brain_name)
  local target, err = brain.resolve(brain_name)
  if not target then
    return nil, err
  end

  local path = concept.path(target.location)
  if vim.fn.filereadable(path) == 0 then
    local ok, write_err = concept.write(target.location, {})
    if not ok then
      return nil, write_err
    end
  end
  return path
end

--- Every mention the registry does not answer to, most-used first. Not gated
--- the way the atlas's report is: this is asked for, rather than volunteered.
---@param brain_name? string Default: resolved (see brain.resolve)
---@return memoria.UndeclaredConcept[]? undeclared
---@return string? err
function M.find_undeclared_concepts(brain_name)
  local target, registry, err = registry_of(brain_name)
  if not target then
    return nil, err
  end
  ---@cast registry memoria.ConceptRegistry

  local current, refresh_err = atlas.refresh(target)
  if not current then
    return nil, refresh_err
  end

  local undeclared = {}
  for mention, engrams in pairs(current.concepts) do
    if not concept.resolve(registry, mention) then
      table.insert(undeclared, { name = mention, count = #engrams, engrams = vim.deepcopy(engrams) })
    end
  end

  table.sort(undeclared, function(a, b)
    return a.count == b.count and a.name < b.name or a.count > b.count
  end)
  return undeclared
end

--- Put a concept in one of an engram's concept fields, written the way the
--- field writes concepts (its `concept_form`). A mention the registry does not
--- answer to is written as given, the way a hand-typed tag would be. A concept
--- already there changes nothing, and a field with `list = false` gives up the
--- value it held.
---@param opts memoria.AttachConceptOpts
---@return memoria.AttachedConcept? attached What was written
---@return string? err
function M.attach_concept(opts)
  local mention = opts.concept and vim.trim(opts.concept) or ""
  if mention == "" then
    return nil, "a concept is required"
  end

  local text
  local updated, err = frontmatter_module.update_field(opts.source, opts.field, "concept", function(values, target, cfg)
    local registry = concept.read(target.location)
    local written, refused = concept.field_values(cfg, registry, opts.field, { mention })
    if not written then
      return nil, refused
    end
    text = written[1]

    if cfg.frontmatter[opts.field].list == false then
      return { text }
    end

    -- Already there, in any spelling: nothing to add.
    local resolve = concept.resolver(registry)
    local key = resolve(mention)
    for _, value in ipairs(values) do
      if value == text or (key and resolve(value) == key) then
        return values
      end
    end
    table.insert(values, text)
    return values
  end)
  if not updated then
    return nil, err
  end
  return { brain = updated.brain.name, source = updated.source, field = opts.field, concept = text }
end

--- The meta keys a concept of this type is asked for, from config.
---@param cfg memoria.Config Brain config
---@param type? string Concept type
---@return string[] fields
function M.schema_fields(cfg, type)
  local schema = type and cfg.concepts[type]
  return schema and schema.fields or {}
end

--- The meta keys no schema names, sorted: written all the same, worth saying.
---@param cfg memoria.Config Brain config
---@param type? string Concept type
---@param fields table<string, string> Meta values
---@return string[] unknown
function M.unknown_fields(cfg, type, fields)
  local known = M.schema_fields(cfg, type)
  local unknown = {}
  for key in pairs(fields) do
    if not vim.tbl_contains(known, key) then
      table.insert(unknown, key)
    end
  end
  table.sort(unknown)
  return unknown
end

return M
