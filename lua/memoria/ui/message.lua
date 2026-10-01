-- What memoria says out loud, and what it asks: every notification, the brain
-- it is about, and the one-line prompt.
local M = {}

-- What input() answers on <Esc>; typed input cannot hold a line break.
local CANCELLED = "\n"

--- Ask for a value; nil when cancelled, with <Esc> or <C-c>.
---@param prompt string What to ask, already brain-named
---@param default? string Filled in, so leaving it alone keeps it
---@return string? answer
function M.ask(prompt, default)
  local ok, value = pcall(vim.fn.input, { prompt = prompt, default = default or "", cancelreturn = CANCELLED })
  if not ok or value == nil or value == CANCELLED then
    return nil
  end
  return value
end

--- Say something.
---@param text string Already brain-named where a brain is involved
function M.info(text)
  vim.notify("memoria: " .. text)
end

--- Say something that needs attention but is not a failure.
---@param text string
function M.warn(text)
  vim.notify("memoria: " .. text, vim.log.levels.WARN)
end

--- Say why something did not happen.
---@param text string
function M.error(text)
  vim.notify("memoria: " .. text, vim.log.levels.ERROR)
end

--- Choose one of a brain's fields: the one given, refused when it is not
--- among them; the only one; or one picked.
---@param brain_name string
---@param fields string[] The fields to choose from
---@param given? string A field already named
---@param labels { kind: string, prompt: string } kind: as in "no concept field", prompt: the picker's
---@param run fun(field: string) Called once chosen
function M.pick_field(brain_name, fields, given, labels, run)
  if given then
    if not vim.tbl_contains(fields, given) then
      return M.error(M.in_brain(brain_name, ("no %s field '%s'"):format(labels.kind, given)))
    end
    return run(given)
  elseif #fields == 0 then
    return M.warn(M.in_brain(brain_name, ("no %s fields configured"):format(labels.kind)))
  elseif #fields == 1 then
    return run(fields[1])
  end

  vim.ui.select(fields, { prompt = M.in_brain(brain_name, labels.prompt) }, function(choice)
    if choice then
      run(choice)
    end
  end)
end

--- Name the brain a message is about, e.g. "(work) Engram title: ". Which
--- brain was resolved (|memoria-brains|) is not obvious from the buffer a
--- command was run in, so everything a brain-scoped feature says goes through
--- this.
---@param name string Brain name
---@param text string
---@return string
function M.in_brain(name, text)
  return ("(%s) %s"):format(name, text)
end

return M
