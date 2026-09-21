-- The concept registry: `mia_concepts.json`, keyed by name. See
-- |memoria-concepts|. Reading and writing the file, and the pure questions
-- asked of a registry once it is loaded.
local M = {}

local json = require("memoria.lib.json")

---@class memoria.ConceptEntry Stored shape; the name is the key
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
    local kept = { type = entry.type, note = entry.note }
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

--- Every text that resolves to a concept, mapped to the name it resolves to:
--- the keys themselves, and every alias.
---@param registry memoria.ConceptRegistry
---@return table<string, string> names
function M.index(registry)
  local names = {}
  for name, entry in pairs(registry) do
    -- A key wins over an alias of the same text, whichever is seen first.
    names[name] = name
    for _, alias in ipairs(entry.aliases or {}) do
      if not registry[alias] then
        names[alias] = names[alias] or name
      end
    end
  end
  return names
end

--- The concept a mention names: its own key, else whoever lists it as an alias.
---@param registry memoria.ConceptRegistry
---@param mention string As written in an engram
---@return string? name Registry key, nil when the mention is undeclared
function M.resolve(registry, mention)
  if registry[mention] then
    return mention
  end
  return M.index(registry)[mention]
end

--- Every text a concept answers to, sorted: its name and its aliases.
---@param name string Registry key
---@param entry memoria.ConceptEntry
---@return string[] mentions
function M.mentions(name, entry)
  local mentions = { name }
  for _, alias in ipairs(entry.aliases or {}) do
    if alias ~= name then
      table.insert(mentions, alias)
    end
  end
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

--- What the derived data depends on, so an edit to the registry is noticed.
---@param registry memoria.ConceptRegistry
---@return string fingerprint
function M.hash(registry)
  -- vim.inspect sorts keys, so an equal registry hashes the same.
  return vim.fn.sha256(vim.inspect(registry)):sub(1, 16)
end

return M
