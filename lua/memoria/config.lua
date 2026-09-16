-- Configuration tiers: built-in defaults, setup() options, and a brain's own
-- `.mia_dna.json`. See ARCHITECTURE.md Part 3 §3.
local M = {}

local json = require("memoria.lib.json")

---@class memoria.FilenameConfig
---@field prefix "date"|"none" What goes before the slug
---@field separator string Between prefix and slug

---@class memoria.EngramsConfig
---@field date_format string Date tokens for filename and %date%
---@field filename memoria.FilenameConfig
---@field content_template string Prose written under the header

---@class memoria.SynapseField
---@field target "engram"|"concept" What a value points at
---@field show_empty? boolean Write the field even with no values

---@class memoria.Config
---@field add_commands boolean Create the :Mia* commands
---@field engrams memoria.EngramsConfig
---@field synapses table<string, memoria.SynapseField>

---@type memoria.Config
M.defaults = {
  -- Create the :Mia* user commands.
  add_commands = true,

  engrams = {
    -- Tokens: YYYY, YY, MM, DD, HH, mm, ss. Used by the filename prefix and %date%.
    date_format = "YYYYMMDD",

    filename = {
      -- "date" or "none".
      prefix = "date",
      separator = "_",
    },

    -- Prose under the generated header. %cursor% marks where typing starts.
    content_template = "# %title%\n\n%cursor%",
  },

  -- Engram fields go in the SYNAPSES block, concept fields in frontmatter.
  synapses = {
    up = { target = "engram", show_empty = true },
    down = { target = "engram", show_empty = true },
    tags = { target = "concept" },
  },
}

--- Options given to setup().
---@type table
M.options = {}

-- Maps whose entries are optional: a key removed from one stays removed. Every
-- other setting is required, so removing it falls back to the built-in default.
local OPTIONAL_ENTRIES = { synapses = true }

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
