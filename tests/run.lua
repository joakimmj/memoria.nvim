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

local atlas = require("memoria.modules.atlas")
local brain = require("memoria.modules.brain")
local cli = require("memoria.cli")
local config = require("memoria.config")
local md_drafting = require("memoria.lib.md-drafting")
local date = require("memoria.lib.date")
local engram = require("memoria.modules.engram")
local json = require("memoria.lib.json")
local synapse = require("memoria.lib.synapse")
local synapse_module = require("memoria.modules.synapse")

-- The commands are the view's callers, and the assertions over prompts and
-- pickers below go through them. Creating them again is safe.
require("memoria.commands").create()

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
local sources = vim.fn.glob("lua/**/*.lua", false, true)
table.insert(sources, "bin/mia")
for _, path in ipairs(sources) do
  if path ~= "lua/memoria/lib/md-drafting.lua" then
    local source = table.concat(vim.fn.readfile(path), "\n")
    check(
      path .. " reaches md-drafting only through lib/md-drafting",
      source:find('require%("md%-drafting') == nil,
      true
    )
  end
end

-- The layers: the model answers, the view asks. Anything interactive under
-- modules/ would be unreachable from the CLI, which has no editor to ask in.
local INTERACTIVE = { "vim%.notify", "vim%.ui%.select", "vim%.fn%.input", "vim%.cmd%.edit", "setqflist" }
for _, path in ipairs(vim.fn.glob("lua/memoria/modules/*.lua", false, true)) do
  local source = table.concat(vim.fn.readfile(path), "\n")
  for _, pattern in ipairs(INTERACTIVE) do
    check(("%s does not %s"):format(path, (pattern:gsub("%%", ""))), source:find(pattern) == nil, true)
  end
end

local headless = vim.fn.glob("lua/memoria/{modules,lib}/*.lua", false, true)
table.insert(headless, "lua/memoria/cli.lua")
for _, path in ipairs(headless) do
  local source = table.concat(vim.fn.readfile(path), "\n")
  check(path .. " does not reach into the view", source:find('require%("memoria%.ui') == nil, true)
end

-- config: merge

check("merge, maps merge by key", config.merge({ a = { b = 1, c = 2 } }, { a = { c = 3 } }), { a = { b = 1, c = 3 } })
check("merge, lists replace wholesale", config.merge({ l = { 1, 2 } }, { l = { 3 } }), { l = { 3 } })
check("merge, null removes the key", config.merge({ a = 1, b = 2 }, { a = vim.NIL }), { b = 2 })
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

json.write(brain_dir .. "/.mia_dna.json", { engrams = { filename = { prefix = "none" } }, add_commands = false })
cfg = config.load_brain_config(brain_dir)
check("load_brain_config, dna over setup", cfg.engrams.filename, { prefix = "none", separator = "-" })
check("load_brain_config, dna cannot set add_commands", cfg.add_commands, true)

vim.fn.writefile({ "{ not json" }, brain_dir .. "/.mia_dna.json")
notified = nil
cfg = config.load_brain_config(brain_dir)
check("load_brain_config, invalid dna skipped", cfg.engrams.filename, { prefix = "date", separator = "-" })
check(
  "load_brain_config, invalid dna reported",
  notified ~= nil and notified:find(".mia_dna.json", 1, true) ~= nil,
  true
)

-- null: "not the value from above"

vim.fn.writefile({ '{ "synapses": { "up": null } }' }, brain_dir .. "/.mia_dna.json")
cfg = config.load_brain_config(brain_dir)
check("dna null removes a synapse field", synapse.field_names(cfg.synapses, "engram"), { "down" })

config.options = { engrams = { date_format = "YYYY" } }
vim.fn.writefile({ '{ "engrams": { "date_format": null } }' }, brain_dir .. "/.mia_dna.json")
cfg = config.load_brain_config(brain_dir)
check("dna null on a required setting restores the built-in default", cfg.engrams.date_format, "YYYYMMDD")

vim.fn.writefile({ '{ "engrams": null }' }, brain_dir .. "/.mia_dna.json")
cfg = config.load_brain_config(brain_dir)
check("dna null on a required map restores it whole", cfg.engrams, config.defaults.engrams)

vim.fn.writefile({ '{ "synapses": null }' }, brain_dir .. "/.mia_dna.json")
cfg = config.load_brain_config(brain_dir)
check("dna null on synapses removes every field", cfg.synapses, {})

vim.fn.delete(brain_dir .. "/.mia_dna.json")
config.options = { synapses = { tags = vim.NIL } }
check("setup vim.NIL removes a synapse field", synapse.field_names(config.get().synapses, "concept"), {})
check("defaults untouched by removal", config.defaults.synapses.tags, { target = "concept" })

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

local function composed(header, prose, cursor)
  local lines, at = engram.compose(header, prose, cursor)
  return { lines = lines, cursor = at }
end

check("compose, blank line after a header", composed({ "---", "---" }, { "# T", "" }, { 2, 0 }), {
  lines = { "---", "---", "", "# T", "" },
  cursor = { 5, 0 },
})
check("compose, no header, no blank line", composed({}, { "# T", "" }, { 2, 0 }), {
  lines = { "# T", "" },
  cursor = { 2, 0 },
})

local function header_with(synapses)
  local header_cfg = config.get()
  header_cfg.synapses = synapses
  return engram.header(header_cfg)
end

check("header, no concept fields: no frontmatter", header_with({ up = { target = "engram" } }), {
  "<!-- SYNAPSES -->",
  "- **up:**",
  "***",
  "<!-- /SYNAPSES -->",
})
check("header, no engram fields: no block", header_with({ tags = { target = "concept" } }), {
  "---",
  "tags: []",
  "---",
})
check("header, no fields at all: nothing", header_with({}), {})

check(
  "header, fields fill the flow list",
  engram.header(config.get(), { tags = { "java", "streams" } })[2],
  "tags: [java, streams]"
)
check("header, a scalar field value is one item", engram.header(config.get(), { tags = "java" })[2], "tags: [java]")
check(
  "header, a value that would read as structure is quoted",
  engram.header(config.get(), { tags = { "a, b", "c: d", " e " } })[2],
  'tags: ["a, b", "c: d", " e "]'
)
check(
  "header, a quote in a value is escaped",
  engram.header(config.get(), { tags = { 'say "hi"' } })[2],
  'tags: ["say \\"hi\\""]'
)
check("header, unknown field refused", { engram.header(config.get(), { bogus = { "x" } }) }, {
  nil,
  "no concept field 'bogus'",
})
---@diagnostic disable-next-line: assign-type-mismatch
check("header, a field that is not text refused", { engram.header(config.get(), { tags = { 1 } }) }, {
  nil,
  "field 'tags' takes strings",
})

local function with_body(prose, cursor, body)
  local lines, at = engram.insert_body(prose, cursor, body)
  return { lines = lines, cursor = at }
end

check("insert_body, one line at the end", with_body({ "# T", "", "" }, { 3, 0 }, "prose"), {
  lines = { "# T", "", "prose" },
  cursor = { 3, 5 },
})
check("insert_body, several lines", with_body({ "# T", "", "" }, { 3, 0 }, "one\ntwo"), {
  lines = { "# T", "", "one", "two" },
  cursor = { 4, 3 },
})
check("insert_body, mid-line keeps what follows", with_body({ "Date:  (x)" }, { 1, 6 }, "today"), {
  lines = { "Date: today (x)" },
  cursor = { 1, 11 },
})
check("insert_body, several lines mid-line", with_body({ "a b" }, { 1, 2 }, "one\ntwo"), {
  lines = { "a one", "twob" },
  cursor = { 2, 3 },
})
check(
  "write_synapse_block, custom frontmatter fields kept",
  synapse.write_synapse_block(
    { "---", "author: me", "status: draft", "---", "# T" },
    { synapses = {} },
    { up = { target = "engram" } }
  ),
  { "---", "author: me", "status: draft", "---", "<!-- SYNAPSES -->", "- **up:**", "***", "<!-- /SYNAPSES -->", "# T" }
)
check(
  "write_synapse_block, custom frontmatter kept with no block",
  synapse.write_synapse_block({ "---", "author: me", "---", "# T" }, { synapses = {} }, {}),
  { "---", "author: me", "---", "# T" }
)

local unreadable = { "---", "tags: [a, b", "---", "# T" }
local rewritten, fm_err = synapse.write_synapse_block(unreadable, { synapses = {} }, { up = { target = "engram" } })
check("write_synapse_block, unreadable frontmatter refused", rewritten, nil)
check(
  "write_synapse_block, unreadable frontmatter says why",
  fm_err,
  "frontmatter: line 2: unclosed flow list for 'tags'"
)

check(
  "write_synapse_block, only empty hidden fields: no block",
  synapse.write_synapse_block({ "# T" }, { synapses = {} }, { up = { target = "engram", show_empty = false } }),
  { "# T" }
)

local function rendered(template, vars)
  local lines, cursor = engram.render_template(template, vars)
  return { lines = lines, cursor = cursor }
end

local vars = { title = "my-slug", date = "20260801" }
check("render_template, default", rendered(config.defaults.engrams.content_template, vars), {
  lines = { "# my-slug", "", "" },
  cursor = { 3, 0 },
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
check("add, collision says why", select(2, brain.add(scratch .. "/other", "work")), "brain 'work' already exists")
check("names, sorted", brain.names(), { "home", "work" })
check("get", brain.get("home"), { name = "home", location = scratch .. "/personal" })
check("containing, file inside", brain.containing(scratch .. "/notes/work/a.md"), brain.get("work"))
check("containing, sibling prefix is not inside", brain.containing(scratch .. "/notes/work2/a.md"), nil)

check("active, unset", brain.active(), nil)
check("resolve, several brains and none named", { brain.resolve() }, {
  nil,
  "no brain resolved; name one (home, work)",
})
check("switch, unknown", brain.switch("nope"), nil)
check("switch, unknown says why", select(2, brain.switch("nope")), "no brain 'nope'")
check("switch", brain.switch("home"), brain.get("home"))
check("active, set", brain.active(), brain.get("home"))

check("resolve, by name", brain.resolve("work"), brain.get("work"))
check("resolve, unknown name", brain.resolve("nope"), nil)
check("resolve, unknown name says why", select(2, brain.resolve("nope")), "no brain 'nope'")
check("resolve, active when buffer is outside", brain.resolve(), brain.get("home"))
check("resolve, empty name is unnamed", brain.resolve(""), brain.get("home"))

local dna = config.brain_config_path(scratch .. "/notes/work")
check("brain_config_path", dna, scratch .. "/notes/work/.mia_dna.json")
check("no config before open_config", vim.fn.filereadable(dna), 0)

local work = brain.get("work") --[[@as memoria.Brain]]
check("ensure_config, answers the path", brain.ensure_config(work), dna)
check("ensure_config, creates an empty object", vim.fn.readfile(dna), { "{}" })

vim.cmd("MiaBrainConfig work")
check("MiaBrainConfig, opens the file", vim.api.nvim_buf_get_name(0), dna)

vim.fn.writefile({ '{ "engrams": { "date_format": "YYYY" } }' }, dna)
brain.ensure_config(work)
check("ensure_config, existing file kept", vim.fn.readfile(dna), { '{ "engrams": { "date_format": "YYYY" } }' })
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
check("resolve, the only brain left needs no picker", brain.resolve(), brain.get("work"))
check("deregister, folder kept", vim.fn.isdirectory(scratch .. "/personal"), 1)
check("deregister, unknown", brain.deregister("home"), nil)
brain.deregister("work")
check("resolve, none registered", { brain.resolve() }, { nil, "no brains registered" })
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
vim.cmd("MiaEngramAdd prompted")
check("MiaEngramAdd prompt names the brain", prompts[1], "(prompted) Engram title: ")

vim.cmd("MiaEngramAdd prompted")
local taken = engram.filename(config.get(), "prompt_test")
check(
  "collision re-prompt names the brain",
  prompts[3],
  ("(prompted) engram %s already exists, edit title: "):format(taken)
)
check(
  "MiaEngramAdd, the re-asked title is the one written",
  vim.fs.basename(vim.api.nvim_buf_get_name(0)),
  engram.filename(config.get(), "prompt_test_two")
)

-- lib: synapse, reading

local block_lines = {
  "---",
  "tags: []",
  "---",
  "<!-- SYNAPSES -->",
  "- **down:** [a](a.md), [b](b.md)",
  "- [ ] **up:** [c](c.md)",
  "stray prose",
  "- **related:**",
  "***",
  "<!-- /SYNAPSES -->",
  "# T",
}
local parsed_block = synapse.parse_synapse_block(block_lines) --[[@as table<string, memoria.SynapseLink[]> ]]

check("parse_synapse_block, no block", synapse.parse_synapse_block({ "# T" }), nil)
check(
  "parse_synapse_block, empty block",
  synapse.parse_synapse_block({ "<!-- SYNAPSES -->", "<!-- /SYNAPSES -->" }),
  {}
)
check("parse_synapse_block, fields, checkbox ignored, stray lines skipped", parsed_block, {
  down = { { title = "a", path = "a.md" }, { title = "b", path = "b.md" } },
  up = { { title = "c", path = "c.md" } },
  related = {},
})
check(
  "write_synapse_block, unconfigured fields kept, sorted with the rest",
  synapse.write_synapse_block(block_lines, { synapses = parsed_block }, config.defaults.synapses),
  {
    "---",
    "tags: []",
    "---",
    "<!-- SYNAPSES -->",
    "- **down:** [a](a.md), [b](b.md)",
    "- **related:**",
    "- **up:** [c](c.md)",
    "***",
    "<!-- /SYNAPSES -->",
    "# T",
  }
)
check(
  "parse_synapse_block, round-trips write_synapse_block",
  synapse.parse_synapse_block(
    synapse.write_synapse_block({}, { synapses = parsed_block }, config.defaults.synapses) --[[@as string[] ]]
  ),
  parsed_block
)
check("link, stem as text", synapse.link("20260801_x.md"), { title = "20260801_x", path = "20260801_x.md" })

-- modules: atlas, parsing

check("engram_target, bare filename", atlas.engram_target("a.md"), "a.md")
check("engram_target, ./ and anchor stripped", atlas.engram_target("./a.md#top"), "a.md")
check("engram_target, URL is not an engram", atlas.engram_target("https://x.org/a.md"), nil)
check("engram_target, folder is not in a flat brain", atlas.engram_target("../a.md"), nil)
check("engram_target, not markdown", atlas.engram_target("a.png"), nil)

local engram_lines = {
  "---",
  "tags: java",
  "---",
  "<!-- SYNAPSES -->",
  "- **up:** [p](p.md)",
  "- [ ] **down:**",
  "***",
  "<!-- /SYNAPSES -->",
  "",
  "# Project X",
  "",
  "See [q](q.md), [site](https://example.com) and [q again](./q.md#top).",
  "- [ ] open task",
  "- [x] done task",
  "- plain item",
}
local entry, tasks = atlas.parse_engram("x.md", engram_lines, config.get())
check("parse_engram, entry", entry, {
  title = "Project X",
  tags = { "java" },
  synapses = { up = { "p.md" }, down = {} },
  links = { "q.md" },
})
check("parse_engram, tasks outside the block", tasks, {
  { engram = "x.md", line = 13, text = "open task", state = "not_done" },
  { engram = "x.md", line = 14, text = "done task", state = "done" },
})
check("parse_engram, title falls back to the stem", atlas.parse_engram("y.md", { "text" }, config.get()).title, "y")
check(
  "parse_engram, empty frontmatter field is an empty list",
  atlas.parse_engram("y.md", { "---", "tags:", "---" }, config.get()).tags,
  {}
)
check(
  "parse_engram, unreadable frontmatter noted",
  atlas.parse_engram("y.md", unreadable, config.get()).error ~= nil,
  true
)

-- modules: synapse

local selects = {}
local choices = {}
---@diagnostic disable-next-line: duplicate-set-field
vim.ui.select = function(items, opts, on_choice)
  local labels = vim.tbl_map(opts.format_item or tostring, items)
  table.insert(selects, { prompt = opts.prompt, labels = labels })
  on_choice(table.remove(choices, 1))
end

local graph = brain.add(scratch .. "/graph", "graph") --[[@as memoria.Brain]]
local function engram_path(name)
  return graph.location .. "/" .. name
end
local function write_engram(name, body)
  local header = engram.header(config.get()) --[[@as string[] ]]
  vim.fn.writefile(vim.list_extend(header, body), engram_path(name))
end
local function block_of(name)
  return synapse.parse_synapse_block(vim.fn.readfile(engram_path(name)))
end
local function set_dna(value, target)
  json.write(config.brain_config_path((target or graph).location), value)
end

write_engram("a.md", { "", "# A" })
write_engram("b.md", { "", "# B" })
write_engram("c.md", { "", "# C" })

synapse_module.add_synapse({ source = engram_path("a.md"), target = "b.md", field = "up" })
check("add_synapse, source side", block_of("a.md").up, { { title = "b", path = "b.md" } })
check("add_synapse, inverse side", block_of("b.md").down, { { title = "a", path = "a.md" } })
check("add_synapse, atlas refreshed", atlas.refresh(graph).engrams["a.md"].synapses.up, { "b.md" })
check("add_synapse, backlinks", atlas.refresh(graph).backlinks["b.md"], { "a.md" })

local a_before, b_before = vim.fn.readfile(engram_path("a.md")), vim.fn.readfile(engram_path("b.md"))
synapse_module.add_synapse({ source = engram_path("a.md"), target = "b.md", field = "up" })
check(
  "add_synapse, again changes nothing",
  { vim.fn.readfile(engram_path("a.md")), vim.fn.readfile(engram_path("b.md")) },
  { a_before, b_before }
)

check("connect, self-link refused", synapse_module.connect(graph, "a.md", "a.md", "up"), nil)
check(
  "connect, self-link says why",
  select(2, synapse_module.connect(graph, "a.md", "a.md", "up")),
  "an engram cannot link to itself"
)
check("connect, missing target refused", synapse_module.connect(graph, "a.md", "zzz.md", "up"), nil)
check("connect, concept field refused", synapse_module.connect(graph, "a.md", "b.md", "tags"), nil)

check("locate, an engram in a brain", synapse_module.locate(engram_path("a.md")), {
  brain = graph,
  filename = "a.md",
})
check("locate, outside every brain", synapse_module.locate(scratch .. "/elsewhere/x.md"), nil)
check("locate, not markdown", synapse_module.locate(engram_path("a.txt")), nil)
check("locate, below a brain is not in it", synapse_module.locate(graph.location .. "/sub/a.md"), nil)
check(
  "add_synapse, outside a brain refused",
  select(2, synapse_module.add_synapse({ source = scratch .. "/elsewhere/x.md", target = "b.md", field = "up" })),
  "not an engram in a registered brain"
)
check(
  "add_synapse, a field is required",
  ---@diagnostic disable-next-line: missing-fields
  select(2, synapse_module.add_synapse({ source = engram_path("a.md"), target = "b.md" })),
  "a synapse field is required"
)
check(
  "add_synapse, answers what it linked",
  synapse_module.add_synapse({
    source = engram_path("a.md"),
    target = "b.md",
    field = "up",
  }),
  { brain = "graph", source = "a.md", field = "up", target = "b.md" }
)

choices = { "down", "c.md" }
selects = {}
vim.cmd.edit(vim.fn.fnameescape(engram_path("a.md")))
vim.cmd("MiaSynapseAdd")
check("MiaSynapseAdd, pickers name the brain", selects, {
  { prompt = "(graph) Synapse field:", labels = { "down", "up" } },
  { prompt = "(graph) down:", labels = { "B (b.md)", "C (c.md)" } },
})
check("MiaSynapseAdd, picked", { block_of("a.md").down, block_of("c.md").up }, {
  { { title = "c", path = "c.md" } },
  { { title = "a", path = "a.md" } },
})

-- A healed one-sided synapse: a.up holds b, drop a from b.down by hand.
vim.fn.writefile(
  synapse.write_synapse_block(vim.fn.readfile(engram_path("b.md")), { synapses = {} }, config.get().synapses) --[[@as string[] ]],
  engram_path("b.md")
)
synapse_module.connect(graph, "a.md", "b.md", "up")
check("connect, heals the missing side", block_of("b.md").down, { { title = "a", path = "a.md" } })

set_dna({ synapses = { up = { list = false } } })
synapse_module.connect(graph, "a.md", "c.md", "up")
check("connect, list = false replaces", block_of("a.md").up, { { title = "c", path = "c.md" } })
check("connect, list = false drops the old inverse", block_of("b.md").down, {})
check("connect, list = false writes the new inverse", block_of("c.md").down, { { title = "a", path = "a.md" } })

set_dna({ synapses = { related = { target = "engram" } } })
synapse_module.connect(graph, "a.md", "b.md", "related")
check("connect, no inverse: one side only", { block_of("a.md").related, block_of("b.md").related }, {
  { { title = "b", path = "b.md" } },
  {},
})
vim.fn.delete(config.brain_config_path(graph.location))

vim.fn.writefile(unreadable, engram_path("d.md"))
a_before = vim.fn.readfile(engram_path("a.md"))
check("connect, unreadable frontmatter refused", synapse_module.connect(graph, "a.md", "d.md", "down"), nil)
check("connect, nothing written when one side fails", vim.fn.readfile(engram_path("a.md")), a_before)
vim.fn.delete(engram_path("d.md"))

-- A loaded buffer is written through, keeping marks outside the change.
vim.cmd.edit(vim.fn.fnameescape(engram_path("b.md")))
local bufnr = vim.api.nvim_get_current_buf()
local heading_row = #vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) - 1
local ns = vim.api.nvim_create_namespace("memoria-test")
local mark = vim.api.nvim_buf_set_extmark(bufnr, ns, heading_row, 0, {})
synapse_module.connect(graph, "c.md", "b.md", "down")
check(
  "write through buffer, buffer updated",
  synapse.parse_synapse_block(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)).up,
  {
    { title = "c", path = "c.md" },
  }
)
check("write through buffer, saved", vim.bo[bufnr].modified, false)
check(
  "write through buffer, disk matches",
  vim.fn.readfile(engram_path("b.md")),
  vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
)
check("write through buffer, mark kept", vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, mark, {})[1], heading_row)
vim.cmd("enew")

-- modules: atlas, storage

local stored = atlas.refresh(graph) --[[@as memoria.Atlas]]
local stored_names = vim.tbl_keys(stored.engrams)
table.sort(stored_names)
check("refresh, every engram", stored_names, { "a.md", "b.md", "c.md" })
local raw = table.concat(vim.fn.readfile(atlas.path(graph.location)), "\n")
check("refresh, empty maps stored as objects", raw:find('"concepts":{}', 1, true) ~= nil, true)

local on_disk = json.read(atlas.path(graph.location))
on_disk.engrams["a.md"].title = "sentinel"
json.write(atlas.path(graph.location), on_disk)
check("refresh, unchanged engram not re-parsed", atlas.refresh(graph).engrams["a.md"].title, "sentinel")
check("refresh, full re-parses", atlas.refresh(graph, { full = true }).engrams["a.md"].title, "A")

vim.fn.writefile(vim.list_extend(vim.fn.readfile(engram_path("c.md")), { "- [ ] call Alice" }), engram_path("c.md"))
stored = atlas.refresh(graph) --[[@as memoria.Atlas]]
check("refresh, changed engram re-parsed", #stored.tasks.not_done, 1)

vim.fn.writefile({ "# E", "[gone](gone.md)" }, engram_path("e.md"))
vim.fn.delete(engram_path("c.md"))
stored = atlas.refresh(graph) --[[@as memoria.Atlas]]
check("refresh, vanished engram dropped", stored.engrams["c.md"], nil)
check("refresh, its tasks dropped", stored.tasks.not_done, {})

-- commands: a brain that is chosen, not resolved, is picked when not named

brain.add(scratch .. "/picked", "picked")
vim.cmd.edit(vim.fn.fnameescape(engram_path("a.md")))
choices, selects = { "picked" }, {}
vim.cmd("MiaBrainSwitch")
check("MiaBrainSwitch, no name: picker, not the buffer's brain", { selects[1].prompt, brain.active() }, {
  "Brain:",
  brain.get("picked"),
})
choices = { "picked" }
vim.cmd("MiaBrainDeregister")
check("MiaBrainDeregister, no name: picker", brain.get("picked"), nil)
choices = {}
vim.cmd("MiaBrainSwitch graph")
check("MiaBrainSwitch, named: no picker", brain.active(), graph)

-- A named brain that is not registered is an error, never the picker: the
-- caller said which one.
notified, selects = nil, {}
vim.cmd("MiaEngramAdd nope")
check("MiaEngramAdd, unknown brain is reported", notified, "memoria: no brain 'nope'")
check("MiaEngramAdd, unknown brain never picks", #selects, 0)
vim.cmd("enew")

-- modules: atlas, rebuild

-- b.down loses a by hand; a.down, a.up and b.up still point at the deleted c.
synapse_module.connect(graph, "a.md", "b.md", "up")
vim.fn.writefile(
  synapse.write_synapse_block(
    vim.fn.readfile(engram_path("b.md")),
    { synapses = { up = { { title = "c", path = "c.md" } } } },
    config.get().synapses
  ) --[[@as string[] ]],
  engram_path("b.md")
)

local function quickfix()
  return vim.tbl_map(function(item)
    return { file = vim.fs.basename(vim.api.nvim_buf_get_name(item.bufnr)), row = item.lnum, text = item.text }
  end, vim.fn.getqflist())
end

local rebuild = atlas.rebuild_atlas("graph") --[[@as memoria.RebuildResult]]
check("rebuild_atlas, unknown brain", { atlas.rebuild_atlas("nope") }, { nil, "no brain 'nope'" })
check("rebuild_atlas, the atlas it rebuilt", vim.tbl_count(rebuild.atlas.engrams), 3)
check(
  "rebuild_atlas, the kinds it found",
  vim.tbl_map(function(problem)
    return problem.kind
  end, rebuild.problems),
  {
    "broken_synapse",
    "broken_synapse",
    "missing_inverse",
    "broken_synapse",
    "broken_link",
  }
)
check(
  "locate_problems, rows",
  vim.tbl_map(function(problem)
    return { file = vim.fs.basename(problem.file), line = problem.line }
  end, atlas.locate_problems(graph, rebuild.problems)),
  {
    { file = "a.md", line = 5 },
    { file = "a.md", line = 7 },
    { file = "a.md", line = 7 },
    { file = "b.md", line = 6 },
    { file = "e.md", line = 2 },
  }
)

vim.cmd("MiaAtlasRebuild graph")
check("MiaAtlasRebuild, problems in the quickfix list", quickfix(), {
  { file = "a.md", row = 5, text = "broken synapse: down → c.md" },
  { file = "a.md", row = 7, text = "broken synapse: up → c.md" },
  { file = "a.md", row = 7, text = "missing inverse: b.md has no down → a.md" },
  { file = "b.md", row = 6, text = "broken synapse: up → c.md" },
  { file = "e.md", row = 2, text = "broken link: gone.md" },
})
check("MiaAtlasRebuild, summary", notified, "memoria: (graph) 3 engrams, 5 problems")
vim.cmd("cclose")

set_dna({ synapses = { side = { target = "engram" } } })
vim.cmd("MiaAtlasRebuild! graph")
check("MiaAtlasRebuild!, inverse written", block_of("b.md").down, { { title = "a", path = "a.md" } })
check("MiaAtlasRebuild!, new field backfilled", block_of("a.md").side, {})
check("MiaAtlasRebuild!, engram without a block left alone", block_of("e.md"), nil)
check("MiaAtlasRebuild!, broken links remain", #quickfix(), 4)
vim.cmd("cclose")
vim.fn.delete(config.brain_config_path(graph.location))

-- modules: engram, headless creation

local made = brain.add(scratch .. "/made", "made") --[[@as memoria.Brain]]

local new = engram.add_engram("made", {
  title = "Project X",
  fields = { tags = { "java", "streams" } },
  body = "first\nsecond",
}) --[[@as memoria.NewEngram]]
check("add_engram, answers the path", new.path, made.location .. "/" .. engram.filename(config.get(), "project_x"))
check("add_engram, answers where the cursor goes", new.cursor, { 13, 6 })
check("add_engram, nothing opened", vim.api.nvim_buf_get_name(0) == new.path, false)
check("add_engram, what it wrote", vim.fn.readfile(new.path), {
  "---",
  "tags: [java, streams]",
  "---",
  "<!-- SYNAPSES -->",
  "- **down:**",
  "- **up:**",
  "***",
  "<!-- /SYNAPSES -->",
  "",
  "# Project X",
  "",
  "first",
  "second",
})
check("add_engram, the atlas has it", atlas.refresh(made).engrams[vim.fs.basename(new.path)].title, "Project X")

check("add_engram, a title is required", { engram.add_engram("made") }, { nil, "a title is required" })
check("add_engram, collision", { engram.add_engram("made", { title = "Project X" }) }, {
  nil,
  ("engram %s already exists"):format(engram.filename(config.get(), "project_x")),
  "collision",
})
check("add_engram, nothing usable in the title", { engram.add_engram("made", { title = "///" }) }, {
  nil,
  "the title needs a letter or digit",
  "empty_slug",
})
check("add_engram, unknown brain", { engram.add_engram("nope", { title = "X" }) }, { nil, "no brain 'nope'" })

set_dna({ engrams = { filename = { prefix = "bogus" } } }, made)
check("add_engram, an unsupported prefix is not worth re-asking", {
  engram.add_engram("made", { title = "X" }),
}, { nil, "filename prefix 'bogus' is not supported", "prefix" })
vim.fn.delete(config.brain_config_path(made.location))

-- cli: parsing

local function parsed(name, argv)
  return {
    cli.parse(cli.find(name) --[[@as memoria.CliCommand]], argv),
  }
end

check("parse, an option and its value", parsed("engrams", { "--brain", "work" })[1].options, { brain = "work" })
check("parse, a flag", parsed("rebuild", { "--fix" })[1].options, { fix = true })
check("parse, a positional", parsed("engram", { "a.md" })[1].positional, { "a.md" })
check("parse, positionals and options together", parsed("add-synapse", { "a.md", "up", "b.md", "--brain", "w" })[1], {
  positional = { "a.md", "up", "b.md" },
  options = { brain = "w" },
})
check(
  "parse, a repeated option",
  parsed("add-engram", { "--title", "T", "--field", "a=1", "--field", "b=2" })[1].options,
  {
    title = "T",
    field = { "a=1", "b=2" },
  }
)
check("parse, unknown option", parsed("engrams", { "--bogus" })[2], "unknown option '--bogus' for 'engrams'")
check("parse, option without its value", parsed("engrams", { "--brain" })[2], "--brain needs a value")
check("parse, too many positionals", parsed("engram", { "a.md", "b.md" })[2], "'engram' takes 1 argument")
check("parse, a command that takes none", parsed("brains", { "x" })[2], "'brains' takes 0 arguments")
check("parse, missing positional", parsed("engram", {})[2], "engram needs <file>")
check("parse, missing option", parsed("add-engram", {})[2], "add-engram needs --title")

-- cli: the command table

check(
  "the command table, in order",
  vim.tbl_map(function(command)
    return command.name
  end, cli.commands),
  {
    "brains",
    "engrams",
    "engram",
    "tasks",
    "check",
    "rebuild",
    "add-engram",
    "add-synapse",
    "commands",
  }
)
for _, command in ipairs(cli.commands) do
  check(command.name .. " is described", type(command.description) == "string" and command.description ~= "", true)
  check(command.name .. " runs", type(command.run), "function")
  for _, argument in ipairs(command.arguments) do
    check(
      ("%s's %s is described"):format(command.name, argument.name),
      type(argument.description) == "string" and argument.description ~= "",
      true
    )
  end
end
check("commands is JSON, with no function in it", pcall(vim.json.encode, cli.run({ "commands" })), true)
check("commands lists every command", #(cli.run({ "commands" }) --[[@as table]]).commands, #cli.commands)

-- cli: usage

local function usage(name)
  return table.concat(cli.usage(name), "\n")
end

check(
  "usage, a line per command",
  vim.tbl_filter(function(line)
    return line:match("^  %S")
  end, cli.usage()),
  {
    "  brains",
    "  engrams [--brain <name>] [--concept <concept>]",
    "  engram <file> [--brain <name>]",
    "  tasks [--brain <name>] [--state <state>]",
    "  check [--brain <name>]",
    "  rebuild [--brain <name>] [--fix]",
    "  add-engram [--brain <name>] --title <title> [--field <name=value>] [--body <text>]",
    "  add-synapse <source> <field> <target> [--brain <name>]",
    "  commands",
  }
)
check("usage, one command leads with its own line", cli.usage("engram")[1], "engram <file> [--brain <name>]")
check("usage, a required argument is bare", usage("engram"):find("<file>   ", 1, true) ~= nil, true)
check("usage, a required option says so", usage("add-engram"):find("(required)", 1, true) ~= nil, true)
check("usage, a repeated option says so", usage("add-engram"):find("(repeatable)", 1, true) ~= nil, true)
check("usage, every argument is explained", select(2, usage("add-engram"):gsub("\n  %-%-", "")), 4)
check("usage, a command with no arguments", cli.usage("brains"), {
  "brains",
  "",
  "Every registered brain",
})
check("usage, an unknown command falls back to all of them", usage("nope"), usage())

-- cli: running commands

--- A table's keys, sorted, so an assertion does not depend on map order.
---@param map table
---@return string[]
local function sorted_keys(map)
  local keys = vim.tbl_keys(map)
  table.sort(keys)
  return keys
end

local function ran(argv)
  local result, err = cli.run(argv)
  return result or err
end

check(
  "cli brains",
  vim.tbl_map(function(entry)
    return entry.name
  end, ran({ "brains" }).brains),
  { "graph", "made", "prompted" }
)
check("cli brains, an existing folder", ran({ "brains" }).brains[1].exists, true)
check("cli, no command", ran({}), "no command given; 'commands' lists them, --help explains them")
check("cli, unknown command", ran({ "nope" }), "unknown command 'nope'; 'commands' lists them, --help explains them")
check("cli, unknown brain", ran({ "engrams", "--brain", "nope" }), "no brain 'nope'")
check("cli, no brain named resolves the same way the editor does", ran({ "engrams" }).brain, "graph")

check(
  "cli engrams",
  vim.tbl_map(function(entry)
    return entry.file
  end, ran({ "engrams", "--brain", "graph" }).engrams),
  { "a.md", "b.md", "e.md" }
)
check("cli engrams, a concept nothing names", ran({ "engrams", "--brain", "made", "--concept", "nope" }).engrams, {})
check(
  "cli engrams, by concept",
  vim.tbl_map(function(entry)
    return entry.file
  end, ran({ "engrams", "--brain", "made", "--concept", "java" }).engrams),
  { vim.fs.basename(new.path) }
)

local shown = ran({ "engram", "--brain", "graph", "a.md" })
check("cli engram, its entry", shown.entry.title, "A")
check("cli engram, its backlinks", shown.backlinks, { "b.md" })
check("cli engram, its content", shown.content, table.concat(vim.fn.readfile(engram_path("a.md")), "\n"))
check("cli engram, one that is not there", ran({ "engram", "--brain", "graph", "zzz.md" }), "(graph) no engram zzz.md")

check("cli tasks, both buckets", sorted_keys(ran({ "tasks", "--brain", "graph" }).tasks), { "done", "not_done" })
check("cli tasks, one bucket", sorted_keys(ran({ "tasks", "--brain", "graph", "--state", "done" }).tasks), { "done" })
check(
  "cli tasks, an unknown state",
  ran({ "tasks", "--brain", "graph", "--state", "bogus" }),
  "(graph) no task state 'bogus'; it is 'not_done' or 'done'"
)

local checked = ran({ "check", "--brain", "graph" })
check("cli check, the count", checked.engrams, 3)
check("cli check, a problem with file, line and kind", checked.problems[1], {
  engram = "a.md",
  file = engram_path("a.md"),
  line = 5,
  kind = "broken_synapse",
  text = "broken synapse: down → c.md",
})
check("cli rebuild --fix leaves what it cannot repair", #ran({ "rebuild", "--brain", "graph", "--fix" }).problems, 4)

local added = ran({ "add-engram", "--brain", "made", "--title", "From the CLI", "--field", "tags=java, lua" })
check("cli add-engram", vim.fn.readfile(added.path)[2], "tags: [java, lua]")
check(
  "cli add-engram, a field that is not configured",
  ran({
    "add-engram",
    "--brain",
    "made",
    "--title",
    "X",
    "--field",
    "bogus=1",
  }),
  "(made) no concept field 'bogus'"
)
check(
  "cli add-engram, a field without a value",
  ran({
    "add-engram",
    "--brain",
    "made",
    "--title",
    "X",
    "--field",
    "bogus",
  }),
  "(made) --field takes name=value"
)

check(
  "cli add-synapse",
  ran({ "add-synapse", "--brain", "made", vim.fs.basename(added.file), "up", vim.fs.basename(new.path) }),
  {
    brain = "made",
    source = added.file,
    field = "up",
    target = vim.fs.basename(new.path),
  }
)
check("cli add-synapse, the inverse is written too", synapse.parse_synapse_block(vim.fn.readfile(new.path)).down, {
  { title = (added.file:gsub("%.md$", "")), path = added.file },
})

-- cli: bin/mia

local mia = vim.fn.fnamemodify("bin/mia", ":p")
local mia_init = scratch .. "/init.lua"
vim.fn.writefile({
  ('package.path = "%s/lua/?.lua;%s/lua/?/init.lua;" .. package.path'):format(md_drafting_dir, md_drafting_dir),
  'print("from the config")',
  'require("memoria").setup({})',
}, mia_init)

--- Run bin/mia the way a caller outside the editor does: its own process,
--- with the config sourced.
---@param argv string[] The command and its arguments
---@param opts? table Extra vim.system options, e.g. env or stdin
---@return { code: integer, out: any, stderr: string }
local function mia_run(argv, opts)
  opts = vim.tbl_extend("force", { text = true }, opts or {})
  opts.env = vim.tbl_extend("force", { MEMORIA_INIT = mia_init }, opts.env or {})

  -- vim.v.progpath, not "nvim": the child is the binary running this.
  local done = vim.system(vim.list_extend({ vim.v.progpath, "-l", mia }, argv), opts):wait()
  local ok, decoded = pcall(vim.json.decode, done.stdout)
  return { code = done.code, out = ok and decoded or done.stdout, stderr = done.stderr }
end

local listed = mia_run({ "brains" })
check("bin/mia, exit status", listed.code, 0)
check("bin/mia, one JSON object on stdout", listed.out.ok, true)
check(
  "bin/mia, the result",
  vim.tbl_map(function(entry)
    return entry.name
  end, listed.out.result.brains),
  { "graph", "made", "prompted" }
)
check("bin/mia, the config's own output goes to stderr", listed.stderr:find("from the config", 1, true) ~= nil, true)

local refused = mia_run({ "nope" })
check("bin/mia, a failure exits 1", refused.code, 1)
check(
  "bin/mia, a failure says why",
  refused.out,
  { ok = false, error = "unknown command 'nope'; 'commands' lists them, --help explains them" }
)

local piped = mia_run({ "add-engram", "--brain", "made", "--title", "Piped", "--body", "-" }, {
  stdin = "line one\nline two",
})
check("bin/mia --body -, reads stdin", vim.list_slice(vim.fn.readfile(piped.out.result.path), 10), {
  "# Piped",
  "",
  "line one",
  "line two",
})

local helped = mia_run({ "--help" })
check("bin/mia --help, exit status", helped.code, 0)
check("bin/mia --help, plain text rather than JSON", type(helped.out), "string")
check("bin/mia --help, every command", select(2, helped.out:gsub("\n  %S", "")), #cli.commands)

local helped_one = mia_run({ "add-engram", "--help" })
check(
  "bin/mia <command> --help, that command only",
  helped_one.out:match("^[^\n]*"),
  table.concat({
    "add-engram [--brain <name>] --title <title>",
    "[--field <name=value>] [--body <text>]",
  }, " ")
)
check("bin/mia <command> --help, its arguments", helped_one.out:find("(repeatable)", 1, true) ~= nil, true)

vim.fn.writefile({ "-- a config that never sets memoria up" }, scratch .. "/bare.lua")
local bare = mia_run({ "brains" }, { env = { MEMORIA_INIT = scratch .. "/bare.lua" } })
check("bin/mia, a config without setup() is refused", bare.code, 1)
check("bin/mia, and says which config", bare.out.error:find("bare.lua did not call", 1, true) ~= nil, true)

local bare_help = mia_run({ "--help" }, { env = { MEMORIA_INIT = scratch .. "/bare.lua" } })
check("bin/mia --help, loads no config", bare_help.code, 0)

local missing = mia_run({ "brains" }, { env = { MEMORIA_INIT = scratch .. "/gone.lua" } })
check("bin/mia, no config at all", missing.out.error:find("no config at", 1, true) ~= nil, true)

-- Packages are off under `nvim -l`, so NONE genuinely has no md-drafting.
local alone = mia_run({ "brains" }, { env = { MEMORIA_INIT = "NONE" } })
check("bin/mia NONE, without md-drafting", alone.code, 1)
check("bin/mia NONE, names the dependency", alone.out.error:find("md-drafting.nvim", 1, true) ~= nil, true)

vim.fn.delete(scratch, "rf")

io.write(("%d checks, %d failed\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
