-- plugin/md-edit.lua

local config = require("md-edit.config")
local main = require("md-edit")

vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  group = vim.api.nvim_create_augroup("md-edit-commands", { clear = true }),
  callback = function(event)
    if not config.options.add_commands then
      return
    end

    local bufnr = event.buf
    vim.api.nvim_buf_create_user_command(bufnr, "MDPresent", main.presentation.start_presentation, {})
  end,
})
