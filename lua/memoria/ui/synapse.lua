-- Linking engrams from the editor: pick the field, pick the target.
local M = {}

local atlas = require("memoria.modules.atlas")
local config = require("memoria.config")
local message = require("memoria.ui.message")
local synapse = require("memoria.modules.synapse")
local synapse_lib = require("memoria.lib.synapse")

--- Link the current engram to another through a synapse field, writing the
--- inverse on the other one. Asks for whatever `opts` leaves out.
---@param opts? { source?: string, target?: string, field?: string }
function M.add_synapse(opts)
  opts = opts or {}

  local source = opts.source or vim.api.nvim_buf_get_name(0)
  local located, err = synapse.locate(source)
  if not located then
    return message.error(err --[[@as string]])
  end

  local target_brain = located.brain
  local cfg = config.load_brain_config(target_brain.location)

  ---@param field string
  ---@param target string Engram filename
  local function finish(field, target)
    local added, add_err = synapse.add_synapse({ source = source, field = field, target = target })
    if not added then
      return message.error(message.in_brain(target_brain.name, add_err --[[@as string]]))
    end
    message.info(message.in_brain(target_brain.name, ("%s %s → %s"):format(added.source, added.field, added.target)))
  end

  ---@param field string
  local function pick_target(field)
    if opts.target then
      return finish(field, opts.target)
    end

    local current, refresh_err = atlas.refresh(target_brain)
    if not current then
      return message.error(message.in_brain(target_brain.name, refresh_err --[[@as string]]))
    end

    local names = vim.tbl_filter(function(name)
      return name ~= located.filename
    end, vim.tbl_keys(current.engrams))
    table.sort(names)
    if #names == 0 then
      return message.warn(message.in_brain(target_brain.name, "no other engrams to link"))
    end

    vim.ui.select(names, {
      prompt = message.in_brain(target_brain.name, field .. ":"),
      format_item = function(name)
        local title = current.engrams[name].title
        return title == (name:gsub("%.md$", "")) and name or ("%s (%s)"):format(title, name)
      end,
    }, function(choice)
      if choice then
        finish(field, choice)
      end
    end)
  end

  local fields = synapse_lib.field_names(cfg.synapses, "engram")
  if opts.field then
    if not vim.tbl_contains(fields, opts.field) then
      return message.error(message.in_brain(target_brain.name, ("no engram field '%s'"):format(opts.field)))
    end
    pick_target(opts.field)
  elseif #fields == 0 then
    message.warn(message.in_brain(target_brain.name, "no engram fields configured"))
  elseif #fields == 1 then
    pick_target(fields[1])
  else
    vim.ui.select(fields, { prompt = message.in_brain(target_brain.name, "Synapse field:") }, function(choice)
      if choice then
        pick_target(choice)
      end
    end)
  end
end

return M
