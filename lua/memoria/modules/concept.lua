-- Concepts: the persons, tags and topics an engram references without one
-- being a file of its own. See |memoria-concepts|.
local M = {}

local atlas = require("memoria.modules.atlas")
local brain = require("memoria.modules.brain")
local concept = require("memoria.lib.concept")
local config = require("memoria.config")
local file = require("memoria.lib.file")
local md_drafting = require("memoria.lib.md-drafting")
local synapse = require("memoria.lib.synapse")
local synapse_module = require("memoria.modules.synapse")

---@class memoria.Concept
---@field name string Registry key
---@field type? string What kind of thing it is
---@field aliases string[] Other names it answers to
---@field note? string Free text
---@field meta table<string, string> Free-form values

---@class memoria.AttachConceptOpts
---@field source? string Engram path, default: the current buffer's file
---@field field string Concept field on the engram
---@field concept string Concept name, or an alias of one

---@class memoria.AttachedConcept
---@field brain string Brain name
---@field source string Engram filename
---@field field string Concept field written
---@field concept string Name written into it

---@class memoria.UndeclaredConcept
---@field name string The mention, as written in the engrams
---@field count integer How many engrams name it
---@field engrams string[] Those filenames, sorted

--- A stored entry as it is handed out.
---@param name string Registry key
---@param entry memoria.ConceptEntry
---@return memoria.Concept
local function concept_of(name, entry)
  return {
    name = name,
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

--- Every registered concept, sorted by name.
---@param brain_name? string Default: resolved (see brain.resolve)
---@return memoria.Concept[]? concepts
---@return string? err
function M.list(brain_name)
  local target, registry, err = registry_of(brain_name)
  if not target then
    return nil, err
  end
  ---@cast registry memoria.ConceptRegistry

  local names = vim.tbl_keys(registry)
  table.sort(names)

  local concepts = {}
  for _, name in ipairs(names) do
    table.insert(concepts, concept_of(name, registry[name]))
  end
  return concepts
end

--- A registered concept, by its exact name.
---@param brain_name? string Default: resolved (see brain.resolve)
---@param name string Registry key
---@return memoria.Concept? found
---@return string? err
function M.get(brain_name, name)
  local target, registry, err = registry_of(brain_name)
  if not target then
    return nil, err
  end
  ---@cast registry memoria.ConceptRegistry

  local entry = registry[name]
  if not entry then
    return nil, ("no concept '%s'"):format(name)
  end
  return concept_of(name, entry)
end

--- The concept a mention names: its own key, else whoever lists it as an
--- alias. A mention nothing answers to is undeclared, which is a state to
--- fix rather than a failure.
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

  local name = concept.resolve(registry, mention)
  if not name then
    return nil, ("undeclared concept '%s'"):format(mention)
  end
  return concept_of(name, registry[name])
end

--- Create a concept. A name already registered is an error: filling one in
--- is what set_concept_meta is for.
---@param brain_name? string Default: resolved (see brain.resolve)
---@param name string Registry key
---@param type string What kind of thing it is; any string
---@param fields? table<string, string> Meta values
---@return memoria.Concept? added
---@return string? err
function M.create_concept(brain_name, name, type, fields)
  local target, registry, err = registry_of(brain_name)
  if not target then
    return nil, err
  end
  ---@cast registry memoria.ConceptRegistry

  if not name or vim.trim(name) == "" then
    return nil, "a concept name is required"
  end
  if registry[vim.trim(name)] then
    return nil, ("concept '%s' already exists"):format(vim.trim(name))
  end
  return M.set_concept_meta(target.name, vim.trim(name), type, fields)
end

--- Write a concept's meta, registering it when it is new. Values are merged
--- one key at a time, so a key the schema does not name survives; an empty
--- value removes its key.
---@param brain_name? string Default: resolved (see brain.resolve)
---@param name string Registry key
---@param type? string Required when the concept is new
---@param fields? table<string, string> Meta values
---@return memoria.Concept? written
---@return string? err
function M.set_concept_meta(brain_name, name, type, fields)
  local target, registry, err = registry_of(brain_name)
  if not target then
    return nil, err
  end
  ---@cast registry memoria.ConceptRegistry

  if not name or vim.trim(name) == "" then
    return nil, "a concept name is required"
  end
  name = vim.trim(name)

  if type and vim.trim(type) ~= "" then
    local cfg = config.load_brain_config(target.location)
    local known = concept.types(cfg, registry)
    if not vim.tbl_contains(known, vim.trim(type)) then
      return nil,
        ("no concept type '%s'; this brain has %s"):format(
          vim.trim(type),
          #known > 0 and table.concat(known, ", ") or "none"
        )
    end
  end

  local entry = registry[name]
  if not entry then
    if not type or vim.trim(type) == "" then
      return nil, ("a type is required for the new concept '%s'"):format(name)
    end
    entry = { type = vim.trim(type) }
  elseif type and vim.trim(type) ~= "" then
    entry.type = vim.trim(type)
  end

  entry.meta = entry.meta or {}
  for key, value in pairs(fields or {}) do
    entry.meta[key] = value ~= "" and value or nil
  end

  registry[name] = entry
  local ok, write_err = concept.write(target.location, registry)
  if not ok then
    return nil, write_err
  end
  return concept_of(name, entry)
end

--- Have a concept answer to another name as well, so a mention written that
--- way stops being undeclared. The engrams are not touched.
---@param brain_name? string Default: resolved (see brain.resolve)
---@param name string Registry key
---@param alias string Text that should resolve to it
---@return memoria.Concept? written
---@return string? err
function M.add_alias(brain_name, name, alias)
  local target, registry, err = registry_of(brain_name)
  if not target then
    return nil, err
  end
  ---@cast registry memoria.ConceptRegistry

  local entry = registry[name]
  if not entry then
    return nil, ("no concept '%s'"):format(name)
  end
  if not alias or vim.trim(alias) == "" then
    return nil, "an alias is required"
  end

  alias = vim.trim(alias)
  local answers = concept.resolve(registry, alias)
  if answers and answers ~= name then
    return nil, ("'%s' already resolves to %s"):format(alias, answers)
  end

  entry.aliases = entry.aliases or {}
  if alias ~= name and not vim.tbl_contains(entry.aliases, alias) then
    table.insert(entry.aliases, alias)
    table.sort(entry.aliases)
  end

  registry[name] = entry
  local ok, write_err = concept.write(target.location, registry)
  if not ok then
    return nil, write_err
  end
  return concept_of(name, entry)
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

  local current, err = atlas.refresh(target)
  if not current then
    return nil, err
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

--- A frontmatter value as a list: nil and "" are empty, a scalar is one item.
---@param value any Frontmatter field value
---@return string[]
local function as_list(value)
  if type(value) == "table" then
    return vim.tbl_filter(function(item)
      return type(item) == "string"
    end, value)
  elseif type(value) == "string" and value ~= "" then
    return { value }
  end
  return {}
end

--- Put a concept in one of an engram's concept fields. A name the registry
--- resolves is written under the concept's own name; one it does not is
--- written as given, the way a hand-typed tag would be. A name already there
--- changes nothing, and a field with `list = false` gives up the value it held.
---@param opts memoria.AttachConceptOpts
---@return memoria.AttachedConcept? attached What was written
---@return string? err
function M.attach_concept(opts)
  local located, err = synapse_module.locate(opts.source or vim.api.nvim_buf_get_name(0))
  if not located then
    return nil, err
  end
  local target = located.brain

  local cfg = config.load_brain_config(target.location)
  local field = opts.field and cfg.synapses[opts.field]
  if not field or field.target ~= "concept" then
    return nil, ("no concept field '%s'"):format(opts.field or "")
  end

  local mention = opts.concept and vim.trim(opts.concept) or ""
  if mention == "" then
    return nil, "a concept is required"
  end
  local registry = concept.read(target.location)
  local resolved = concept.resolve(registry, mention)
  local name = resolved or mention

  -- A field takes the one type it declares. A name the registry does not answer
  -- to has no type, so it contradicts nothing and goes in as written.
  local expects = field.concept_type
  local concept_type = resolved and registry[resolved].type or nil
  if not expects then
    return nil, ("concept field '%s' declares no concept_type"):format(opts.field)
  elseif not concept.accepts(cfg, opts.field, concept_type) then
    return nil, ("%s is a %s, %s takes %s"):format(name, concept_type, opts.field, expects)
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

  local values = as_list(fields and fields[opts.field])
  if not vim.tbl_contains(values, name) then
    -- A field holding one value is written as one, and gives up what it held.
    local value = field.list == false and name or vim.list_extend(values, { name })

    -- md-drafting refuses a field it cannot rewrite whole (a block scalar, a
    -- nested mapping, a key written twice) rather than leave half of it behind.
    local written, set_err = md_drafting.syntax.set_frontmatter_field(lines, opts.field, value)
    if not written then
      return nil, ("%s: %s"):format(located.filename, set_err)
    end
    local ok, write_err = file.write_lines(path, written)
    if not ok then
      return nil, write_err
    end
  end

  local _, refresh_err = atlas.refresh(target)
  if refresh_err then
    return nil, refresh_err
  end
  return { brain = target.name, source = located.filename, field = opts.field, concept = name }
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
