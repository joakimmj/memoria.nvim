-- The concept registry: `mia_concepts.json`, keyed by slug. See
-- |memoria-concepts|. Reading and writing the file, and the pure questions
-- asked of a registry once it is loaded.
local M = {}

local json = require("memoria.lib.json")
local slug = require("memoria.lib.slug")

---@class memoria.ConceptEntry Stored shape; the key is its slug
---@field display_name? string The natural name; the key when missing
---@field type? string What kind of thing it is, e.g. "person"
---@field aliases? string[] Other names it answers to
---@field note? string Free text
---@field meta? table<string, string> Free-form, shaped by the type's schema

---@alias memoria.ConceptRegistry table<string, memoria.ConceptEntry>

--- Where a brain's concepts live. Visible and hand-editable, unlike the
--- dot-prefixed files beside it.
---@param location string Absolute brain location
---@return string path
function M.path(location)
  return location .. "/mia_concepts.json"
end

--- Read a brain's registry; a missing one is empty.
---@param location string Absolute brain location
---@return memoria.ConceptRegistry registry Empty when there is none, or it cannot be read
---@return string? err Why it could not be read
function M.read(location)
  local path = M.path(location)
  if vim.fn.filereadable(path) == 0 then
    return {}
  end

  local registry, err = json.read(path)
  if type(registry) ~= "table" then
    return {}, ("cannot read %s: %s"):format(path, err or "not a JSON object")
  end
  return registry
end

--- Write a brain's registry, one key per line so it stays readable by hand.
--- An entry's empty parts are left out rather than written as empty lists.
---@param location string Absolute brain location
---@param registry memoria.ConceptRegistry
---@return boolean? ok
---@return string? err Why it could not be written
function M.write(location, registry)
  local stored = {}
  for name, entry in pairs(registry) do
    local kept = { display_name = entry.display_name, type = entry.type, note = entry.note }
    if entry.aliases and #entry.aliases > 0 then
      kept.aliases = entry.aliases
    end
    if entry.meta and next(entry.meta) ~= nil then
      kept.meta = entry.meta
    end
    stored[name] = kept
  end

  -- An empty table encodes as a list; a registry is an object.
  local ok, err = json.write(M.path(location), next(stored) == nil and vim.empty_dict() or stored, { pretty = true })
  if not ok then
    return nil, err
  end
  return true
end

--- A concept's natural name: its display_name, or its key without one.
---@param key string Registry key
---@param entry memoria.ConceptEntry
---@return string
function M.display_name(key, entry)
  return type(entry.display_name) == "string" and entry.display_name ~= "" and entry.display_name or key
end

--- Every text that resolves to a concept exactly, mapped to its key: the keys
--- themselves, then display names, then aliases. An earlier kind wins over a
--- later one of the same text.
---@param registry memoria.ConceptRegistry
---@return table<string, string> keys
function M.index(registry)
  local keys = {}
  for key in pairs(registry) do
    keys[key] = key
  end
  for key, entry in pairs(registry) do
    local name = M.display_name(key, entry)
    keys[name] = keys[name] or key
  end
  for key, entry in pairs(registry) do
    for _, alias in ipairs(entry.aliases or {}) do
      keys[alias] = keys[alias] or key
    end
  end
  return keys
end

--- The concept a mention names: a key, a display name or an alias as written,
--- else a key its slug is. Exact matches come first, so `C++` finds the concept
--- displayed as `C++` even when another one's key is `c`.
---@param registry memoria.ConceptRegistry
---@param mention string As written in an engram
---@return string? key Nil when the mention is undeclared
function M.resolve(registry, mention)
  local exact = M.index(registry)[mention]
  if exact then
    return exact
  end
  local slugged = slug.slugify(mention)
  return registry[slugged] and slugged or nil
end

--- Every text a concept answers to exactly, sorted: its key, its display name
--- and its aliases.
---@param key string Registry key
---@param entry memoria.ConceptEntry
---@return string[] mentions
function M.mentions(key, entry)
  local seen = { [key] = true, [M.display_name(key, entry)] = true }
  for _, alias in ipairs(entry.aliases or {}) do
    seen[alias] = true
  end
  local mentions = vim.tbl_keys(seen)
  table.sort(mentions)
  return mentions
end

--- Registered concepts by type, sorted. A concept with no type groups nowhere.
---@param registry memoria.ConceptRegistry
---@return table<string, string[]> by_type
function M.by_type(registry)
  local by_type = {}
  for name, entry in pairs(registry) do
    if type(entry.type) == "string" and entry.type ~= "" then
      by_type[entry.type] = by_type[entry.type] or {}
      table.insert(by_type[entry.type], name)
    end
  end

  for _, names in pairs(by_type) do
    table.sort(names)
  end
  return by_type
end

--- The concept types a brain knows: the types its config gives a schema, and
--- the types its registry already uses. A type nobody has declared is not one.
---@param cfg memoria.Config Brain config
---@param registry memoria.ConceptRegistry
---@return string[] types Sorted
function M.types(cfg, registry)
  local seen = {}
  for name in pairs(cfg.concepts) do
    seen[name] = true
  end
  for _, entry in pairs(registry) do
    if type(entry.type) == "string" and entry.type ~= "" then
      seen[entry.type] = true
    end
  end

  local types = vim.tbl_keys(seen)
  table.sort(types)
  return types
end

--- Whether a concept field takes a concept of this type. A field declaring a
--- type takes that one; a field declaring none takes every type. A name the
--- registry does not answer to has no type, and so contradicts nothing — it
--- stays the plain label it has always been.
---@param cfg memoria.Config Brain config
---@param field string Concept field name
---@param concept_type? string The concept's own type, nil when it has none
---@return boolean
function M.accepts(cfg, field, concept_type)
  local declared = cfg.frontmatter[field]
  if not declared or declared.kind ~= "concept" then
    return false
  end
  local expects = declared.concept_type
  return expects == nil or concept_type == nil or concept_type == expects
end

--- The concept fields taking this type, sorted: the ones declaring it and the
--- ones declaring none.
---@param cfg memoria.Config Brain config
---@param concept_type? string
---@return string[] fields
function M.fields_for(cfg, concept_type)
  local fields = {}
  for name, field in pairs(cfg.frontmatter) do
    if field.kind == "concept" and M.accepts(cfg, name, concept_type) then
      table.insert(fields, name)
    end
  end
  table.sort(fields)
  return fields
end

--- How a concept field writes a concept.
---@param cfg memoria.Config Brain config
---@param field string Concept field name
---@return memoria.ConceptForm
function M.form(cfg, field)
  return (cfg.frontmatter[field] or {}).concept_form or cfg.engrams.concept_form
end

--- The text a concept is written as in a field of this form.
---@param key string Registry key
---@param entry memoria.ConceptEntry
---@param form memoria.ConceptForm
---@return string
function M.text_for(key, entry, form)
  return form == "display_name" and M.display_name(key, entry) or key
end

--- A mention as a field of this form writes it: the resolved concept's key or
--- display name, or the mention as given when nothing answers to it.
---@param registry memoria.ConceptRegistry
---@param form memoria.ConceptForm
---@param mention string
---@return string text
---@return string? key The concept it resolved to
function M.canonical(registry, form, mention)
  local key = M.resolve(registry, mention)
  if not key then
    return mention
  end
  return M.text_for(key, registry[key], form), key
end

--- A field's values rewritten in its form, in order, each concept once.
---@param registry memoria.ConceptRegistry
---@param form memoria.ConceptForm
---@param values string[]
---@return string[]
function M.canonical_list(registry, form, values)
  local written, seen = {}, {}
  for _, value in ipairs(values) do
    local text, key = M.canonical(registry, form, value)
    local identity = key or text
    if not seen[identity] then
      seen[identity] = true
      table.insert(written, text)
    end
  end
  return written
end

--- What the derived data depends on, so an edit to the registry is noticed.
---@param registry memoria.ConceptRegistry
---@return string fingerprint
function M.hash(registry)
  -- vim.inspect sorts keys, so an equal registry hashes the same.
  return vim.fn.sha256(vim.inspect(registry)):sub(1, 16)
end

return M
