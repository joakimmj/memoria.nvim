# memoria.nvim

Memoria is a note-taking system built around a simple idea: \
*write down what you want to remember and keep it like a memory, in a brain*

- A **brain** is a folder of notes — one for work, one personal, one per project.
- An **engram** is a single note — a meeting record, a recipe, a project plan.
- A **synapse** is a link from a note — to another note, or to a concept.
- A **concept** is anything you reference that isn't itself a note — a person, a topic, a tag.

A brain holds engrams, connected to each other and to concepts through synapses.

Full reference: `:help memoria`.

## ✨ Features

- **Brains:** Register any folder as a brain, list them, switch between them.
- **Engrams:** Create a note with a dated, concept or plain filename, a
  generated frontmatter and synapse header, and your own content template.
- **Synapses:** Link two notes with one command; the inverse link (`up` ↔
  `down`) is written on the other note too.
- **Concepts:** Give the people, tags and topics your notes name an entry of
  their own — a type, aliases, an email or a description — and find the names
  nothing has declared yet.
- **Atlas:** A derived index of every brain — titles, links, backlinks, tags,
  tasks — kept up to date on its own and rebuildable at any time, with a
  consistency report of broken links and one-sided synapses.
- **Per-brain config:** Override any setting for one brain in its
  `.mia_dna.json`.
- **CLI:** `bin/mia` is memoria with no editor running — the same functions the
  commands call, from a shell, one JSON object per run.

## 📦 Installation

<details>
  <summary>vim.pack</summary>

  Built into Neovim 0.12 and later.

  ```lua
  vim.pack.add({
    "https://github.com/joakimmj/md-drafting.nvim",
    "https://github.com/joakimmj/memoria.nvim",
  })
  ```
</details>

<details>
  <summary>lazy.nvim</summary>

  ```lua
  {
    "joakimmj/memoria.nvim",
    dependencies = { "joakimmj/md-drafting.nvim" },
  }
  ```
</details>

<details>
  <summary>packer.nvim</summary>

  ```lua
  use({ "joakimmj/memoria.nvim", requires = { "joakimmj/md-drafting.nvim" } })
  ```
</details>

> [!IMPORTANT]
> - Requires Neovim 0.10 or later
> - `nvim-treesitter` with the `markdown` and `markdown_inline` parsers
> - [md-drafting.nvim](https://github.com/joakimmj/md-drafting.nvim) v0.2.0

## ⚙️ Configuration

Every value below is the default, so an empty `setup()` call — or none at
all — gives exactly this. See `:help memoria-config`.

```lua
require("memoria").setup({
  -- Create the :Mia* user commands.
  add_commands = true,

  engrams = {
    -- Tokens: YYYY, YY, MM, DD, HH, mm, ss. Used by the filename prefix
    -- and %date%.
    date_format = "YYYYMMDD",

    filename = {
      -- "date", "concept" or "none".
      prefix = "date",
      -- Between the prefix and the slug, and for spaces in the slug.
      separator = "_",
    },

    -- Prose under the generated header. %cursor% marks where typing starts;
    -- %title% and %date% are expanded.
    content_template = "# %title%\n\n%cursor%",

    -- Checkbox markers the atlas indexes as tasks, by state.
    task_markers = {
      not_done = { "[ ]" },
      done = { "[x]", "[X]" },
    },
  },

  -- Fields on an engram: target "engram" writes a link in the SYNAPSES
  -- block, "concept" a frontmatter list. show_empty writes the field even
  -- with no values. inverse is the field kept in sync on the other engram;
  -- list = false holds one value only, written as one. concept_type is the one
  -- concept type a concept field takes, required on every one of them. Both
  -- kinds are written sorted by name.
  synapses = {
    up = { target = "engram", inverse = "down", list = true, show_empty = true },
    down = { target = "engram", inverse = "up", list = true, show_empty = true },
    tags = { target = "concept", concept_type = "tag", list = true },
  },

  -- The concept types this brain has, and what each is asked for when its
  -- meta is filled in. A concept's type is one of these, or one the registry
  -- already uses.
  concepts = {
    tag = { fields = { "description" } },
  },
})
```

Maps merge by key, so one `filename` entry leaves the rest alone. Lists
replace wholesale. `vim.NIL` (`null` in JSON) removes a key: a synapse field
disappears, any other setting goes back to its built-in default —
`synapses = { up = vim.NIL }` drops `up`.

A brain can override any of it in its own `.mia_dna.json`, holding only what
differs — `:MiaBrainConfig` opens it, see `:help memoria-mia_dna.json`:

```json
{ "engrams": { "filename": { "prefix": "none" } } }
```

## 🚀 Usage

```vim
:MiaBrainRegister ~/notes/work
:MiaBrainSwitch work
:MiaEngramCreate
:MiaSynapseAttach up
:MiaConceptCreate
:MiaConceptAttach tags
:MiaConceptFill
:MiaAtlasRebuild
:MiaBrainConfig
```

A brain's concepts live in `mia_concepts.json` beside its notes — visible,
and meant to be edited by hand too. A person can carry an email, a tag a
description, and every concept field takes the one type it declares — to tag a
note with a room, configure a field for rooms. A name no entry answers to is
something `:MiaConceptFill` walks
you through and `:MiaAtlasRebuild` reports. See `:help memoria-concepts`.

Every command is also a Lua function, e.g.
`require("memoria").engram.create_engram()` — bind it to a keymap and it behaves
exactly like `:MiaEngramCreate`. The same feature without the prompts and the
buffer is `require("memoria").core.engram.create_engram(brain, opts)`, which
answers a result or `nil, err`. See `:help memoria-api`.

## 💻 CLI

`bin/mia` is that headless layer with a shell in front of it — for a script, a
git hook, another editor, or an AI agent. A brain is readable without memoria,
being markdown and JSON; what is not writable without it is a *correct* one: a
hand-written engram misses its generated header, and a hand-added link misses
its inverse.

```sh
bin/mia --help                        # every command, in words
bin/mia create-engram --help             # one command and what it takes
bin/mia commands                      # the same, as JSON
bin/mia brains
bin/mia create-engram --title "Project X" --field tags=java,streams
echo "Some prose." | bin/mia create-engram --title Notes --body -
bin/mia attach-synapse 20260801_notes.md up 20260801_project_x.md
bin/mia concepts --undeclared
bin/mia create-concept --name java --type tag --meta description="Java notes"
bin/mia edit-concept --name java --meta description="The JVM kind"
bin/mia attach-concept 20260801_notes.md tags java
bin/mia check
```

Each run prints one JSON object — `{"ok":true,"result":…}` or
`{"ok":false,"error":…}` — and exits `0` or `1`. It loads your own config, so
an engram it writes has the same header and template as one written in the
editor; `MEMORIA_INIT=NONE` skips that and uses the defaults.

`--help` is the one exception: plain text for a person, and no config loaded,
so it still answers when nothing else does. See `:help memoria-cli`.

### 🤖 Agents

An AI agent needs only to be told it exists. Point one at it from its
instructions file (`CLAUDE.md`, `AGENTS.md`):

```markdown
## Notes

Notes live in memoria brains — folders of markdown engrams. Never write or
link one by hand: a hand-written engram misses its generated header, and a
hand-added link misses its inverse.

Use `<path-to>/memoria.nvim/bin/mia`. Start with `bin/mia commands`, which
prints every command and its arguments as JSON. Each call prints one JSON
object and exits 0 (`"ok": true`) or 1.
```
