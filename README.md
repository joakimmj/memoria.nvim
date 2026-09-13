# memoria.nvim

`memoria.nvim` is a note taking plugin.

## 📦 Installation

<details>
  <summary>vim.pack</summary>

  Built into Neovim 0.12 and later.

  ```lua
  vim.pack.add({
    "https://github.com/joakimmj/memoria.nvim",
  })
  ```
</details>

<details>
  <summary>lazy.nvim</summary>

  ```lua
  {
    "joakimmj/memoria.nvim",
    -- Optional: ft = "markdown",
  }
  ```
</details>

<details>
  <summary>packer.nvim</summary>

  ```lua
  use "joakimmj/memoria.nvim"
  ```
</details>

> [!IMPORTANT]
> - Requires Neovim 0.10 or later
> - `nvim-treesitter` with the `markdown` and `markdown_inline` parsers
> - [md-drafting.nvim](https://github.com/joakimmj/md-drafting.nvim)

