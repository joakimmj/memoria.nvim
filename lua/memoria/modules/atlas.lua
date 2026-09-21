-- The atlas: a brain's derived index in `.mia_atlas.json`, rebuildable from
-- its engrams at any time. See |memoria-atlas|.
local M = {}

local brain = require("memoria.modules.brain")
local concept = require("memoria.lib.concept")
local config = require("memoria.config")
local file = require("memoria.lib.file")
local json = require("memoria.lib.json")
local md_drafting = require("memoria.lib.md-drafting")
local synapse = require("memoria.lib.synapse")

---@class memoria.AtlasEngram
---@field title string First heading, or the filename's stem
---@field synapses table<string, string[]> Linked filenames by field
---@field links string[] Engrams linked from the body
---@field error? string Why the frontmatter could not be read
---@field modified string File mtime, ISO 8601 UTC
---@field hash string Content hash
---@field [string] any Concept fields, each a list of values

---@class memoria.AtlasTask
---@field engram string Filename
---@field line integer 1-indexed row
---@field text string Task text, marker left out

---@class memoria.Atlas
---@field config string Fingerprint of the config the entries were parsed with
---@field concept_registry string Fingerprint of the registry the derived maps came from
---@field engrams table<string, memoria.AtlasEngram> By filename
---@field backlinks table<string, string[]> Filename to the engrams linking it
---@field concepts table<string, string[]> Concept name to the engrams naming it
---@field concepts_by_type table<string, string[]> Registered concepts by type, sorted
---@field tasks { not_done: memoria.AtlasTask[], done: memoria.AtlasTask[] }

---@alias memoria.AtlasProblemKind
---| "broken_synapse" # A synapse pointing at an engram that is not there
---| "missing_inverse" # A synapse the other engram does not answer
---| "broken_link" # A body link pointing at an engram that is not there
---| "unreadable_frontmatter" # Frontmatter that could not be parsed
---| "undeclared_concept" # A concept an engram names that the registry does not answer to
---| "orphaned_concept" # A registered concept no engram names

---@class memoria.AtlasProblem
---@field engram? string Filename, when an engram is what is wrong
---@field concept? string Concept name, when the registry is what is wrong
---@field kind memoria.AtlasProblemKind What is wrong
---@field text string What is wrong, in words
---@field needle? string Text on the offending line, to find its row
---@field repair? { source: string, target: string, field: string } Missing inverse to write

---@class memoria.LocatedProblem : memoria.AtlasProblem
---@field file string Absolute path of the engram, or of the concept registry
---@field line integer 1-indexed row, 1 when no line says so

---@class memoria.RebuildResult
---@field atlas memoria.Atlas The atlas as rebuilt
---@field problems memoria.AtlasProblem[] What is still wrong

-- Entry keys a concept field cannot be stored under.
local RESERVED = { title = true, synapses = true, links = true, error = true, modified = true, hash = true }

--- Where a brain's atlas lives.
---@param location string Absolute brain location
---@return string path
function M.path(location)
  return location .. "/.mia_atlas.json"
end

--- An atlas with nothing in it.
---@return memoria.Atlas
local function empty()
  return {
    config = "",
    concept_registry = "",
    engrams = {},
    backlinks = {},
    concepts = {},
    concepts_by_type = {},
    tasks = { not_done = {}, done = {} },
  }
end

--- A frontmatter value as a list: nil and "" are empty, a scalar is one item.
---@param value any Frontmatter field value
---@return string[]
local function as_list(value)
  if type(value) == "table" then
    return vim.tbl_filter(function(item)
      return type(item) == "string"
    end, value)
  elseif type(value) == "string" and value ~= "" then
    return { value }
  end
  return {}
end

--- The engram filename a link points at, when it points at one in this brain.
--- Brains are flat: a link with a folder in it, or a scheme, is not an engram.
---@param path string Link destination
---@return string? filename
function M.engram_target(path)
  if path:match("^%a[%w+.-]*:") then
    return nil
  end

  local target = path:gsub("#.*$", ""):gsub("^%./", "")
  if target:find("/", 1, true) or not target:match("%.md$") then
    return nil
  end
  return target
end

--- Index one engram. Pure: lines in, entry and tasks out.
---@param filename string e.g. "20260801_project-x.md"
---@param lines string[] Engram lines
---@param cfg memoria.Config Brain config
---@return memoria.AtlasEngram entry Without `modified`/`hash`
---@return memoria.AtlasTask[]|table tasks With a `state` each
function M.parse_engram(filename, lines, cfg)
  local fields, fm_end, err = md_drafting.syntax.parse_frontmatter(lines)
  local entry = { title = (filename:gsub("%.md$", "")), synapses = {}, links = {} }
  if err then
    entry.error = err
  end

  for _, name in ipairs(synapse.field_names(cfg.synapses, "concept")) do
    if not RESERVED[name] then
      entry[name] = as_list(fields and fields[name])
    end
  end

  -- Blanking the block's body keeps every row where it is, so task rows
  -- stay true while nothing in the block is read as body.
  local block = synapse.parse_synapse_block(lines)
  local body = lines
  if block then
    local blanks = {}
    for _ = 1, #md_drafting.section.get(lines, "SYNAPSES") do
      table.insert(blanks, "")
    end
    body = md_drafting.section.set(lines, "SYNAPSES", blanks)

    for name, values in pairs(block) do
      entry.synapses[name] = vim.tbl_map(function(value)
        return M.engram_target(value.path) or value.path
      end, values)
    end
  end

  local tasks, seen, titled = {}, {}, false
  for row = (fm_end or 0) + 1, #body do
    local line = body[row]

    if not titled then
      local level, text = md_drafting.syntax.parse_heading(line)
      if level and text ~= "" then
        entry.title, titled = text, true
      end
    end

    for _, link in ipairs(md_drafting.syntax.parse_links(line)) do
      local target = M.engram_target(link.path)
      if target and not seen[target] then
        seen[target] = true
        table.insert(entry.links, target)
      end
    end

    local state = md_drafting.syntax.parse_checkbox(line, cfg.engrams.task_markers)
    if state then
      local _, _, text = md_drafting.syntax.parse_list_item(line)
      table.insert(tasks, { engram = filename, line = row, text = text, state = state })
    end
  end

  return entry, tasks
end

--- The config an atlas depends on, so a change to it re-parses every engram.
---@param cfg memoria.Config
---@return string
local function fingerprint(cfg)
  return vim.fn.sha256(vim.inspect({ cfg.synapses, cfg.engrams.task_markers })):sub(1, 16)
end

--- Read a brain's atlas; a missing or unreadable one is empty.
---@param location string Absolute brain location
---@return memoria.Atlas
local function read(location)
  local path = M.path(location)
  if vim.fn.filereadable(path) == 0 then
    return empty()
  end

  local atlas = json.read(path)
  if type(atlas) ~= "table" or type(atlas.engrams) ~= "table" then
    return empty()
  end
  atlas.tasks = type(atlas.tasks) == "table" and atlas.tasks or {}
  -- An atlas written before concepts had a registry: re-derive once.
  atlas.concept_registry = type(atlas.concept_registry) == "string" and atlas.concept_registry or ""
  atlas.concepts_by_type = type(atlas.concepts_by_type) == "table" and atlas.concepts_by_type or {}
  return atlas
end

--- A map for JSON: empty encodes as an object rather than a list.
---@param map table
---@return table
local function object(map)
  return next(map) == nil and vim.empty_dict() or map
end

--- Write an atlas, maps kept maps however empty.
---@param location string Absolute brain location
---@param atlas memoria.Atlas
---@return boolean? ok
---@return string? err Why it could not be written
local function write(location, atlas)
  local engrams = {}
  for name, entry in pairs(atlas.engrams) do
    engrams[name] = vim.tbl_extend("force", entry, { synapses = object(entry.synapses) })
  end

  local ok, err = json.write(M.path(location), {
    config = atlas.config,
    concept_registry = atlas.concept_registry,
    engrams = object(engrams),
    backlinks = object(atlas.backlinks),
    concepts = object(atlas.concepts),
    concepts_by_type = object(atlas.concepts_by_type),
    tasks = atlas.tasks,
  })
  if not ok then
    return nil, err
  end
  return true
end

--- Append to a list in a map, once.
---@param map table<string, string[]>
---@param key string
---@param value string
local function add_to(map, key, value)
  map[key] = map[key] or {}
  if not vim.tbl_contains(map[key], value) then
    table.insert(map[key], value)
  end
end

--- Recompute `backlinks`, `concepts` and `concepts_by_type` from the entries
--- and the registry. A mention is indexed under the concept it resolves to, so
--- an engram writing an alias still counts for the concept itself.
---@param atlas memoria.Atlas
---@param cfg memoria.Config
---@param registry memoria.ConceptRegistry
local function derive(atlas, cfg, registry)
  atlas.backlinks, atlas.concepts = {}, {}
  atlas.concepts_by_type = concept.by_type(registry)
  local names = concept.index(registry)
  local concept_fields = synapse.field_names(cfg.synapses, "concept")

  for name, entry in pairs(atlas.engrams) do
    for _, targets in pairs(entry.synapses) do
      for _, target in ipairs(targets) do
        add_to(atlas.backlinks, target, name)
      end
    end
    for _, target in ipairs(entry.links) do
      add_to(atlas.backlinks, target, name)
    end
    for _, field in ipairs(concept_fields) do
      for _, mention in ipairs(entry[field] or {}) do
        add_to(atlas.concepts, names[mention] or mention, name)
      end
    end
  end

  for _, map in ipairs({ atlas.backlinks, atlas.concepts }) do
    for _, list in pairs(map) do
      table.sort(list)
    end
  end
end

--- File mtime as ISO 8601 UTC.
---@param path string
---@return string
local function modified(path)
  local stat = vim.uv.fs_stat(path)
  return tostring(os.date("!%Y-%m-%dT%H:%M:%SZ", stat and stat.mtime.sec or 0))
end

--- Bring a brain's atlas up to date with its files: new and changed engrams
--- are parsed, vanished ones dropped, unchanged ones kept as they are. Written
--- only when something changed.
---@param target memoria.Brain
---@param opts? { full?: boolean } full: parse every engram, as if no atlas existed
---@return memoria.Atlas? atlas
---@return string? err Why the brain could not be read
function M.refresh(target, opts)
  opts = opts or {}
  if vim.fn.isdirectory(target.location) == 0 then
    return nil, "missing folder " .. target.location
  end

  local cfg = config.load_brain_config(target.location)
  local registry = concept.read(target.location)
  local old = opts.full and empty() or read(target.location)
  local atlas = empty()
  atlas.config = fingerprint(cfg)
  atlas.concept_registry = concept.hash(registry)

  -- A config change re-parses every engram; a registry change cannot, since it
  -- says nothing about how an engram is written — only about what is derived.
  local stale = atlas.config ~= old.config
  local changed = stale
    or atlas.concept_registry ~= old.concept_registry
    or vim.fn.filereadable(M.path(target.location)) == 0

  local parsed = {}
  for name, kind in vim.fs.dir(target.location) do
    if kind == "file" and name:match("%.md$") then
      local path = target.location .. "/" .. name
      local ok, lines = pcall(vim.fn.readfile, path)
      if ok then
        local hash = vim.fn.sha256(table.concat(lines, "\n")):sub(1, 16)
        local previous = old.engrams[name]
        if previous and previous.hash == hash and not stale then
          atlas.engrams[name] = previous
        else
          local entry, tasks = M.parse_engram(name, lines, cfg)
          entry.hash, entry.modified = hash, modified(path)
          atlas.engrams[name], parsed[name] = entry, tasks
          changed = true
        end
      end
    end
  end

  for name in pairs(old.engrams) do
    changed = changed or atlas.engrams[name] == nil
  end
  if not changed then
    return old
  end

  -- Tasks of kept engrams carry over; re-parsed ones bring their own.
  for state, tasks in pairs(old.tasks) do
    for _, task in ipairs(tasks) do
      if atlas.engrams[task.engram] and not parsed[task.engram] then
        atlas.tasks[state] = atlas.tasks[state] or {}
        table.insert(atlas.tasks[state], task)
      end
    end
  end
  for _, tasks in pairs(parsed) do
    for _, task in ipairs(tasks) do
      atlas.tasks[task.state] = atlas.tasks[task.state] or {}
      table.insert(atlas.tasks[task.state], { engram = task.engram, line = task.line, text = task.text })
    end
  end
  for _, tasks in pairs(atlas.tasks) do
    table.sort(tasks, function(a, b)
      return a.engram == b.engram and a.line < b.line or a.engram < b.engram
    end)
  end

  derive(atlas, cfg, registry)
  local ok, err = write(target.location, atlas)
  if not ok then
    return nil, err
  end
  return atlas
end

--- Everything wrong with a brain's links and concepts, in filename order and
--- then by concept. Concepts are only reported against a registry that holds
--- something: a brain that has declared nothing is not told that everything it
--- writes is undeclared.
---@param atlas memoria.Atlas
---@param cfg memoria.Config Brain config
---@param registry? memoria.ConceptRegistry Default: none, and no concept is reported
---@return memoria.AtlasProblem[]
function M.check(atlas, cfg, registry)
  registry = registry or {}
  local declared = next(registry) ~= nil
  local names = declared and concept.index(registry) or {}
  local concept_fields = synapse.field_names(cfg.synapses, "concept")

  local problems = {}
  local engram_names = vim.tbl_keys(atlas.engrams)
  table.sort(engram_names)

  for _, name in ipairs(engram_names) do
    local entry = atlas.engrams[name]
    if entry.error then
      table.insert(
        problems,
        { engram = name, kind = "unreadable_frontmatter", text = "unreadable frontmatter: " .. entry.error }
      )
    end

    local fields = vim.tbl_keys(entry.synapses)
    table.sort(fields)
    for _, field in ipairs(fields) do
      local needle = ("**%s:**"):format(field)
      local inverse = (cfg.synapses[field] or {}).inverse
      local inverse_field = inverse and cfg.synapses[inverse]
      if not (inverse_field and inverse_field.target == "engram") then
        inverse = nil
      end

      for _, target in ipairs(entry.synapses[field]) do
        local linked = atlas.engrams[target]
        if not linked then
          table.insert(problems, {
            engram = name,
            kind = "broken_synapse",
            needle = needle,
            text = ("broken synapse: %s → %s"):format(field, target),
          })
        elseif inverse and not vim.tbl_contains(linked.synapses[inverse] or {}, name) then
          table.insert(problems, {
            engram = name,
            kind = "missing_inverse",
            needle = needle,
            text = ("missing inverse: %s has no %s → %s"):format(target, inverse, name),
            repair = { source = name, target = target, field = field },
          })
        end
      end
    end

    for _, target in ipairs(entry.links) do
      if not atlas.engrams[target] then
        table.insert(problems, {
          engram = name,
          kind = "broken_link",
          needle = "](" .. target,
          text = "broken link: " .. target,
        })
      end
    end

    if declared then
      for _, field in ipairs(concept_fields) do
        for _, mention in ipairs(entry[field] or {}) do
          if not names[mention] then
            table.insert(problems, {
              engram = name,
              concept = mention,
              kind = "undeclared_concept",
              -- The frontmatter key, so the row is the field's own line rather
              -- than wherever the text happens to appear in the prose.
              needle = field .. ":",
              text = ("undeclared concept: %s in %s"):format(mention, field),
            })
          end
        end
      end
    end
  end

  local registered = vim.tbl_keys(registry)
  table.sort(registered)
  for _, name in ipairs(registered) do
    local named = false
    for _, mention in ipairs(concept.mentions(name, registry[name])) do
      named = named or #(atlas.concepts[mention] or {}) > 0
    end
    if not named then
      table.insert(problems, {
        concept = name,
        kind = "orphaned_concept",
        -- How both json.write and a hand-written file spell the key.
        needle = ('"%s"'):format(name),
        text = "orphaned concept: " .. name,
      })
    end
  end

  return problems
end

--- Write every missing inverse, and regenerate every existing SYNAPSES block
--- from config so fields added since it was written get their line.
---@param target memoria.Brain
---@param problems memoria.AtlasProblem[]
local function fix(target, problems)
  local synapse_module = require("memoria.modules.synapse")
  for _, problem in ipairs(problems) do
    local repair = problem.repair
    if repair then
      synapse_module.connect(target, repair.source, repair.target, repair.field)
    end
  end

  local cfg = config.load_brain_config(target.location)
  for name, kind in vim.fs.dir(target.location) do
    if kind == "file" and name:match("%.md$") then
      local path = target.location .. "/" .. name
      local lines = file.read_lines(path)
      if lines and synapse.parse_synapse_block(lines) then
        local updated = synapse.update(lines, cfg.synapses, function() end)
        if updated and not vim.deep_equal(updated, lines) then
          file.write_lines(path, updated)
        end
      end
    end
  end
end

--- Each problem with the file and row it sits on: the first line holding its
--- `needle`, or row 1. Every engram named is read once.
---@param target memoria.Brain
---@param problems memoria.AtlasProblem[]
---@return memoria.LocatedProblem[] located In the order given
function M.locate_problems(target, problems)
  local lines_of = {}
  local located = {}

  for _, problem in ipairs(problems) do
    -- A problem naming no engram is the registry's, not an engram's.
    local path = problem.engram and (target.location .. "/" .. problem.engram) or concept.path(target.location)
    if lines_of[path] == nil then
      lines_of[path] = file.read_lines(path) or {}
    end

    local row = 1
    if problem.needle then
      for index, line in ipairs(lines_of[path]) do
        if line:find(problem.needle, 1, true) then
          row = index
          break
        end
      end
    end
    table.insert(located, vim.tbl_extend("force", problem, { file = path, line = row }))
  end

  return located
end

--- Rebuild a brain's atlas from scratch and check it. Reporting is the view's
--- (the quickfix list) and the CLI's (JSON).
---@param brain_name? string Default: resolved (see brain.resolve)
---@param opts? { fix?: boolean } fix: write missing inverses and backfill blocks first
---@return memoria.RebuildResult? result
---@return string? err
function M.rebuild_atlas(brain_name, opts)
  opts = opts or {}

  local target, err = brain.resolve(brain_name)
  if not target then
    return nil, err
  end

  local atlas, refresh_err = M.refresh(target, { full = true })
  if not atlas then
    return nil, refresh_err
  end

  local cfg = config.load_brain_config(target.location)
  local registry = concept.read(target.location)
  if opts.fix then
    -- A repair that cannot be written stays in the problems below. Concepts
    -- are left out here: neither kind has a repair to write.
    fix(target, M.check(atlas, cfg))
    atlas = M.refresh(target) --[[@as memoria.Atlas]]
  end

  return { atlas = atlas, problems = M.check(atlas, cfg, registry) }
end

return M
