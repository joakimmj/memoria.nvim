# memoria.nvim

`memoria.nvim` is a Neovim plugin that provides a suite of tools for note
taking, enhanced Markdown editing and a built-in presentation mode. The plugin
is designed to be lightweight, configurable, and easy to use.

## ✨ Features

- **Presentation Mode:** View your markdown file as a slide deck directly
  within Neovim.
- **Task:** Cycle through task list item states (no checkbox -> `[ ]` -> `[x]`).
- **TOC Generation:** Automatically generate and update a table of contents
  from your markdown headers.
- **Callout:** Adding callout block qoute
- **Generators:** Quickly create tables, links, images, footnotes, block
  quotes, callouts, and more.
- **Text Formatting:** Easily toggle bold, italic, strikethrough, and inline
  code on selected text.
- **And more...**

## 📦 Installation

Install `memoria.nvim` using your favorite plugin manager.

<details>
  <summary>lazy.nvim</summary>

  [lazy.nvim](https://github.com/folke/lazy.nvim)
  ```lua
  {
    "joakimmj/memoria.nvim",
    -- Optional: ft = "markdown",
  }
  ```
</details>

<details>
  <summary>packer.nvim</summary>

  [packer.nvim](https://github.com/wbthomason/packer.nvim)

  ```lua
  use "joakimmj/memoria.nvim"
  ```
</details>

## Dependencies

This plugin requires `nvim-treesitter` to function correctly. Please ensure you
have it installed and configured.

```lua
-- For lazy.nvim
{
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  config = function()
    require("nvim-treesitter.configs").setup({
      ensure_installed = { "markdown", "markdown_inline" },
      highlight = { enable = true },
    })
  end,
},

-- For packer.nvim
use {
  "nvim-treesitter/nvim-treesitter",
  run = ":TSUpdate",
  config = function()
    require("nvim-treesitter.configs").setup({
      ensure_installed = { "markdown", "markdown_inline" },
      highlight = { enable = true },
    })
  end,
}
```

You must have the `markdown` and `markdown_inline` parsers installed for the
plugin to work.

## ⚙️ Configuration

`memoria.nvim` is configured through its `setup()` function. Here is an example
configuration with all the default values:

```lua
require("memoria").setup({
  -- Add user commands for all functions in the plugin.
  -- Default: false
  add_commands = false,

  -- Callout types to use for `add_callout`.
  -- These are the GitHub Flavored Markdown callout types.
  callout_types = {
    "NOTE",
    "TIP",
    "IMPORTANT",
    "WARNING",
    "CAUTION",
  },

  presentation = {
    -- Show line numbers in presentation mode.
    -- default: false
    show_line_numbers = false,

    -- Show relative line numbers in presentation mode.
    -- default: false
    show_relative_line_numbers = false,

    -- Width of the gutter in presentation mode.
    -- default: 6
    gutter_width = 6,

    -- Navigation
    keymaps = {
      next = "n",
      previous = "p",
      quit = "q",
    },
  },
})
```

## Mappings

This plugin does not come with any default mappings. You can set up your own
keymaps for markdown files using a `FileType` autocommand.

Here is an example of how you can set up keymaps:

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    local mia = require("memoria")

    -- Presentation (normal mode)
    vim.keymap.set("n", "<leader>mp", mia.presentation.start_presentation, { desc = "Start Presentation" })

    -- Tasks (normal mode)
    vim.keymap.set("n", "<leader>mt", mia.task.toggle, { desc = "Toggle Task" })

    -- Formatting (visual mode)
    vim.keymap.set("v", "<leader>mfb", mia.format.toggle_bold, { desc = "Toggle Bold" })
    vim.keymap.set("v", "<leader>mfi", mia.format.toggle_italic, { desc = "Toggle Italic" })
    vim.keymap.set("v", "<leader>mfs", mia.format.toggle_strikethrough, { desc = "Toggle Strikethrough" })
    vim.keymap.set("v", "<leader>mfc", mia.format.toggle_inline_code, { desc = "Toggle Inline Code" })

    -- Generators (normal mode)
    vim.keymap.set("n", "<leader>mgt", mia.generator.generate_toc, { desc = "Generate TOC" })
    vim.keymap.set("n", "<leader>mgT", mia.generator.add_table, { desc = "Add Table" })
    vim.keymap.set("n", "<leader>mgl", mia.generator.add_link, { desc = "Add Link" })
    vim.keymap.set("n", "<leader>mgi", mia.generator.add_image, { desc = "Add Image" })
    vim.keymap.set("n", "<leader>mgf", mia.generator.add_footnote, { desc = "Add Footnote" })
    vim.keymap.set("n", "<leader>mgc", mia.generator.add_code_block, { desc = "Add Code Block" })
    vim.keymap.set("n", "<leader>mgq", mia.generator.add_block_quote, { desc = "Add Block Quote" })
    vim.keymap.set("n", "<leader>mgo", mia.generator.add_callout, { desc = "Add Callout" })
    vim.keymap.set("n", "<leader>mgr", mia.generator.add_reference_style_link, { desc = "Add Reference-Style Link" })
  end,
})
```

## 🚀 Usage

### Commands

If you set `add_commands = true` in your configuration, the following commands
will be available:

| Command                     | Description                                                                                                                                |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `:MiaPresent`               | Starts a slide-based presentation mode. Slides are separated by `---`.                                                                     |
| `:MiaToggleTask`            | Toggles the state of a list item: `item` -> `[ ] item` -> `[x] item` -> `item`.                                                            |
| `:MiaGenerateTOC`           | Generates or updates a Table of Contents. The TOC is wrapped in `<!-- TOC -->` and `<!-- /TOC -->` comments.                               |
| `:MiaAddCallout`            | Prompts to select a callout type and inserts a GFM callout block.                                                                          |
| `:MiaAddBlockQuote`         | Adds a block quote to the current line, with support for nesting.                                                                          |
| `:MiaAddTable`              | Prompts for the number of rows and columns and generates a Markdown table.                                                                 |
| `:MiaAddLink`               | Prompts for link text and a URL and inserts a Markdown link. The cursor is placed after the link.                                          |
| `:MiaGenerateImage`         | Prompts for image alt text and a URL and inserts a Markdown image link.                                                                    |
| `:MiaAddFootnote`           | Prompts for footnote text and inserts a footnote reference (with auto-incrementing number) and definition.                                 |
| `:MiaAddCodeBlock`          | Prompts for a language and whether to tangle, then inserts a fenced code block with the cursor inside.                                     |
| `:MiaAddReferenceStyleLink` | Adds a reference-style link. If the reference already exists, it is reused. Otherwise, a new reference is added to the bottom of the file. |

### Presentation Mode

The presentation mode allows you to view your markdown file as a set of slides.
Each slide is separated by `---`.

You can also add a metadata block at the top of your file to configure the
header for your presentation. The header is split into three parts: left,
center, and a slide counter on the right.

```markdown
---
header_left: My Presentation
header_center: Chapter 1
---
# Slide 1

This is the first slide.

---
# Slide 2

This is the second slide.
```

