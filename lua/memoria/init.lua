local M = {}

local config = require("memoria.config")
local md_drafting = require("memoria.lib.md-drafting")

M.brain = require("memoria.modules.brain")
M.engram = require("memoria.modules.engram")

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
