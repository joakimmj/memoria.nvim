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
- **Engrams:** Create a note with a dated or plain filename, a generated
  frontmatter and synapse header, and your own content template.
- **Synapses:** Link two notes with one command; the inverse link (`up` ↔
  `down`) is written on the other note too.
- **Atlas:** A derived index of every brain — titles, links, backlinks, tags,
  tasks — kept up to date on its own and rebuildable at any time, with a
  consistency report of broken links and one-sided synapses.
- **Per-brain config:** Override any setting for one brain in its
  `.mia_dna.json`.

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
> - [md-drafting.nvim](https://github.com/joakimmj/md-drafting.nvim)

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
      -- "date" or "none".
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
  -- list = false holds one value only. Both kinds are written sorted by name.
  synapses = {
    up = { target = "engram", inverse = "down", list = true, show_empty = true },
    down = { target = "engram", inverse = "up", list = true, show_empty = true },
    tags = { target = "concept" },
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
:MiaBrainAdd ~/notes/work
:MiaBrainSwitch work
:MiaEngramAdd
:MiaSynapseAdd up
:MiaAtlasRebuild
:MiaBrainConfig
```

Every command is also a Lua function, e.g.
`require("memoria").engram.add_engram()`. See `:help memoria-api`.
