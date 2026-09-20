-- The atlas as the editor sees it: a rebuild, and its problems in the
-- quickfix list.
local M = {}

local atlas = require("memoria.modules.atlas")
local message = require("memoria.ui.message")
local ui_brain = require("memoria.ui.brain")

--- Rebuild a brain's atlas and report what is wrong in the quickfix list,
--- which opens only when there is something in it.
---@param brain_name? string Brain name, default: resolved (see ui/brain.resolve)
---@param opts? { fix?: boolean } fix: write missing inverses and backfill blocks first
function M.rebuild_atlas(brain_name, opts)
  ui_brain.resolve(brain_name, function(target)
    local result, err = atlas.rebuild_atlas(target.name, opts)
    if not result then
      return message.error(message.in_brain(target.name, err --[[@as string]]))
    end

    local items = {}
    for _, problem in ipairs(atlas.locate_problems(target, result.problems)) do
      table.insert(items, { filename = problem.file, lnum = problem.line, text = problem.text })
    end

    vim.fn.setqflist({}, " ", { title = ("memoria: (%s) atlas"):format(target.name), items = items })
    message.info(
      message.in_brain(
        target.name,
        ("%d engrams, %d problems"):format(vim.tbl_count(result.atlas.engrams), #result.problems)
      )
    )
    if #items > 0 then
      vim.cmd.copen()
    end
  end)
end

return M
