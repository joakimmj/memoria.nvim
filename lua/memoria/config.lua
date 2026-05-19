-- lua/memoria/config.lua

local M = {}

M.options = {
  -- Add user commands for all functions in the plugin.
  -- default: false
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

    keymaps = {
      next = "n",
      previous = "p",
      quit = "q",
    },
  },
}

return M
