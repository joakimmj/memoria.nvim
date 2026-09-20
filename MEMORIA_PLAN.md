# memoria.nvim — Implementation Plan

Companion to `ARCHITECTURE.md` (Part 3), which this plan does not repeat —
section references below (`§5.6`, etc.) point back into it for the actual
behavior. This document only orders the work: what ships in each delivery,
and why that's the right cut.

## Dev notes

- Develop against the **local** copy of `md-drafting.nvim`, on branch
  `feature/expose-api-for-other-plugins` — not the published one, since that
  branch is where this plan's `api` surface (Part 1 §2, Part 2) actually
  lives.
- If something comes up during memoria's development that belongs in
  `md-drafting.nvim` instead — a missing syntax utility, a section-API gap —
  consider adding it to that same branch rather than working around it in
  memoria.
- Use the local `md-drafting.nvim` project itself — not the docs — as the
  starting point for memoria's project structure.
- Typings and comments follow `md-drafting.nvim`: a header comment per file,
  LuaCATS (`---@param`/`---@return`) on every function, `---@class` for shared
  shapes. Keep descriptions short and concise.
- Built-in defaults and `doc/memoria.txt` carry only what is implemented: a
  config key ships with the delivery that reads it, not ahead of it.
  `ARCHITECTURE.md` is the target state and describes the whole surface.
- Commands, functions and CLI commands follow Part 3 §1's verb table —
  Register, Create, Attach, Edit — so a new feature picks its verb there
  rather than copying the nearest precedent.
- Every prompt that acts on a brain names it, `(work) Engram title:` — new
  features in later deliveries included (`attach_synapse`, the concept pickers,
  `append_to_engram`, the agenda). The brain picker in `resolve` is the one
  exception: it is what decides the brain (§2.2).
- Every feature function follows the headless core (Part 3's design principles):
  it prompts for nothing, opens nothing, and answers one `result` or
  `nil, err`. Prompts, pickers, notifications and quickfix belong to `ui/`
  (Part 3 §1.3), which the commands call and a keymap can too.
- From Delivery 3 on, a feature the CLI can carry ships its command (§11.3) in
  the same delivery — `append` with `append_to_engram`, `concepts` with the
  registry. `rename_engram`/`delete_engram` never get one.
- Every delivery passes `nvim -l tests/run.lua [md-drafting dir]`,
  `stylua --check lua tests` and `lua-language-server --check .` with no
  warnings. Neither the tests nor `.luarc.json` may assume where
  `md-drafting.nvim` sits: the tests look on the runtimepath and in the usual
  install locations, and take a path when it is somewhere else.

Ordering rule: **a feature ships in the first delivery where everything it
depends on has already shipped**, subject to a second preference once that's
satisfied: core functionality before nice-to-have. `md-drafting.nvim` is
assumed complete and available throughout — every delivery uses it, none of
them wait on it.

---

## Delivery 1 — Brains and engrams

The smallest thing that is actually memoria rather than a folder of markdown:
register a brain, create an engram in it, nothing else.

**Ships:**
- Brain registry and commands — `:MiaBrainRegister`, `:MiaBrainDeregister`,
  `:MiaBrainList`, `:MiaBrainSwitch`, `:MiaBrainConfig`, `:MiaEngramCreate`,
  on unless `add_commands = false` (§1.3, §2.1–2.2)
- Configuration layers — built-in defaults, `setup({})`, `.mia_dna.json`
  resolution (§3)
- Filenames — `"date"` and `"none"` prefix modes only. `"concept"` mode is
  deferred: it needs `mia_concepts.json` to pick or create a concept against,
  which doesn't exist yet (§4, minus §4.1); choosing it is an error for now
- `create_engram` (§8.1) — writes the generated header (frontmatter + empty
  `SYNAPSES` block, straight from `synapses` config) and the prose template,
  opens the buffer

**Explicitly not yet:**
- No atlas. `create_engram`'s step 7 ("register in atlas") is a no-op for this
  delivery — there is nothing yet that reads one.
- No concept resolution. `tags`/`participants` are typed as plain strings into
  YAML lists; no picker, no metadata, no `mia_concepts.json`.
- Synapse fields (`up`/`down`) are written empty and left for the user to
  hand-edit. No `attach_synapse`, no inverse sync.

**What this unlocks:** a working note-taking loop — pick a brain, create
notes in it with tags, structured the same way every time. Nothing links
automatically yet, and nothing is indexed, but every file `create_engram` writes
is already in its final shape: later deliveries add behavior around these
files, not a migration of them.

---

## Delivery 2 — Synapses and the atlas

Turns the empty `SYNAPSES` blocks from Delivery 1 into an actual graph, with
an index behind it.

**Ships:**
- `attach_synapse` — inverse-sync between two engrams (§5.6), and
  `:MiaSynapseAttach`. Hand-added block fields survive every write (§5.3)
- The atlas — storage, refreshed on read (§7.1), and `rebuild_atlas`'s
  consistency check (§7.2) with `:MiaAtlasRebuild[!]`: broken links, missing
  inverses and unreadable frontmatter into the quickfix list, and `!` to
  repair inverses and backfill blocks. `concepts` ships here, since it
  already indexes plain tag strings with no registry entry required;
  `concepts_by_type` does not, since a concept's type lives only in the
  registry
- `engrams.task_markers` and the atlas's `tasks` buckets, and the `inverse` /
  `list` synapse field keys — the first config each is read by
- `create_engram`'s step 7 now refreshes the atlas

**Explicitly not yet:**
- No `rename_engram`/`delete_engram` — both need to search the atlas for
  referencing engrams before touching one, so they come after the atlas
  rather than alongside it.
- No `mia_concepts.json`, no `resolve_concept` — so `rebuild_atlas` reports
  no undeclared or orphaned concepts yet.

**What this unlocks:** linking two notes keeps both sides correct
automatically, and there is now something a rebuild/consistency pass can
actually check.

---

## Delivery 3 — The CLI

Lets anything outside the editor — a script, a git hook, an AI agent — work in
a brain under the same rules, before the feature list grows any further: every
later delivery then adds its command instead of retrofitting one.

**Ships:**
- The model/view/controller split (§1.3): everything Deliveries 1–2 shipped
  goes headless — the registry functions, `create_engram` (`title`, `fields`,
  `body` — §8.1), `attach_synapse`/`connect` (§5.6) and `rebuild_atlas` (§7.2)
  answer `result | nil, err` — and the prompting, pickers, notifying, buffer
  opening and quickfix move into `ui/`, one file per feature, which
  `commands.lua` and a user's keymaps call
- `cli.lua` and `bin/mia` (§11.1–11.2): user-config loading, stdout kept to
  one JSON object, exit status
- The commands in §11.3 — `brains`, `engrams`, `engram`, `tasks`, `check`,
  `rebuild`, `create-engram`, `attach-synapse`, `commands`
- The CLI in `doc/memoria.txt` and the README, including what an AI agent needs
  to use it: a short snippet for an instructions file (`CLAUDE.md`,
  `AGENTS.md`) naming `bin/mia commands` as the place to start

**Explicitly not yet:**
- No MCP server (Open items).
- Nothing destructive: `rename_engram`/`delete_engram` ship much later
  (Delivery 11), and stay off the CLI (§11.3) even then.

**What this unlocks:** engrams can be created, linked and queried without
Neovim open, and every file written that way is in the same shape as one
written by hand in the editor.

---

## Delivery 4 — Concepts

Adds the entity layer: persons, tags-with-metadata, and everything that
depends on being able to resolve a name to something.

**Ships:**
- `mia_concepts.json`, concept type schemas, `resolve_concept` (§6.1–6.3)
- `find_undeclared_concepts` / `set_concept_meta` (§6.4)
- Concept-prefix filenames (§4.1) — unblocked now that there's a registry to
  pick from or create into
- `concepts_by_type` added to the atlas, since it now has a real source —
  and `mia_concepts.json` joins what a refresh checks for changes, since it
  is not an engram and the per-file hash pass would miss an edit to it
- `rebuild_atlas` reports `undeclared_concept` and `orphaned_concept`, the
  latter anchored in `mia_concepts.json` — once the registry holds anything
- `:MiaConceptCreate`, `:MiaConceptAttach`, `:MiaConceptEdit`, `:MiaConceptList`,
  `:MiaConceptFill`
  (§2.2 names none), over one pick-or-create in `ui/concept.lua`
- The CLI's `concepts`, `create-concept`, `edit-concept` and `attach-concept`,
  and `create-engram --concept`
- `attach_concept` / `:MiaConceptAttach`: a concept into the current engram's
  concept field, written with md-drafting's new `set_frontmatter_field`

**What this unlocks:** tags and people stop being bare strings. A `person`
concept can carry an email; a `tag` can carry a description; typing a name
that doesn't exist yet is now a detectable, fixable state instead of just a
string nobody checks.

---

## Delivery 5 — Generated index

One function, ships alone because it depends on nothing this plan hasn't
already shipped and nothing later depends on it.

**Ships:**
- `generate_index` / `index.md`, all four sections (§9.3)

**What this unlocks:** a standing, regeneratable overview of the brain —
stats, recent activity, concepts by type, open tasks — without needing
navigation history or any of the deliveries after it.

---

## Delivery 6 — Navigation history

The foundational piece of "moving around a brain" — a delivery of its own now,
rather than bundled with diary, since Agenda (Delivery 7) needs it too and
shouldn't have to wait on diary to get it.

**Ships:**
- `push_nav_history` / `go_back` (§9.1)

**What this unlocks:** a "back" command that means something, wherever a link
was followed from.

---

## Delivery 7 — Agenda

**Ships:**
- `:MiaAgenda` (§9.4) — needs the atlas's `tasks` bucket (Delivery 2) and
  `go_back`/`push_nav_history` (Delivery 6) for its jump-to-source keymap

**What this unlocks:** the cross-engram, read-only task view — the everyday
productivity feature, shipped ahead of the more niche navigation helpers that
follow.

---

## Delivery 8 — Diary

**Ships:**
- `open_or_create_today` / `open_last_edited` (§9.5) — both call
  `push_nav_history` before opening anything, so they wait for Delivery 6
  rather than shipping alongside Delivery 1's `create_engram`, which they
  otherwise only depend on

**What this unlocks:** the diary workflow — open today's entry, creating it
on first touch, or jump to whatever was last worked on.

---

## Delivery 9 — Engram search

**Ships:**
- `search_engrams(brain, query, opts) → result | nil, err` — headless (dev
  notes' headless-core rule), fuzzy match over an engram's title, filename,
  tags and participants, read from the atlas. No prose/body search — nothing
  in the atlas holds engram bodies, and that's a different kind of feature
- `:MiaEngramSearch [brain] [query]` — resolves the brain through §2.2's
  `resolve()`, the same as every other brain-scoped command; prompts for
  `query` when not given, opens the chosen result
- `bin/mia search --query Q [--brain B]` (§11.3), shipped in this delivery
  per the dev notes' rule that a feature the CLI can carry gets its command
  alongside it

**What this unlocks:** finding an engram by roughly what it's called, tagged,
or who's in it, without opening a picker over every file in the brain — the
CLI's existing `engrams [--concept C]` (§11.3) becomes the exact-match,
concept-only case of what this searches more generally (§9.6). Its only real
dependency is the atlas (Delivery 2); it ships this late because it's a
convenience, not because anything forces it here.

---

## Delivery 10 — Link-or-create at cursor

**Ships:**
- `link_or_create_at_cursor` (§9.2) — needs `resolve_concept` (Delivery 4) and
  `push_nav_history` (Delivery 6) together, which is why it couldn't ship any
  earlier
- The "Engram" and "Concept" link-provider registration into `md-drafting`'s
  seam (Part 1 §7.3, Part 2 §3), since it's the same two resolutions exposed
  a second way

**What this unlocks:** turning a bare word into a link — to an existing
engram, an existing concept, or a newly-created engram — without leaving the
buffer, from both memoria's own function and `md-drafting`'s own
`:MdAddLink`/`:MdAddImage`.

---

## Delivery 11 — Safe rename and delete

The last delivery, deliberately: nothing else in this plan depends on
`rename_engram`/`delete_engram`, and a filename mistake or an unwanted note
can be worked around by hand in the meantime — useful, but not something
anything else is waiting on.

**Ships:**
- `rename_engram` (§10.1) and `delete_engram` (§10.2)

**What this unlocks:** engram identity stops being one-way. Up to this point
a filename mistake or an unwanted note was permanent (by hand-editing) or
silently broke links (by deleting outside the plugin); both are now safe,
atlas-aware operations — and, with this delivery, the plugin is feature-complete
against everything specified in `ARCHITECTURE.md`.

---

## Open items

Not scheduled into a delivery yet.

- **Folder browser for `:MiaBrainRegister`.** The path stays a required argument
  until there is a folder browser to pick it with (§2.2). The candidate is
  `md-drafting`'s `file_browser.browse` — the walk behind `File or URL` —
  with files filtered out, `insert_dirs` to take the current folder, and the
  typed entry for a folder that does not exist yet. It needs work in
  `md-drafting` first, on `feature/expose-api-for-other-plugins`: `browse`
  exposed under `api` (it is internal today, Part 1 §1.1, and would need a
  Part 2 entry), and a label option, since `[Insert this folder]` is worded
  for links.
- **MCP server.** A stdio JSON-RPC loop in `nvim --headless -l`, loading the
  config the way `bin/mia` does (§11.1), with its tools generated from
  `cli.lua`'s command table — one schema behind both, so they cannot drift.
  Long-lived, so it can hold the atlas in memory between calls rather than
  refreshing per process. Unscheduled because the CLI already serves anything
  with a shell; MCP adds discovery for clients without one, and is worth
  building once the command table has stopped moving.
