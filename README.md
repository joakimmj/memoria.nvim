# memoria.nvim

`memoria.nvim` is a Neovim plugin that provides a suite of tools for note
taking, enhanced Markdown editing and a built-in presentation mode. The plugin
is designed to be lightweight, configurable, and easy to use.

## ✨ Features

- **Presentation Mode:** View your markdown file as a slide deck directly
  within Neovim.

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

## ⚙️ Configuration

`memoria.nvim` is configured through its `setup()` function. Here is an example
configuration with all the default values:

```lua
require("memoria").setup({
  -- Add user commands for all functions in the plugin.
  -- Default: false
  add_commands = false,

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
    vim.keymap.set("n", "<leader>mps", mia.presentation.start_presentation, { desc = "Start Presentation" })
  end,
})
```

## 🚀 Usage

### Commands

If you set `add_commands = true` in your configuration, the following commands
will be available:


| Command       | Description                                                            |
| ------------- | ---------------------------------------------------------------------- |
| `:MiaPresent` | Starts a slide-based presentation mode. Slides are separated by `---`. |

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

