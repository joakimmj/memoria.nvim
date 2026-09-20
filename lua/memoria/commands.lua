-- The :Mia* user commands, created by setup() unless `add_commands` is off.
-- Each one is a wrapper over the matching ui/ function, which is what a keymap
-- binds to instead.
local M = {}

local brain = require("memoria.modules.brain")
local config = require("memoria.config")
local synapse_lib = require("memoria.lib.synapse")
local ui_atlas = require("memoria.ui.atlas")
local ui_brain = require("memoria.ui.brain")
local ui_engram = require("memoria.ui.engram")
local ui_synapse = require("memoria.ui.synapse")

--- Complete brain names.
---@param lead string Typed so far
---@return string[]
local function complete_brains(lead)
  return vim.tbl_filter(function(name)
    return vim.startswith(name, lead)
  end, brain.names())
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
    ui_brain.add(cmd.fargs[1], cmd.fargs[2])
  end, { nargs = "+", complete = "dir", desc = "Register a folder as a brain" })

  create("MiaBrainDeregister", function(cmd)
    ui_brain.deregister(cmd.args)
  end, { nargs = "?", complete = complete_brains, desc = "Remove a brain from the registry" })

  create("MiaBrainList", ui_brain.print_list, { nargs = 0, desc = "List registered brains" })

  create("MiaBrainSwitch", function(cmd)
    ui_brain.switch(cmd.args)
  end, { nargs = "?", complete = complete_brains, desc = "Set the active brain" })

  create("MiaBrainConfig", function(cmd)
    ui_brain.open_config(cmd.fargs[1])
  end, { nargs = "?", complete = complete_brains, desc = "Open a brain's .mia_dna.json" })

  create("MiaEngramAdd", function(cmd)
    ui_engram.add_engram(cmd.fargs[1])
  end, { nargs = "?", complete = complete_brains, desc = "Create an engram" })

  create("MiaSynapseAdd", function(cmd)
    ui_synapse.add_synapse({ field = cmd.fargs[1] })
  end, { nargs = "?", complete = complete_engram_fields, desc = "Link the current engram to another" })

  create("MiaAtlasRebuild", function(cmd)
    ui_atlas.rebuild_atlas(cmd.fargs[1], { fix = cmd.bang })
  end, { nargs = "?", bang = true, complete = complete_brains, desc = "Rebuild the atlas and report problems" })
end

return M
