# memoria.nvim

Memoria is a note-taking system built around a simple idea: \
*write down what you want to remember and keep it like a memory, in a brain*

- A **brain** is a folder of notes — one for work, one personal, one per project.
- An **engram** is a single note — a meeting record, a recipe, a project plan.
- A **synapse** is a link from one note to another.
- A **concept** is anything you reference that isn't itself a note — a person, a topic, a tag.

A brain holds engrams, connected to each other through synapses and to
concepts through their frontmatter.

Full reference: `:help memoria`.

## ✨ Features

- **Brains:** Register any folder as a brain, list them, switch between them.
- **Engrams:** Create a note with a dated, concept or plain filename, a
  generated frontmatter and synapse header, and your own content template.
  Set a frontmatter value on it with one command.
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
> - [md-drafting.nvim](https://github.com/joakimmj/md-drafting.nvim) v0.3.0

## ⚙️ Configuration

Every value below is the default, so an empty `setup()` call — or none at
all — gives exactly this. See `:help memoria-config`.

```lua
require("memoria").setup({
  -- Create the :Mia* user commands.
  add_commands = true,

  engrams = {
    -- Tokens: YYYY, YY, MM, DD, HH, mm, ss. Used by %date%, in the template
    -- and in a frontmatter field's default.
    date_format = "YYYY-MM-DD",

    -- How a concept field writes a concept: "slug" (its key) or
    -- "display_name". A field's own concept_form wins.
    concept_form = "slug",

    filename = {
      -- "date", "concept" or "none".
      prefix = "date",
      -- Tokens as above, for the "date" prefix.
      date_format = "YYYY-MM-DD",
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

  -- Engram-to-engram links, in the SYNAPSES block. show_empty writes the
  -- field even with no values; inverse is the field kept in sync on the
  -- other engram; list = false holds one value only (list defaults to
  -- true).
  synapses = {
    up = { inverse = "down", list = true, show_empty = true },
    down = { inverse = "up", list = true, show_empty = true },
  },

  -- Frontmatter fields. kind "concept" resolves against the brain's
  -- concepts, "value" is plain text. concept_type is the one type a concept
  -- field takes (left out, every type); default is what a new engram's value
  -- field holds; list = false holds one value, written as itself (list
  -- defaults to true). Written sorted by name.
  frontmatter = {
    created = { kind = "value", list = false, default = "%date%" },
    tags = { kind = "concept", concept_type = "tag", list = true },
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
replace wholesale. `vim.NIL` (`null` in JSON) removes a key: a synapse or
frontmatter field disappears, any other setting goes back to its built-in
default — `synapses = { up = vim.NIL }` drops `up`.

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
:MiaConceptAttach tags
:MiaFrontmatterEdit created 2026-08-01
:MiaConceptRegister
:MiaAtlasRebuild
:MiaBrainConfig
```

A brain's concepts live in `.mia_concepts.json` beside its notes — hidden,
but plain JSON meant to be edited by hand too. Each is keyed by a slug (`alice_smith`)
and shown by its display name (`Alice Smith`); a person can carry an email, a
tag a description. A concept field with a `concept_type` takes only that type,
one without takes any. A name no entry answers to is something
`:MiaConceptRegister` walks you through and `:MiaAtlasRebuild` reports. See
`:help memoria-concepts`.

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
bin/mia create-engram --help          # one command and what it takes
bin/mia commands                      # the same, as JSON
bin/mia brains
bin/mia create-engram --title "Project X" --field tags=java,streams
echo "Some prose." | bin/mia create-engram --title Notes --body -
bin/mia attach-synapse 2026-08-01_notes.md up 2026-08-01_project_x.md
bin/mia concepts --undeclared
bin/mia create-concept --name Java --type tag --meta description="Java notes"
bin/mia edit-concept --name java --meta description="The JVM kind"
bin/mia attach-concept 2026-08-01_notes.md tags java
bin/mia edit-frontmatter 2026-08-01_notes.md created 2026-07-31
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
