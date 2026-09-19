-- Brain registry: which brains exist on this machine, and the active one.
local M = {}

local config = require("memoria.config")
local json = require("memoria.lib.json")

---@class memoria.Brain
---@field name string Registry key
---@field location string Absolute folder path

---@alias memoria.Registry table<string, { location: string }>

---@type string?
local active

--- Registry file path.
---@return string
function M.registry_path()
  return vim.fn.stdpath("data") .. "/memoria/brains.json"
end

--- Read the registry; missing file is empty.
---@return memoria.Registry
local function read()
  local path = M.registry_path()
  if vim.fn.filereadable(path) == 0 then
    return {}
  end

  local registry, err = json.read(path)
  if type(registry) ~= "table" then
    vim.notify(("memoria: cannot read %s: %s"):format(path, err or "not a JSON object"), vim.log.levels.ERROR)
    return {}
  end
  return registry
end

--- Write the registry.
---@param registry memoria.Registry
---@return boolean ok
local function write(registry)
  -- An empty table encodes as a list; the registry is an object.
  local ok, err = json.write(M.registry_path(), vim.tbl_isempty(registry) and vim.empty_dict() or registry)
  if not ok then
    vim.notify("memoria: " .. err, vim.log.levels.ERROR)
  end
  return ok
end

--- Absolute path, no trailing separator.
---@param path string
---@return string
local function absolute(path)
  local expanded = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
  return (expanded:gsub("(.)/+$", "%1"))
end

--- Registered brain names, sorted.
---@return string[]
function M.names()
  local names = vim.tbl_keys(read())
  table.sort(names)
  return names
end

--- All registered brains, sorted by name.
---@return memoria.Brain[]
function M.list()
  local registry = read()
  local brains = {}
  for _, name in ipairs(M.names()) do
    table.insert(brains, { name = name, location = registry[name].location })
  end
  return brains
end

--- A registered brain.
---@param name string
---@return memoria.Brain?
function M.get(name)
  local entry = read()[name]
  return entry and { name = name, location = entry.location } or nil
end

--- Register a folder as a brain, creating it if missing.
---@param path string Folder path
---@param name? string Default: folder name
---@return memoria.Brain?
function M.add(path, name)
  local location = absolute(path)
  name = name or vim.fs.basename(location)

  local registry = read()
  if registry[name] then
    vim.notify(("memoria: brain '%s' already exists"):format(name), vim.log.levels.ERROR)
    return nil
  end

  if vim.fn.mkdir(location, "p") == 0 and vim.fn.isdirectory(location) == 0 then
    vim.notify("memoria: cannot create " .. location, vim.log.levels.ERROR)
    return nil
  end

  registry[name] = { location = location }
  if not write(registry) then
    return nil
  end
  return { name = name, location = location }
end

--- Remove a brain from the registry. Files are never touched.
---@param name string
---@return boolean ok
function M.deregister(name)
  local registry = read()
  if not registry[name] then
    vim.notify(("memoria: no brain '%s'"):format(name), vim.log.levels.ERROR)
    return false
  end

  registry[name] = nil
  if active == name then
    active = nil
  end
  return write(registry)
end

--- Set the active brain for this session.
---@param name string
---@return boolean ok
function M.switch(name)
  if not M.get(name) then
    vim.notify(("memoria: no brain '%s'"):format(name), vim.log.levels.ERROR)
    return false
  end

  active = name
  return true
end

--- The active brain, if one is set and still registered.
---@return memoria.Brain?
function M.active()
  return active and M.get(active) or nil
end

--- The brain whose folder holds a file.
---@param file string Absolute path
---@return memoria.Brain?
function M.containing(file)
  if file == "" then
    return nil
  end

  for _, brain in ipairs(M.list()) do
    if vim.startswith(file, brain.location .. "/") then
      return brain
    end
  end
  return nil
end

--- The brain a command would act on without being given one, and why. The
--- picker step of M.resolve is left out: it has no answer until it is asked.
---@return memoria.Brain? brain Nil when nothing resolves
---@return string? reason "holds the current buffer" or "active"
function M.current()
  local holding = M.containing(vim.api.nvim_buf_get_name(0))
  if holding then
    return holding, "holds the current buffer"
  end

  local brain = M.active()
  if brain then
    return brain, "active"
  end
end

--- Pick a registered brain. The one picker that does not name a brain, since
--- it is what decides one.
---@param callback fun(brain: memoria.Brain) Called once picked
function M.pick(callback)
  local names = M.names()
  if #names == 0 then
    vim.notify("memoria: no brains registered; add one with :MiaBrainAdd", vim.log.levels.WARN)
    return
  end

  vim.ui.select(names, { prompt = "Brain:" }, function(choice)
    if choice then
      callback(M.get(choice) --[[@as memoria.Brain]])
    end
  end)
end

--- Resolve a brain: by name, by current buffer, active, then picker.
---@param name? string Brain name
---@param callback fun(brain: memoria.Brain) Called once resolved
function M.resolve(name, callback)
  if name and name ~= "" then
    local brain = M.get(name)
    if not brain then
      vim.notify(("memoria: no brain '%s'"):format(name), vim.log.levels.ERROR)
      return
    end
    return callback(brain)
  end

  local brain = M.containing(vim.api.nvim_buf_get_name(0)) or M.active()
  if brain then
    return callback(brain)
  end

  M.pick(callback)
end

--- Open a brain's own config, creating an empty one when it has none. What the
--- file may hold is |memoria-mia_dna.json|; only what differs belongs in it.
---@param name? string Brain name, default: resolved (see M.resolve)
function M.open_config(name)
  M.resolve(name, function(brain)
    local path = config.brain_config_path(brain.location)

    if vim.fn.filereadable(path) == 0 and vim.fn.writefile({ "{}" }, path) ~= 0 then
      vim.notify("memoria: could not write " .. path, vim.log.levels.ERROR)
      return
    end

    vim.cmd.edit(vim.fn.fnameescape(path))
  end)
end

--- Echo every brain: "*" the active one, ">" the one holding the current
--- buffer, then name, location, "(config)" when it has a `.mia_dna.json`, and
--- ⚠ when the folder is missing.
function M.print_list()
  local brains = M.list()
  if #brains == 0 then
    vim.notify("memoria: no brains registered", vim.log.levels.INFO)
    return
  end

  local width = 0
  for _, brain in ipairs(brains) do
    width = math.max(width, #brain.name)
  end

  local holding = M.containing(vim.api.nvim_buf_get_name(0))

  local chunks = {}
  for index, brain in ipairs(brains) do
    local marker = (holding and brain.name == holding.name and ">" or " ") .. (brain.name == active and "* " or "  ")
    table.insert(chunks, { marker .. brain.name .. string.rep(" ", width - #brain.name + 2) })
    table.insert(chunks, { brain.location })
    if vim.fn.filereadable(config.brain_config_path(brain.location)) == 1 then
      table.insert(chunks, { "  (config)", "Comment" })
    end
    if vim.fn.isdirectory(brain.location) == 0 then
      table.insert(chunks, { "  ⚠ missing", "WarningMsg" })
    end
    if index < #brains then
      table.insert(chunks, { "\n" })
    end
  end
  vim.api.nvim_echo(chunks, false, {})
end

return M
