-- Configuration tiers: built-in defaults, setup() options, and a brain's own
-- `.mia_dna.json`. See |memoria-config|.
local M = {}

local json = require("memoria.lib.json")

---@class memoria.FilenameConfig
---@field prefix "date"|"concept"|"none" What goes before the slug
---@field date_format string Date tokens for the "date" prefix

---@alias memoria.ConceptForm "slug"|"display_name"

---@class memoria.EngramsConfig
---@field date_format string Date tokens for %date%
---@field concept_form memoria.ConceptForm How concept fields write a concept, unless a field says
---@field filename memoria.FilenameConfig
---@field content_template string Prose written under the header
---@field task_markers { not_done: string[], done: string[] } Checkbox markers the atlas indexes

---@class memoria.SynapseField
---@field inverse? string Engram field kept in sync on the target
---@field list? boolean Whether the field holds more than one value
---@field show_empty? boolean Write the field even with no values

---@class memoria.FrontmatterField
---@field kind "concept"|"value" What a value is
---@field list? boolean Whether the field holds more than one value
---@field concept_type? string The one concept type a concept field takes; omitted, every type
---@field concept_form? memoria.ConceptForm How a concept field writes a concept
---@field default? string What create_engram writes into a value field given none; placeholders expanded

---@class memoria.ConceptSchema
---@field fields string[] Meta keys a concept of this type is asked for, in order

---@class memoria.Config
---@field add_commands boolean Create the :Mia* commands
---@field engrams memoria.EngramsConfig
---@field synapses table<string, memoria.SynapseField>
---@field frontmatter table<string, memoria.FrontmatterField>
---@field concepts table<string, memoria.ConceptSchema>

---@type memoria.Config
M.defaults = {
  -- Create the :Mia* user commands.
  add_commands = true,

  engrams = {
    -- Tokens: YYYY, YY, MM, DD, HH, mm, ss. Used by %date%, in the template and
    -- in a field's default.
    date_format = "YYYY-MM-DD",

    -- How a concept field writes a concept: "slug" (its key) or "display_name".
    concept_form = "slug",

    filename = {
      -- "date", "concept" or "none".
      prefix = "date",
      -- Tokens as above, for the "date" prefix.
      date_format = "YYYY-MM-DD",
    },

    -- Prose under the generated header. %cursor% marks where typing starts.
    content_template = "# %title%\n\n%cursor%",

    -- Checkbox markers the atlas indexes, by state. Replaces, never merges.
    task_markers = {
      not_done = { "[ ]" },
      done = { "[x]", "[X]" },
    },
  },

  -- Engram-to-engram fields, in the SYNAPSES block.
  synapses = {
    up = { inverse = "down", list = true, show_empty = true },
    down = { inverse = "up", list = true, show_empty = true },
  },

  -- Frontmatter fields: concepts, or plain values.
  frontmatter = {
    created = { kind = "value", list = false, default = "%date%" },
    tags = { kind = "concept", concept_type = "tag", list = true },
  },

  -- The concept types this brain has, and what each is asked for when its meta
  -- is filled in. A concept's type is one of these, or one the registry already
  -- uses.
  concepts = {
    tag = { fields = { "description" } },
  },
}

--- Options given to setup().
---@type table
M.options = {}

--- Whether setup() has run. The CLI refuses to write with a config that was
--- sourced without it, see |memoria-cli|.
---@type boolean
M.configured = false

-- Maps whose entries are optional: a key removed from one stays removed. Every
-- other setting is required, so removing it falls back to the built-in default.
local OPTIONAL_ENTRIES = { concepts = true, frontmatter = true, synapses = true }

--- Merge `opts` over `defaults`: maps by key, lists replaced wholesale, and
--- `vim.NIL` (JSON null) removing the key.
---@param defaults table Base table
---@param opts table Overrides
---@return table merged New table
function M.merge(defaults, opts)
  local merged = vim.deepcopy(defaults)

  for key, value in pairs(opts) do
    local default = merged[key]
    if value == vim.NIL then
      merged[key] = nil
    elseif type(value) == "table" and type(default) == "table" and not vim.islist(default) then
      merged[key] = M.merge(default, value)
    else
      merged[key] = vim.deepcopy(value)
    end
  end

  return merged
end

--- Put back every required setting a null removed, from the built-in defaults.
---@param merged table Merged config, changed in place
---@param defaults table Built-in defaults at the same level
local function restore_required(merged, defaults)
  for key, default in pairs(defaults) do
    if merged[key] == nil then
      merged[key] = OPTIONAL_ENTRIES[key] and {} or vim.deepcopy(default)
    elseif type(default) == "table" and not vim.islist(default) and not OPTIONAL_ENTRIES[key] then
      restore_required(merged[key], default)
    end
  end
end

--- Defaults with setup() options over them.
---@return memoria.Config
function M.get()
  local merged = M.merge(M.defaults, M.options)
  restore_required(merged, M.defaults)
  return merged
end

--- Where a brain's own overrides live.
---@param brain_path string Absolute brain location
---@return string path
function M.brain_config_path(brain_path)
  return brain_path .. "/.mia_dna.json"
end

--- The config for one brain: defaults, setup() options, then `.mia_dna.json`.
---@param brain_path string Absolute brain location
---@return memoria.Config
function M.load_brain_config(brain_path)
  local merged = M.get()

  local path = M.brain_config_path(brain_path)
  if vim.fn.filereadable(path) == 0 then
    return merged
  end

  local dna, err = json.read(path)
  if type(dna) ~= "table" then
    vim.notify(("memoria: skipping %s: %s"):format(path, err or "not a JSON object"), vim.log.levels.ERROR)
    return merged
  end

  -- Commands are editor-wide; a brain has no say in them.
  dna.add_commands = nil
  merged = M.merge(merged, dna)
  restore_required(merged, M.defaults)
  return merged
end

return M
