-- Brains as the editor sees them: the picker, the list, and the config file.
local M = {}

local brain = require("memoria.modules.brain")
local config = require("memoria.config")
local message = require("memoria.ui.message")

--- Pick a registered brain. The one picker that does not name a brain, since
--- it is what decides one.
---@param run fun(target: memoria.Brain) Called once picked
function M.pick(run)
  local names = brain.names()
  if #names == 0 then
    message.warn("no brains registered; register one with :MiaBrainRegister")
    return
  end

  vim.ui.select(names, { prompt = "Brain:" }, function(choice)
    if choice then
      run(brain.get(choice) --[[@as memoria.Brain]])
    end
  end)
end

--- Resolve a brain and act in it: what the registry answers
--- (|memoria-brains|), else the picker. A brain that was named but is not
--- registered is an error — the caller said which one — so the picker is only
--- reachable unnamed.
---@param name? string Brain name, possibly ""
---@param run fun(target: memoria.Brain)
function M.resolve(name, run)
  if name and name ~= "" then
    local target, err = brain.resolve(name)
    if not target then
      return message.error(err --[[@as string]])
    end
    return run(target)
  end

  local target = brain.resolve()
  if target then
    return run(target)
  end
  M.pick(run)
end

--- Choose a brain: the picker when not named. For the commands that choose a
--- brain rather than act in one, where the current buffer's brain would be a
--- surprise rather than a default.
---@param name? string Brain name, possibly ""
---@param run fun(target: memoria.Brain)
function M.choose(name, run)
  if name and name ~= "" then
    local target, err = brain.resolve(name)
    if not target then
      return message.error(err --[[@as string]])
    end
    return run(target)
  end
  M.pick(run)
end

--- Register a folder as a brain, creating it if missing.
---@param path string Folder path
---@param name? string Default: folder name
function M.register(path, name)
  local registered, err = brain.register(path, name)
  if not registered then
    return message.error(err --[[@as string]])
  end
  message.info(("registered brain '%s' at %s"):format(registered.name, registered.location))
end

--- Remove a brain from the registry, picked when not named.
---@param name? string Brain name, possibly ""
function M.deregister(name)
  M.choose(name, function(target)
    local ok, err = brain.deregister(target.name)
    if not ok then
      return message.error(err --[[@as string]])
    end
    message.info(("deregistered brain '%s'"):format(target.name))
  end)
end

--- Set the active brain, picked when not named.
---@param name? string Brain name, possibly ""
function M.switch(name)
  M.choose(name, function(target)
    local switched, err = brain.switch(target.name)
    if not switched then
      return message.error(err --[[@as string]])
    end
    message.info(("active brain '%s'"):format(switched.name))
  end)
end

--- Open a brain's own config, creating an empty one when it has none.
---@param name? string Brain name, default: resolved (see M.resolve)
function M.open_config(name)
  M.resolve(name, function(target)
    local path, err = brain.ensure_config(target)
    if not path then
      return message.error(err --[[@as string]])
    end
    vim.cmd.edit(vim.fn.fnameescape(path))
  end)
end

--- Echo every brain: "*" the active one, ">" the one holding the current
--- buffer, then name, location, "(config)" when it has a `.mia_dna.json`, and
--- ⚠ when the folder is missing.
function M.print_list()
  local brains = brain.list()
  if #brains == 0 then
    message.info("no brains registered")
    return
  end

  local width = 0
  for _, entry in ipairs(brains) do
    width = math.max(width, #entry.name)
  end

  local holding = brain.containing(vim.api.nvim_buf_get_name(0))
  local active = brain.active()

  local chunks = {}
  for index, entry in ipairs(brains) do
    local marker = (holding and entry.name == holding.name and ">" or " ")
      .. (active and entry.name == active.name and "* " or "  ")
    table.insert(chunks, { marker .. entry.name .. string.rep(" ", width - #entry.name + 2) })
    table.insert(chunks, { entry.location })
    if vim.fn.filereadable(config.brain_config_path(entry.location)) == 1 then
      table.insert(chunks, { "  (config)", "Comment" })
    end
    if vim.fn.isdirectory(entry.location) == 0 then
      table.insert(chunks, { "  ⚠ missing", "WarningMsg" })
    end
    if index < #brains then
      table.insert(chunks, { "\n" })
    end
  end
  vim.api.nvim_echo(chunks, false, {})
end

return M
