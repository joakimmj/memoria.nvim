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
---@return memoria.Registry registry Empty when it could not be read
---@return string? err Why it could not be read
local function read()
  local path = M.registry_path()
  if vim.fn.filereadable(path) == 0 then
    return {}
  end

  local registry, err = json.read(path)
  if type(registry) ~= "table" then
    return {}, ("cannot read %s: %s"):format(path, err or "not a JSON object")
  end
  return registry
end

--- Write the registry.
---@param registry memoria.Registry
---@return boolean? ok
---@return string? err Why it could not be written
local function write(registry)
  -- An empty table encodes as a list; the registry is an object.
  local ok, err = json.write(M.registry_path(), vim.tbl_isempty(registry) and vim.empty_dict() or registry)
  if not ok then
    return nil, err
  end
  return true
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
---@return memoria.Brain? brain
---@return string? err Why it could not be registered
function M.add(path, name)
  local location = absolute(path)
  name = name or vim.fs.basename(location)

  local registry, err = read()
  if err then
    return nil, err
  end
  if registry[name] then
    return nil, ("brain '%s' already exists"):format(name)
  end

  if vim.fn.mkdir(location, "p") == 0 and vim.fn.isdirectory(location) == 0 then
    return nil, "cannot create " .. location
  end

  registry[name] = { location = location }
  local ok, write_err = write(registry)
  if not ok then
    return nil, write_err
  end
  return { name = name, location = location }
end

--- Remove a brain from the registry. Files are never touched.
---@param name string
---@return boolean? ok
---@return string? err
function M.deregister(name)
  local registry, err = read()
  if err then
    return nil, err
  end
  if not registry[name] then
    return nil, ("no brain '%s'"):format(name)
  end

  registry[name] = nil
  if active == name then
    active = nil
  end
  return write(registry)
end

--- Set the active brain for this session.
---@param name string
---@return memoria.Brain? brain The now-active brain
---@return string? err
function M.switch(name)
  local brain = M.get(name)
  if not brain then
    return nil, ("no brain '%s'"):format(name)
  end

  active = name
  return brain
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

--- The brain to act in: the one named, the one holding the current buffer, the
--- active one, or the only one registered (|memoria-brains|). The last step,
--- the picker, is the view's; a name that is not registered is an error and
--- never reaches it.
---@param name? string Brain name, "" or nil to resolve
---@return memoria.Brain? brain
---@return string? err Why none resolved
function M.resolve(name)
  if name and name ~= "" then
    local brain = M.get(name)
    if not brain then
      return nil, ("no brain '%s'"):format(name)
    end
    return brain
  end

  local brain = M.current()
  if brain then
    return brain
  end

  local names = M.names()
  if #names == 1 then
    return M.get(names[1])
  elseif #names == 0 then
    return nil, "no brains registered"
  end
  return nil, ("no brain resolved; name one (%s)"):format(table.concat(names, ", "))
end

--- A brain's own config, written as `{}` when it has none. What the file may
--- hold is |memoria-mia_dna.json|; only what differs belongs in it. Opening it
--- is the view's.
---@param target memoria.Brain
---@return string? path
---@return string? err
function M.ensure_config(target)
  local path = config.brain_config_path(target.location)

  if vim.fn.filereadable(path) == 0 and vim.fn.writefile({ "{}" }, path) ~= 0 then
    return nil, "could not write " .. path
  end
  return path
end

return M
