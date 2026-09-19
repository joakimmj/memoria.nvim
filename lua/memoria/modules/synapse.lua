-- Linking engrams: a synapse field on one side, its inverse on the other.
local M = {}

local atlas = require("memoria.modules.atlas")
local brain = require("memoria.modules.brain")
local config = require("memoria.config")
local file = require("memoria.lib.file")
local synapse = require("memoria.lib.synapse")

---@class memoria.AddSynapseOpts
---@field source? string Engram path, default: the current buffer's file
---@field target? string Engram filename, default: picked
---@field field? string Engram field, default: picked

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

--- Put `target` in `source`'s field, and `source` in `target`'s inverse field.
--- Values already there are left alone, so running it again writes the side
--- that is missing and nothing else. A field with `list = false` gives up the
--- value it held, and that engram loses its inverse back. Nothing is written
--- unless every file can be.
---@param target_brain memoria.Brain
---@param source string Engram filename
---@param target string Engram filename
---@param field string Engram field on `source`
---@return boolean ok
function M.connect(target_brain, source, target, field)
  local fields = config.load_brain_config(target_brain.location).synapses
  local in_brain = ("memoria: (%s) "):format(target_brain.name)

  if not fields[field] or fields[field].target ~= "engram" then
    vim.notify(in_brain .. ("no engram field '%s'"):format(field), vim.log.levels.ERROR)
    return false
  end
  if source == target then
    vim.notify(in_brain .. "an engram cannot link to itself", vim.log.levels.ERROR)
    return false
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
      vim.notify(in_brain .. "no engram " .. name, vim.log.levels.ERROR)
      return false
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
        vim.notify(in_brain .. ("%s: %s"):format(name, err), vim.log.levels.ERROR)
        return false
      end
      if not vim.deep_equal(lines, engram.lines) then
        table.insert(writes, { path = engram.path, lines = lines })
      end
    end
  end

  for _, write in ipairs(writes) do
    local ok, err = file.write_lines(write.path, write.lines)
    if not ok then
      vim.notify("memoria: " .. err, vim.log.levels.ERROR)
      return false
    end
  end
  return true
end

--- Link the current engram to another through a synapse field, writing the
--- inverse on the other one. Asks for whatever `opts` leaves out.
---@param opts? memoria.AddSynapseOpts
function M.add_synapse(opts)
  opts = opts or {}

  local source = vim.fn.fnamemodify(opts.source or vim.api.nvim_buf_get_name(0), ":p")
  local target_brain = brain.containing(source)
  if not target_brain or vim.fs.dirname(source) ~= target_brain.location or not source:match("%.md$") then
    vim.notify("memoria: not an engram in a registered brain", vim.log.levels.ERROR)
    return
  end

  local source_name = vim.fs.basename(source)
  local in_brain = ("(%s) "):format(target_brain.name)
  local cfg = config.load_brain_config(target_brain.location)

  ---@param field string
  ---@param target string Engram filename
  local function finish(field, target)
    if M.connect(target_brain, source_name, target, field) then
      atlas.refresh(target_brain)
      vim.notify(("memoria: %s%s %s → %s"):format(in_brain, source_name, field, target))
    end
  end

  ---@param field string
  local function pick_target(field)
    local target = opts.target
    if target then
      return finish(field, vim.fs.basename(target))
    end

    local current = atlas.refresh(target_brain)
    if not current then
      return
    end

    local names = vim.tbl_filter(function(name)
      return name ~= source_name
    end, vim.tbl_keys(current.engrams))
    table.sort(names)
    if #names == 0 then
      vim.notify("memoria: " .. in_brain .. "no other engrams to link", vim.log.levels.WARN)
      return
    end

    vim.ui.select(names, {
      prompt = in_brain .. field .. ":",
      format_item = function(name)
        local title = current.engrams[name].title
        return title == (name:gsub("%.md$", "")) and name or ("%s (%s)"):format(title, name)
      end,
    }, function(choice)
      if choice then
        finish(field, choice)
      end
    end)
  end

  local fields = synapse.field_names(cfg.synapses, "engram")
  if opts.field then
    if not vim.tbl_contains(fields, opts.field) then
      vim.notify(("memoria: %sno engram field '%s'"):format(in_brain, opts.field), vim.log.levels.ERROR)
      return
    end
    pick_target(opts.field)
  elseif #fields == 0 then
    vim.notify("memoria: " .. in_brain .. "no engram fields configured", vim.log.levels.WARN)
  elseif #fields == 1 then
    pick_target(fields[1])
  else
    vim.ui.select(fields, { prompt = in_brain .. "Synapse field:" }, function(choice)
      if choice then
        pick_target(choice)
      end
    end)
  end
end

return M
