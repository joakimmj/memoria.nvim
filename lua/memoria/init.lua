local M = {}

local config = require("memoria.config")
local md_drafting = require("memoria.lib.md-drafting")

-- The interactive layer: what the :Mia* commands call, and what a keymap
-- binds to. The headless functions behind them are under M.core.
M.atlas = require("memoria.ui.atlas")
M.brain = require("memoria.ui.brain")
M.engram = require("memoria.ui.engram")
M.synapse = require("memoria.ui.synapse")

--- Every feature without its prompts, pickers and buffers: given all its
--- arguments each one answers `result` or `nil, err`. See |memoria-api|.
M.core = {
  atlas = require("memoria.modules.atlas"),
  brain = require("memoria.modules.brain"),
  engram = require("memoria.modules.engram"),
  synapse = require("memoria.modules.synapse"),
}

--- Check the dependency, store options and create commands.
---@param opts? table Options, see |memoria-config|
function M.setup(opts)
  if not md_drafting.available() then
    vim.notify(
      "memoria.nvim requires md-drafting.nvim (with its api table) — add it as a dependency and restart",
      vim.log.levels.ERROR
    )
    return
  end

  config.options = opts or {}

  if config.get().add_commands then
    require("memoria.commands").create()
  end
end

return M
