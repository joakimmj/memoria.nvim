-- Creating an engram from the editor: ask for the title, then open the file.
local M = {}

local engram = require("memoria.modules.engram")
local message = require("memoria.ui.message")
local ui_brain = require("memoria.ui.brain")

--- Ask for a value; nil when cancelled.
---@param prompt string
---@param default? string
---@return string?
local function ask(prompt, default)
  local ok, value = pcall(vim.fn.input, prompt, default or "")
  return ok and value or nil
end

--- Create an engram in a brain and open it, asking for the title and asking
--- again when the answer cannot be a filename.
---@param brain_name? string Brain name, default: resolved (see ui/brain.resolve)
---@param opts? memoria.CreateEngramOpts
function M.create_engram(brain_name, opts)
  opts = opts or {}

  ui_brain.resolve(brain_name, function(target)
    local prompt = message.in_brain(target.name, "Engram title: ")
    local title = opts.title

    while true do
      title = ask(prompt, title)
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
  end)
end

return M
