-- What memoria says out loud: every notification, and the brain it is about.
local M = {}

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
