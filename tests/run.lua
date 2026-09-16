-- Assertions over the parts of the plugin that need no window and no cursor.
-- Run from the repository root:
--
--   nvim -l tests/run.lua
--
-- md-drafting.nvim is looked for on the runtimepath and where plugin managers
-- install it. A checkout elsewhere is named as an argument, or in
-- $MD_DRAFTING:
--
--   nvim -l tests/run.lua ~/src/md-drafting.nvim

package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

--- Where md-drafting.nvim is installed.
---@return string dir Plugin root, holding lua/md-drafting/
local function find_md_drafting()
  local data, config_dir = vim.fn.stdpath("data"), vim.fn.stdpath("config")
  local candidates = {
    (_G.arg or {})[1],
    vim.env.MD_DRAFTING,
    -- On the runtimepath already: the plugin is loaded, or in a pack/*/start.
    (vim.api.nvim_get_runtime_file("lua/md-drafting/init.lua", false)[1] or ""):match("^(.*)/lua/"),
    data .. "/lazy/md-drafting.nvim",
    data .. "/site/pack/*/*/md-drafting.nvim",
    config_dir .. "/pack/*/*/md-drafting.nvim",
  }

  for _, candidate in
    ipairs(vim.tbl_filter(function(c)
      return c ~= nil and c ~= ""
    end, candidates))
  do
    for _, dir in ipairs(vim.fn.glob(vim.fn.expand(candidate), false, true)) do
      if vim.fn.filereadable(dir .. "/lua/md-drafting/init.lua") == 1 then
        return dir
      end
    end
  end

  error("md-drafting.nvim not found; pass its directory as an argument or in $MD_DRAFTING")
end

local md_drafting_dir = find_md_drafting()
package.path = ("%s/lua/?.lua;%s/lua/?/init.lua;"):format(md_drafting_dir, md_drafting_dir) .. package.path

-- Keep the registry out of the real data directory.
local scratch = vim.fn.tempname()
vim.fn.mkdir(scratch, "p")
vim.env.XDG_DATA_HOME = scratch .. "/data"

-- Before anything memoria is required: whether md-drafting is already loaded.
local loaded_before = package.loaded["md-drafting"] ~= nil

local brain = require("memoria.modules.brain")
local config = require("memoria.config")
local md_drafting = require("memoria.lib.md-drafting")
local date = require("memoria.lib.date")
local engram = require("memoria.modules.engram")
local json = require("memoria.lib.json")
local synapse = require("memoria.lib.synapse")

local failures = 0
local checks = 0

local function render(value)
  if type(value) ~= "table" then
    return tostring(value)
  end

  local parts = {}
  for key, item in pairs(value) do
    table.insert(parts, ("%s = %s"):format(tostring(key), render(item)))
  end
  table.sort(parts)
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a == b
  end

  for key, value in pairs(a) do
    if not same(value, b[key]) then
      return false
    end
  end
  for key in pairs(b) do
    if a[key] == nil then
      return false
    end
  end
  return true
end

local function check(name, actual, expected)
  checks = checks + 1
  if same(actual, expected) then
    return
  end

  failures = failures + 1
  io.stderr:write(("FAIL  %s\n  expected: %s\n  actual:   %s\n"):format(name, render(expected), render(actual)))
end

-- Swallow notifications, keeping the last one for checks.
local notified
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(message)
  notified = message
end

-- lib: md-drafting

-- Only meaningful in a session that has not loaded md-drafting itself, i.e.
-- `nvim -l`; inside a configured Neovim it may already be on the runtimepath.
if not loaded_before then
  -- Every memoria module is required above; none may have loaded md-drafting.
  check("loading memoria does not load md-drafting", package.loaded["md-drafting"], nil)

  package.preload["md-drafting"] = function()
    error("not installed")
  end
  check("md_drafting unavailable when missing", md_drafting.available(), false)
  package.preload["md-drafting"] = nil
  -- A failed require leaves a sentinel behind; clear it so the real one loads.
  package.loaded["md-drafting"] = nil
end

check("md_drafting available", md_drafting.available(), true)
local api = require("md-drafting").api
for _, group in ipairs({ "syntax", "section" }) do
  for name in pairs(md_drafting[group]) do
    check(("md_drafting.%s.%s wraps a real api function"):format(group, name), type(api[group][name]), "function")
  end
end
for _, path in ipairs(vim.fn.glob("lua/**/*.lua", false, true)) do
  if path ~= "lua/memoria/lib/md-drafting.lua" then
    local source = table.concat(vim.fn.readfile(path), "\n")
    check(
      path .. " reaches md-drafting only through lib/md-drafting",
      source:find('require%("md%-drafting') == nil,
      true
    )
  end
end

-- config: merge

check("merge, maps merge by key", config.merge({ a = { b = 1, c = 2 } }, { a = { c = 3 } }), { a = { b = 1, c = 3 } })
check("merge, lists replace wholesale", config.merge({ l = { 1, 2 } }, { l = { 3 } }), { l = { 3 } })
check("merge, null keeps the default", config.merge({ a = 1 }, { a = vim.NIL }), { a = 1 })
check("merge, new keys added", config.merge({ a = 1 }, { b = 2 }), { a = 1, b = 2 })

local defaults_before = vim.deepcopy(config.defaults)
config.merge(config.defaults, { engrams = { filename = { prefix = "none" } } })
check("merge, defaults untouched", config.defaults, defaults_before)

-- config: tiers

config.options = { engrams = { filename = { separator = "-" } } }
local brain_dir = scratch .. "/work"
vim.fn.mkdir(brain_dir, "p")

local cfg = config.load_brain_config(brain_dir)
check("load_brain_config, no dna", cfg.engrams.filename, { prefix = "date", separator = "-" })

json.write(brain_dir .. "/.mia_dna.json", { engrams = { filename = { prefix = "none" } }, add_commands = true })
cfg = config.load_brain_config(brain_dir)
check("load_brain_config, dna over setup", cfg.engrams.filename, { prefix = "none", separator = "-" })
check("load_brain_config, dna cannot set add_commands", cfg.add_commands, false)

vim.fn.writefile({ "{ not json" }, brain_dir .. "/.mia_dna.json")
notified = nil
cfg = config.load_brain_config(brain_dir)
check("load_brain_config, invalid dna skipped", cfg.engrams.filename, { prefix = "date", separator = "-" })
check(
  "load_brain_config, invalid dna reported",
  notified ~= nil and notified:find(".mia_dna.json", 1, true) ~= nil,
  true
)

vim.fn.delete(brain_dir .. "/.mia_dna.json")
config.options = {}

-- lib: date

local time = os.time({ year = 2026, month = 8, day = 1, hour = 9, min = 5, sec = 7 })
check("date YYYYMMDD", date.format("YYYYMMDD", time), "20260801")
check("date with literals", date.format("YYYY-MM-DD", time), "2026-08-01")
check("date YY", date.format("YY", time), "26")
check("date time tokens", date.format("HH:mm:ss", time), "09:05:07")
check("date literal percent", date.format("%YYYY", time), "%2026")

-- lib: synapse

check("field_names, engram sorted", synapse.field_names(config.defaults.synapses, "engram"), { "down", "up" })
check("field_names, concept sorted", synapse.field_names(config.defaults.synapses, "concept"), { "tags" })

check(
  "write_synapse_block, empty engram under frontmatter",
  synapse.write_synapse_block({ "---", "tags: []", "---", "# Title" }, { synapses = {} }, config.defaults.synapses),
  { "---", "tags: []", "---", "<!-- SYNAPSES -->", "- **down:**", "- **up:**", "***", "<!-- /SYNAPSES -->", "# Title" }
)
check(
  "write_synapse_block, no frontmatter goes to the top",
  synapse.write_synapse_block({ "# Title" }, { synapses = {} }, config.defaults.synapses),
  { "<!-- SYNAPSES -->", "- **down:**", "- **up:**", "***", "<!-- /SYNAPSES -->", "# Title" }
)
check(
  "write_synapse_block, values and show_empty = false",
  synapse.write_synapse_block({}, {
    synapses = { down = { { title = "a", path = "a.md" }, { title = "b", path = "b.md" } } },
  }, {
    up = { target = "engram", list = true, show_empty = false },
    down = { target = "engram", list = true },
  }),
  { "<!-- SYNAPSES -->", "- **down:** [a](a.md), [b](b.md)", "***", "<!-- /SYNAPSES -->" }
)
check(
  "write_synapse_block, existing block replaced in place",
  synapse.write_synapse_block(
    { "# T", "<!-- SYNAPSES -->", "stale", "<!-- /SYNAPSES -->" },
    { synapses = {} },
    { up = { target = "engram", list = true } }
  ),
  { "# T", "<!-- SYNAPSES -->", "- **up:**", "***", "<!-- /SYNAPSES -->" }
)

-- modules: engram

cfg = config.get()
check("filename, date", engram.filename(cfg, "project-x", time), "20260801_project-x.md")
cfg.engrams.filename.prefix = "none"
check("filename, none", engram.filename(cfg, "project-x", time), "project-x.md")
---@diagnostic disable-next-line: assign-type-mismatch
cfg.engrams.filename.prefix = "bogus"
check("filename, unknown prefix is an error", select(2, engram.filename(cfg, "x", time)) ~= nil, true)

check("slugify, spaces and case", engram.slugify("Note about Java", "_"), "note_about_java")
check("slugify, separator", engram.slugify("Note about Java", "-"), "note-about-java")
check("slugify, whitespace runs and edges", engram.slugify("  Two   words\t ", "_"), "two_words")
check("slugify, unsafe characters dropped", engram.slugify('a/b\\c:d*e?f"g<h>i|j', "_"), "abcdefghij")
check("slugify, non-ASCII kept and lowercased", engram.slugify("Ærlig Østers", "_"), "ærlig_østers")
check("slugify, repeated separators collapsed", engram.slugify("a _ b", "_"), "a_b")
check("slugify, trailing dot dropped", engram.slugify("Done.", "_"), "done")
check("slugify, other punctuation kept", engram.slugify("C++ & Lua", "_"), "c++_&_lua")
check("slugify, nothing usable", engram.slugify("///", "_"), "")
check("slugify, separator with pattern meaning", engram.slugify("a b", "."), "a.b")

check("header, defaults", engram.header(config.get()), {
  "---",
  "tags: []",
  "---",
  "<!-- SYNAPSES -->",
  "- **down:**",
  "- **up:**",
  "***",
  "<!-- /SYNAPSES -->",
})

local function rendered(template, vars)
  local lines, cursor = engram.render_template(template, vars)
  return { lines = lines, cursor = cursor }
end

local vars = { title = "my-slug", date = "20260801" }
check("render_template, default", rendered(config.defaults.engrams.content_template, vars), {
  lines = { "", "# my-slug", "", "" },
  cursor = { 4, 0 },
})
check("render_template, cursor mid-line", rendered("# %title%\nDate: %cursor% (%date%)", vars), {
  lines = { "# my-slug", "Date:  (20260801)" },
  cursor = { 2, 6 },
})
check("render_template, no cursor ends at content end", rendered("# %title%", vars), {
  lines = { "# my-slug" },
  cursor = { 1, 9 },
})
check("render_template, percent in title", rendered("%title%", { title = "100%", date = "" }), {
  lines = { "100%" },
  cursor = { 1, 4 },
})

-- modules: brain

check("registry under XDG_DATA_HOME", vim.startswith(brain.registry_path(), scratch), true)
check("names, empty registry", brain.names(), {})

local added = brain.add(scratch .. "/notes/work/")
check("add, name from folder, no trailing slash", added, { name = "work", location = scratch .. "/notes/work" })
check("add, folder created", vim.fn.isdirectory(scratch .. "/notes/work"), 1)
check(
  "add, explicit name",
  brain.add(scratch .. "/personal", "home"),
  { name = "home", location = scratch .. "/personal" }
)
check("add, collision refused", brain.add(scratch .. "/other", "work"), nil)
check("names, sorted", brain.names(), { "home", "work" })
check("get", brain.get("home"), { name = "home", location = scratch .. "/personal" })
check("containing, file inside", brain.containing(scratch .. "/notes/work/a.md"), brain.get("work"))
check("containing, sibling prefix is not inside", brain.containing(scratch .. "/notes/work2/a.md"), nil)

check("active, unset", brain.active(), nil)
check("switch, unknown", brain.switch("nope"), false)
check("switch", brain.switch("home"), true)
check("active, set", brain.active(), brain.get("home"))

local resolved
brain.resolve("work", function(b)
  resolved = b
end)
check("resolve, by name", resolved, brain.get("work"))
resolved = nil
brain.resolve(nil, function(b)
  resolved = b
end)
check("resolve, active when buffer is outside", resolved, brain.get("home"))

local dna = config.brain_config_path(scratch .. "/notes/work")
check("brain_config_path", dna, scratch .. "/notes/work/.mia_dna.json")
check("no config before open_config", vim.fn.filereadable(dna), 0)

brain.open_config("work")
check("open_config, creates an empty object", vim.fn.readfile(dna), { "{}" })
check("open_config, opens the file", vim.api.nvim_buf_get_name(0), dna)

vim.fn.writefile({ '{ "engrams": { "date_format": "YYYY" } }' }, dna)
brain.open_config("work")
check("open_config, existing file kept", vim.fn.readfile(dna), { '{ "engrams": { "date_format": "YYYY" } }' })
check("open_config, override read back", config.load_brain_config(scratch .. "/notes/work").engrams.date_format, "YYYY")

local function current()
  local brain_now, reason = brain.current()
  return { name = brain_now and brain_now.name, reason = reason }
end

vim.api.nvim_buf_set_name(0, scratch .. "/notes/work/note.md")
check("current, the buffer's brain wins", current(), { name = "work", reason = "holds the current buffer" })
vim.api.nvim_buf_set_name(0, scratch .. "/elsewhere/note.md")
check("current, falls back to the active brain", current(), { name = "home", reason = "active" })

check("deregister", brain.deregister("home"), true)
check("deregister, active cleared", brain.active(), nil)
check("current, nothing resolves", current(), { name = nil, reason = nil })
check("deregister, folder kept", vim.fn.isdirectory(scratch .. "/personal"), 1)
check("deregister, unknown", brain.deregister("home"), false)
brain.deregister("work")
check("registry is an object when empty", vim.fn.readfile(brain.registry_path())[1], "{}")

-- Prompts name their brain, so the resolution in brain.resolve is visible.

local prompts = {}
local answers = { "Prompt Test", "Prompt Test", "Prompt Test Two" }
---@diagnostic disable-next-line: duplicate-set-field
vim.fn.input = function(message)
  table.insert(prompts, message)
  return table.remove(answers, 1)
end

brain.add(scratch .. "/prompts", "prompted")
engram.add_engram("prompted")
check("add_engram prompt names the brain", prompts[1], "(prompted) Engram title: ")

engram.add_engram("prompted")
local taken = engram.filename(config.get(), "prompt_test")
check("collision re-prompt names the brain", prompts[3], ("(prompted) %s exists, edit title: "):format(taken))

vim.fn.delete(scratch, "rf")

io.write(("%d checks, %d failed\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
