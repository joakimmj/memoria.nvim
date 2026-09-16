-- The :Mia* user commands, created by setup() when `add_commands` is on.
local M = {}

local brain = require("memoria.modules.brain")
local engram = require("memoria.modules.engram")

--- Complete brain names.
---@param lead string Typed so far
---@return string[]
local function complete_brains(lead)
  return vim.tbl_filter(function(name)
    return vim.startswith(name, lead)
  end, brain.names())
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
    if brain.deregister(cmd.args) then
      vim.notify(("memoria: deregistered brain '%s'"):format(cmd.args))
    end
  end, { nargs = 1, complete = complete_brains, desc = "Remove a brain from the registry" })

  create("MiaBrainList", brain.print_list, { nargs = 0, desc = "List registered brains" })

  create("MiaBrainSwitch", function(cmd)
    if brain.switch(cmd.args) then
      vim.notify(("memoria: active brain '%s'"):format(cmd.args))
    end
  end, { nargs = 1, complete = complete_brains, desc = "Set the active brain" })

  create("MiaBrainCurrent", brain.print_current, { nargs = 0, desc = "Show the brain commands would act on" })

  create("MiaBrainConfig", function(cmd)
    brain.open_config(cmd.fargs[1])
  end, { nargs = "?", complete = complete_brains, desc = "Open a brain's .mia_dna.json" })

  create("MiaEngramAdd", function(cmd)
    engram.add_engram(cmd.fargs[1])
  end, { nargs = "?", complete = complete_brains, desc = "Create an engram" })
end

return M
