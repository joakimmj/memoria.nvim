-- The :Mia* user commands, created by setup() unless `add_commands` is off.
-- Each one is a wrapper over the matching ui/ function, which is what a keymap
-- binds to instead.
local M = {}

local brain = require("memoria.modules.brain")
local config = require("memoria.config")
local synapse_lib = require("memoria.lib.synapse")
local ui_atlas = require("memoria.ui.atlas")
local ui_brain = require("memoria.ui.brain")
local ui_concept = require("memoria.ui.concept")
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

--- A completion over the current buffer's brain's fields of one target.
---@param target "engram"|"concept"
---@return fun(lead: string): string[]
local function complete_fields(target)
  return function(lead)
    local current = brain.current()
    if not current then
      return {}
    end

    local fields = config.load_brain_config(current.location).synapses
    return vim.tbl_filter(function(name)
      return vim.startswith(name, lead)
    end, synapse_lib.field_names(fields, target))
  end
end

--- Create every command. Safe to call again.
function M.create()
  local create = vim.api.nvim_create_user_command

  create("MiaBrainRegister", function(cmd)
    ui_brain.register(cmd.fargs[1], cmd.fargs[2])
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

  create("MiaEngramCreate", function(cmd)
    ui_engram.create_engram(cmd.fargs[1])
  end, { nargs = "?", complete = complete_brains, desc = "Create an engram" })

  create("MiaSynapseAttach", function(cmd)
    ui_synapse.attach_synapse({ field = cmd.fargs[1] })
  end, { nargs = "?", complete = complete_fields("engram"), desc = "Link the current engram to another" })

  create("MiaConceptCreate", function(cmd)
    ui_concept.create_concept(cmd.fargs[1])
  end, { nargs = "?", complete = complete_brains, desc = "Create a concept" })

  create("MiaConceptAttach", function(cmd)
    ui_concept.attach_concept({ field = cmd.fargs[1] })
  end, { nargs = "?", complete = complete_fields("concept"), desc = "Put a concept on the current engram" })

  create("MiaConceptEdit", function(cmd)
    ui_concept.set_concept_meta(cmd.fargs[1])
  end, { nargs = "?", complete = complete_brains, desc = "Fill in a concept's meta" })

  create("MiaConceptList", function(cmd)
    ui_concept.print_list(cmd.fargs[1])
  end, { nargs = "?", complete = complete_brains, desc = "List a brain's concepts" })

  create("MiaConceptFill", function(cmd)
    ui_concept.find_undeclared_concepts(cmd.fargs[1])
  end, { nargs = "?", complete = complete_brains, desc = "Declare the concepts nothing answers to" })

  create("MiaAtlasRebuild", function(cmd)
    ui_atlas.rebuild_atlas(cmd.fargs[1], { fix = cmd.bang })
  end, { nargs = "?", bang = true, complete = complete_brains, desc = "Rebuild the atlas and report problems" })
end

return M
