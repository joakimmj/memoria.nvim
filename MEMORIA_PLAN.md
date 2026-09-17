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
- Every prompt that acts on a brain names it, `(work) Engram title:` — new
  features in later deliveries included (`add_synapse`, the concept pickers,
  `append_to_engram`, the agenda). The brain picker in `resolve` is the one
  exception: it is what decides the brain (§2.2).
- Every delivery passes `nvim -l tests/run.lua [md-drafting dir]`,
  `stylua --check lua tests` and `lua-language-server --check .` with no
  warnings. Neither the tests nor `.luarc.json` may assume where
  `md-drafting.nvim` sits: the tests look on the runtimepath and in the usual
  install locations, and take a path when it is somewhere else.

Ordering rule: **a feature ships in the first delivery where everything it
depends on has already shipped.** `md-drafting.nvim` is assumed complete and
available throughout — every delivery uses it, none of them wait on it.

---

## Delivery 1 — Brains and engrams

The smallest thing that is actually memoria rather than a folder of markdown:
register a brain, create an engram in it, nothing else.

**Ships:**
- Brain registry and commands — `:MiaBrainAdd`, `:MiaBrainDeregister`,
  `:MiaBrainList`, `:MiaBrainSwitch`, `:MiaBrainCurrent`, `:MiaBrainConfig`,
  `:MiaEngramAdd`, behind `add_commands` (§1.3, §2.1–2.2)
- Configuration layers — built-in defaults, `setup({})`, `.mia_dna.json`
  resolution (§3)
- Filenames — `"date"` and `"none"` prefix modes only. `"concept"` mode is
  deferred: it needs `mia_concepts.json` to pick or create a concept against,
  which doesn't exist yet (§4, minus §4.1); choosing it is an error for now
- `add_engram` (§8.1) — writes the generated header (frontmatter + empty
  `SYNAPSES` block, straight from `synapses` config) and the prose template,
  opens the buffer

**Explicitly not yet:**
- No atlas. `add_engram`'s step 7 ("register in atlas") is a no-op for this
  delivery — there is nothing yet that reads one.
- No concept resolution. `tags`/`participants` are typed as plain strings into
  YAML lists; no picker, no metadata, no `mia_concepts.json`.
- Synapse fields (`up`/`down`) are written empty and left for the user to
  hand-edit. No `add_synapse`, no inverse sync.

**What this unlocks:** a working note-taking loop — pick a brain, create
notes in it with tags, structured the same way every time. Nothing links
automatically yet, and nothing is indexed, but every file `add_engram` writes
is already in its final shape: later deliveries add behavior around these
files, not a migration of them.

---

## Delivery 2 — Synapses and the atlas

Turns the empty `SYNAPSES` blocks from Delivery 1 into an actual graph, with
an index behind it.

**Ships:**
- `add_synapse` — inverse-sync between two engrams (§5.6)
- The atlas — storage, and `rebuild_atlas`'s consistency check (§7.1–7.2).
  `concepts_by_type` is part of the stored shape but stays empty until Delivery
  4; `concepts` itself does not wait, since it already indexes plain tag
  strings with no registry entry required

**Explicitly not yet:**
- No `rename_engram`/`delete_engram` — both need to search the atlas for
  referencing engrams before touching one, so they wait one delivery even
  though the atlas they need ships here.
- No `mia_concepts.json`, no `resolve_concept`.

**What this unlocks:** linking two notes keeps both sides correct
automatically, and there is now something a rebuild/consistency pass can
actually check.

---

## Delivery 3 — Safe rename and delete

A short, self-contained delivery: two functions that were always going to
need the previous one finished first.

**Ships:**
- `rename_engram` (§10.1) and `delete_engram` (§10.2)

**What this unlocks:** engram identity stops being one-way. Up to this point
a filename mistake or an unwanted note was permanent (by hand-editing) or
silently broke links (by deleting outside the plugin); both are now safe,
atlas-aware operations.

---

## Delivery 4 — Concepts

Adds the entity layer: persons, tags-with-metadata, and everything that
depends on being able to resolve a name to something.

**Ships:**
- `mia_concepts.json`, concept type schemas, `resolve_concept` (§6.1–6.3)
- `find_undeclared_concepts` / `set_concept_meta` (§6.4)
- Concept-prefix filenames (§4.1) — unblocked now that there's a registry to
  pick from or create into
- `concepts_by_type` in the atlas starts being populated, since it now has a
  real source

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
navigation history or any of Delivery 6–8's machinery.

---

## Delivery 6 — Navigation history and diary

The foundational piece of "moving around a brain," plus the one feature built
directly on it.

**Ships:**
- `push_nav_history` / `go_back` (§9.1)
- `open_or_create_today` / `open_last_edited` (§9.5) — both call `push_nav_history`
  before opening anything, so they wait for it rather than shipping alongside
  Delivery 1's `add_engram`, which they otherwise only depend on

**What this unlocks:** a "back" command that means something, and the diary
workflow — open today's entry, creating it on first touch, or jump to
whatever was last worked on.

---

## Delivery 7 — Link-or-create at cursor

**Ships:**
- `link_or_create_at_cursor` (§9.2) — needs `resolve_concept` (Delivery 4) and
  `push_nav_history` (Delivery 6) together, which is why it's the one navigation
  feature that couldn't ship any earlier
- The "Engram" and "Concept" link-provider registration into `md-drafting`'s
  seam (Part 1 §7.3, Part 2 §3), since it's the same two resolutions exposed
  a second way

**What this unlocks:** turning a bare word into a link — to an existing
engram, an existing concept, or a newly-created engram — without leaving the
buffer, from both memoria's own function and `md-drafting`'s own
`:MdAddLink`/`:MdAddImage`.

---

## Delivery 8 — Agenda

**Ships:**
- `:MiaAgenda` (§9.4) — needs the atlas's `tasks` bucket (Delivery 2) and
  `go_back`/`push_nav_history` (Delivery 6) for its jump-to-source keymap

**What this unlocks:** the cross-engram, read-only task view — the last piece
of "productivity layer," and the natural point to call the plugin feature-complete
against everything specified in `ARCHITECTURE.md`.
