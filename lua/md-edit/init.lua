-- md-edit.nvim
--
-- A plugin for markdown files.

local M = {}

local config = require("md-edit.config")

function M.setup(opts)
  config.options = vim.tbl_deep_extend("force", config.options, opts or {})
end

M.presentation = require("md-edit.modules.presentation")

return M
