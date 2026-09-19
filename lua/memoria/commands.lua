-- The :Mia* user commands, created by setup() unless `add_commands` is off.
local M = {}

local atlas = require("memoria.modules.atlas")
local brain = require("memoria.modules.brain")
local config = require("memoria.config")
local engram = require("memoria.modules.engram")
local synapse = require("memoria.modules.synapse")
local synapse_lib = require("memoria.lib.synapse")

--- Complete brain names.
---@param lead string Typed so far
---@return string[]
local function complete_brains(lead)
  return vim.tbl_filter(function(name)
    return vim.startswith(name, lead)
  end, brain.names())
end

--- Run with the named brain, or one picked when none is named. Never the
--- current or active brain: these commands choose a brain, not act in one.
---@param name string Command argument, possibly ""
---@param run fun(name: string)
local function with_brain(name, run)
  if name ~= "" then
    return run(name)
  end
  brain.pick(function(picked)
    run(picked.name)
  end)
end

--- Complete engram field names of the current buffer's brain.
---@param lead string Typed so far
---@return string[]
local function complete_engram_fields(lead)
  local current = brain.current()
  if not current then
    return {}
  end

  local fields = config.load_brain_config(current.location).synapses
  return vim.tbl_filter(function(name)
    return vim.startswith(name, lead)
  end, synapse_lib.field_names(fields, "engram"))
end

--- Create every command. Safe to call again.
function M.create()
  local create = vim.api.nvim_create_user_command

  create("MiaBrainAdd", function(cmd)
    local added = brain.add(cmd.fargs[1], cmd.fargs[2])
    if added then
      vim.notify(("memoria: added brain '%s' at %s"):format(added.name, added.location))
    end
  end, { nargs = "+", complete = "dir", desc = "Register a folder as a brain" })

  create("MiaBrainDeregister", function(cmd)
    with_brain(cmd.args, function(name)
      if brain.deregister(name) then
        vim.notify(("memoria: deregistered brain '%s'"):format(name))
      end
    end)
  end, { nargs = "?", complete = complete_brains, desc = "Remove a brain from the registry" })

  create("MiaBrainList", brain.print_list, { nargs = 0, desc = "List registered brains" })

  create("MiaBrainSwitch", function(cmd)
    with_brain(cmd.args, function(name)
      if brain.switch(name) then
        vim.notify(("memoria: active brain '%s'"):format(name))
      end
    end)
  end, { nargs = "?", complete = complete_brains, desc = "Set the active brain" })

  create("MiaBrainConfig", function(cmd)
    brain.open_config(cmd.fargs[1])
  end, { nargs = "?", complete = complete_brains, desc = "Open a brain's .mia_dna.json" })

  create("MiaEngramAdd", function(cmd)
    engram.add_engram(cmd.fargs[1])
  end, { nargs = "?", complete = complete_brains, desc = "Create an engram" })

  create("MiaSynapseAdd", function(cmd)
    synapse.add_synapse({ field = cmd.fargs[1] })
  end, { nargs = "?", complete = complete_engram_fields, desc = "Link the current engram to another" })

  create("MiaAtlasRebuild", function(cmd)
    atlas.rebuild_atlas(cmd.fargs[1], { fix = cmd.bang })
  end, { nargs = "?", bang = true, complete = complete_brains, desc = "Rebuild the atlas and report problems" })
end

return M
