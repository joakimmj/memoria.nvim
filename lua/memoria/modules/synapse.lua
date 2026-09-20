-- Linking engrams: a synapse field on one side, its inverse on the other.
local M = {}

local atlas = require("memoria.modules.atlas")
local brain = require("memoria.modules.brain")
local config = require("memoria.config")
local file = require("memoria.lib.file")
local synapse = require("memoria.lib.synapse")

---@class memoria.AddSynapseOpts
---@field source? string Engram path, default: the current buffer's file
---@field target string Engram filename
---@field field string Engram field on the source

---@class memoria.EngramLocation
---@field brain memoria.Brain The brain holding it
---@field filename string Its filename in that brain

---@class memoria.Synapse
---@field brain string Brain name
---@field source string Source filename
---@field field string Engram field written on the source
---@field target string Target filename

---@class memoria.LoadedEngram
---@field path string Absolute path
---@field lines string[] Current lines
---@field synapses table<string, memoria.SynapseLink[]> Block values, edited in place

--- A field's inverse, when it names a configured engram field.
---@param fields table<string, memoria.SynapseField> Synapse config
---@param name string Field name
---@return string? inverse
local function inverse_of(fields, name)
  local inverse = fields[name].inverse
  local field = inverse and fields[inverse]
  return field and field.target == "engram" and inverse or nil
end

--- The engram a synapse value points at, as a filename.
---@param value memoria.SynapseLink
---@return string
local function target_of(value)
  return atlas.engram_target(value.path) or value.path
end

--- The brain an engram path belongs to. Brains are flat, so an engram is a
--- markdown file sitting directly inside a registered one.
---@param source string Engram path
---@return memoria.EngramLocation? located
---@return string? err Why it is not an engram in a brain
function M.locate(source)
  local path = vim.fn.fnamemodify(source, ":p")
  local target_brain = brain.containing(path)

  if not target_brain or vim.fs.dirname(path) ~= target_brain.location or not path:match("%.md$") then
    return nil, "not an engram in a registered brain"
  end
  return { brain = target_brain, filename = vim.fs.basename(path) }
end

--- Put `target` in `source`'s field, and `source` in `target`'s inverse field.
--- Values already there are left alone, so running it again writes the side
--- that is missing and nothing else. A field with `list = false` gives up the
--- value it held, and that engram loses its inverse back. Nothing is written
--- unless every file can be.
---@param target_brain memoria.Brain
---@param source string Engram filename
---@param target string Engram filename
---@param field string Engram field on `source`
---@return boolean? ok
---@return string? err
function M.connect(target_brain, source, target, field)
  local fields = config.load_brain_config(target_brain.location).synapses

  if not fields[field] or fields[field].target ~= "engram" then
    return nil, ("no engram field '%s'"):format(field)
  end
  if source == target then
    return nil, "an engram cannot link to itself"
  end

  ---@type table<string, memoria.LoadedEngram|false>
  local engrams = {}

  ---@param name string Engram filename
  ---@return memoria.LoadedEngram?
  local function load(name)
    if engrams[name] == nil then
      local path = target_brain.location .. "/" .. name
      local lines = vim.uv.fs_stat(path) and file.read_lines(path)
      engrams[name] = lines and { path = path, lines = lines, synapses = synapse.parse_synapse_block(lines) or {} }
        or false
    end
    return engrams[name] or nil
  end

  for _, name in ipairs({ source, target }) do
    if not load(name) then
      return nil, "no engram " .. name
    end
  end

  ---@param name string Engram filename
  ---@param field_name string
  ---@param other string Filename to drop
  local function remove(name, field_name, other)
    local engram = load(name)
    if engram and engram.synapses[field_name] then
      engram.synapses[field_name] = vim.tbl_filter(function(value)
        return target_of(value) ~= other
      end, engram.synapses[field_name])
    end
  end

  ---@param name string Engram filename
  ---@param field_name string
  ---@param other string Filename to add
  local function add(name, field_name, other)
    local engram = load(name) --[[@as memoria.LoadedEngram]]
    local values = engram.synapses[field_name] or {}
    for _, value in ipairs(values) do
      if target_of(value) == other then
        return
      end
    end

    if fields[field_name].list == false then
      local inverse = inverse_of(fields, field_name)
      for _, value in ipairs(values) do
        if inverse then
          remove(target_of(value), inverse, name)
        end
      end
      values = {}
    end

    table.insert(values, synapse.link(other))
    engram.synapses[field_name] = values
  end

  add(source, field, target)
  local inverse = inverse_of(fields, field)
  if inverse then
    add(target, inverse, source)
  end

  local writes = {}
  for name, engram in pairs(engrams) do
    if engram then
      local lines, err = synapse.write_synapse_block(engram.lines, engram, fields)
      if not lines then
        return nil, ("%s: %s"):format(name, err)
      end
      if not vim.deep_equal(lines, engram.lines) then
        table.insert(writes, { path = engram.path, lines = lines })
      end
    end
  end

  for _, write in ipairs(writes) do
    local ok, err = file.write_lines(write.path, write.lines)
    if not ok then
      return nil, err
    end
  end
  return true
end

--- Link one engram to another through a synapse field, writing the inverse on
--- the other one, and bring the atlas up to date. Given all of `source`,
--- `field` and `target` it asks nothing and opens nothing; the pickers that
--- fill them in are the view's.
---@param opts memoria.AddSynapseOpts
---@return memoria.Synapse? synapse What was linked
---@return string? err
function M.add_synapse(opts)
  local located, err = M.locate(opts.source or vim.api.nvim_buf_get_name(0))
  if not located then
    return nil, err
  end

  if not opts.field or opts.field == "" then
    return nil, "a synapse field is required"
  end
  if not opts.target or opts.target == "" then
    return nil, "a target engram is required"
  end

  local target = vim.fs.basename(opts.target)
  local ok, connect_err = M.connect(located.brain, located.filename, target, opts.field)
  if not ok then
    return nil, connect_err
  end

  local _, refresh_err = atlas.refresh(located.brain)
  if refresh_err then
    return nil, refresh_err
  end

  return { brain = located.brain.name, source = located.filename, field = opts.field, target = target }
end

return M
