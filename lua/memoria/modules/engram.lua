-- Creating engrams: filename, generated header, prose template.
local M = {}

local brain = require("memoria.modules.brain")
local config = require("memoria.config")
local date = require("memoria.lib.date")
local synapse = require("memoria.lib.synapse")

---@class memoria.AddEngramOpts
---@field title? string Seeds the title prompt

--- Filename for a slug under the configured prefix.
---@param cfg memoria.Config Brain config
---@param slug string User-typed slug
---@param time? integer Epoch seconds, default now
---@return string? filename Nil when the prefix mode is unsupported
---@return string? err Why not
function M.filename(cfg, slug, time)
  local opts = cfg.engrams.filename
  local prefix = opts.prefix or "none"

  if prefix == "date" then
    return date.format(cfg.engrams.date_format, time) .. opts.separator .. slug .. ".md"
  elseif prefix == "none" then
    return slug .. ".md"
  end
  return nil, ("filename prefix '%s' is not supported"):format(prefix)
end

-- Characters no filename may hold on common filesystems.
local UNSAFE = '[/\\:*?"<>|]'

--- Filename-safe slug from a title: lowercased, whitespace to `separator`.
---@param title string e.g. "Note about Java"
---@param separator string e.g. "_"
---@return string slug e.g. "note_about_java"; "" when nothing usable is left
function M.slugify(title, separator)
  local sep = vim.pesc(separator)
  local slug = vim.fn.tolower(vim.trim(title)):gsub(UNSAFE, ""):gsub("%s+", separator)

  -- Repeated separators, and separators or dots at either end.
  slug = slug:gsub(sep .. "+", separator)
  local edge = "[%." .. sep .. "]"
  return (slug:gsub("^" .. edge .. "+", ""):gsub(edge .. "+$", ""))
end

--- Frontmatter and SYNAPSES block, straight from config.
---@param cfg memoria.Config Brain config
---@return string[] lines
function M.header(cfg)
  local lines = { "---" }
  for _, name in ipairs(synapse.field_names(cfg.synapses, "concept")) do
    table.insert(lines, name .. ": []")
  end
  table.insert(lines, "---")

  return synapse.write_synapse_block(lines, { synapses = {} }, cfg.synapses)
end

--- Expand a content template.
---@param template string With %title%, %date%, %cursor%
---@param vars { title: string, date: string }
---@return string[] lines Rendered, %cursor% stripped
---@return integer[] cursor { row, col }: 1-indexed row, 0-indexed col
function M.render_template(template, vars)
  -- Function replacements, so "%" in a value is not a pattern escape.
  local text = template
    :gsub("%%title%%", function()
      return vars.title
    end)
    :gsub("%%date%%", function()
      return vars.date
    end)

  local lines, cursor
  local at = text:find("%cursor%", 1, true)
  if at then
    local before = text:sub(1, at - 1)
    local row = select(2, before:gsub("\n", "")) + 1
    local col = #before - (before:match(".*\n()") or 1) + 1
    lines = vim.split(before .. text:sub(at + #"%cursor%"), "\n", { plain = true })
    cursor = { row, col }
  else
    lines = vim.split(text, "\n", { plain = true })
    cursor = { #lines, #lines[#lines] }
  end

  return lines, cursor
end

--- Ask for a value; nil when cancelled.
---@param message string
---@param default? string
---@return string?
local function prompt(message, default)
  local ok, value = pcall(vim.fn.input, message, default or "")
  return ok and value or nil
end

--- Create an engram in a brain and open it.
---@param brain_name? string Default: resolved (see brain.resolve)
---@param opts? memoria.AddEngramOpts
function M.add_engram(brain_name, opts)
  opts = opts or {}

  brain.resolve(brain_name, function(target)
    local cfg = config.load_brain_config(target.location)

    local _, unsupported = M.filename(cfg, "")
    if unsupported then
      vim.notify("memoria: " .. unsupported, vim.log.levels.ERROR)
      return
    end

    -- Every prompt names its brain: which one a command resolved to (§2.2) is
    -- not obvious from the buffer it was run in.
    local in_brain = ("(%s) "):format(target.name)
    local message = in_brain .. "Engram title: "
    local title = opts.title
    local filename
    while true do
      title = prompt(message, title)
      if not title or vim.trim(title) == "" then
        return
      end

      local slug = M.slugify(title, cfg.engrams.filename.separator)
      filename = M.filename(cfg, slug) --[[@as string]]
      if slug == "" then
        message = in_brain .. "Title needs a letter or digit: "
      elseif vim.uv.fs_stat(target.location .. "/" .. filename) then
        message = in_brain .. filename .. " exists, edit title: "
      else
        break
      end
    end

    ---@cast title string
    local header = M.header(cfg)
    local prose, cursor = M.render_template(cfg.engrams.content_template, {
      title = vim.trim(title),
      date = date.format(cfg.engrams.date_format),
    })

    local path = target.location .. "/" .. filename
    if vim.fn.writefile(vim.list_extend(vim.deepcopy(header), prose), path) ~= 0 then
      vim.notify("memoria: could not write " .. path, vim.log.levels.ERROR)
      return
    end

    vim.cmd.edit(vim.fn.fnameescape(path))
    vim.api.nvim_win_set_cursor(0, { #header + cursor[1], cursor[2] })
  end)
end

return M
