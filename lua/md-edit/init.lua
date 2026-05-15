-- md-edit.nvim
--
-- A plugin for markdown files.

local M = {}

local config = require("md-edit.config")

function M.setup(opts)
  config.options = vim.tbl_deep_extend("force", config.options, opts or {})

  -- Validate config
  if config.options.presentation.gutter_width <= 0 then
    vim.api.nvim_err_writeln("md-edit: gutter_width must be > 0, default to 1")
    config.options.presentation.gutter_width = 1
  end
end

M.presentation = require("md-edit.modules.presentation")

return M
