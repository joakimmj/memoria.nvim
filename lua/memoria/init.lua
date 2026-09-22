local M = {}

local config = require("memoria.config")
local md_drafting = require("memoria.lib.md-drafting")

-- The interactive layer: what the :Mia* commands call, and what a keymap
-- binds to. The headless functions behind them are under M.core.
M.atlas = require("memoria.ui.atlas")
M.brain = require("memoria.ui.brain")
M.concept = require("memoria.ui.concept")
M.engram = require("memoria.ui.engram")
M.synapse = require("memoria.ui.synapse")

--- Every feature without its prompts, pickers and buffers: given all its
--- arguments each one answers `result` or `nil, err`. See |memoria-api|.
M.core = {
  atlas = require("memoria.modules.atlas"),
  brain = require("memoria.modules.brain"),
  concept = require("memoria.modules.concept"),
  engram = require("memoria.modules.engram"),
  synapse = require("memoria.modules.synapse"),
}

--- Check the dependency, store options and create commands.
---@param opts? table Options, see |memoria-config|
---@return boolean? ok
---@return string? err Why memoria did not set up
function M.setup(opts)
  if not md_drafting.available() then
    local err = "memoria.nvim requires md-drafting.nvim (with its api table) — add it as a dependency and restart"
    vim.notify(err, vim.log.levels.ERROR)
    return nil, err
  end

  config.options = opts or {}

  -- A concept field takes the one type it declares, so one declaring none takes
  -- nothing: said once here rather than at every write that then refuses it.
  local untyped = config.untyped_concept_fields(config.get())
  if #untyped > 0 then
    vim.notify(
      ("memoria: concept fields with no concept_type take nothing: %s"):format(table.concat(untyped, ", ")),
      vim.log.levels.WARN
    )
  end

  if config.get().add_commands then
    require("memoria.commands").create()
  end

  -- Last, so a setup that stopped above leaves it false: it is what the CLI
  -- tests to know the user's config really configured memoria.
  config.configured = true
  return true
end

return M
