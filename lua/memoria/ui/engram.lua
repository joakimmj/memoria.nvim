-- Creating an engram from the editor: choose what the filename needs, ask for
-- the title, then open the file.
local M = {}

local config = require("memoria.config")
local engram = require("memoria.modules.engram")
local message = require("memoria.ui.message")
local ui_brain = require("memoria.ui.brain")
local ui_concept = require("memoria.ui.concept")

--- Ask for the title until it can be a filename, then create and open.
---@param target memoria.Brain
---@param opts memoria.CreateEngramOpts
local function ask_title(target, opts)
  local prompt = message.in_brain(target.name, "Engram title: ")
  local title = opts.title

  while true do
    title = message.ask(prompt, title)
    if not title or vim.trim(title) == "" then
      return
    end

    local new, err, code = engram.create_engram(target.name, vim.tbl_extend("force", opts, { title = title }))
    if new then
      vim.cmd.edit(vim.fn.fnameescape(new.path))
      return vim.api.nvim_win_set_cursor(0, new.cursor)
    end

    -- Only a title the user can fix is worth asking about again.
    if code == "collision" then
      prompt = message.in_brain(target.name, err .. ", edit title: ")
    elseif code == "empty_slug" then
      prompt = message.in_brain(target.name, "Title needs a letter or digit: ")
    else
      return message.error(message.in_brain(target.name, err --[[@as string]]))
    end
  end
end

--- Create an engram in a brain and open it, asking for whatever the brain's
--- filename needs and for the title.
---@param brain_name? string Brain name, default: resolved (see ui/brain.resolve)
---@param opts? memoria.CreateEngramOpts
function M.create_engram(brain_name, opts)
  opts = opts or {}

  ui_brain.resolve(brain_name, function(target)
    local cfg = config.load_brain_config(target.location)

    -- The concept is chosen before the title, so re-asking a title that
    -- collides never asks for the concept again.
    if cfg.engrams.filename.prefix == "concept" and not opts.concept then
      return ui_concept.pick_or_create(target, { prompt = "Filename concept" }, function(chosen)
        ask_title(target, vim.tbl_extend("force", opts, { concept = chosen.name }))
      end)
    end
    ask_title(target, opts)
  end)
end

return M
