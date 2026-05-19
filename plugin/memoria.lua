-- plugin/memoria.lua

local config = require("memoria.config")
local mia = require("memoria")

vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  group = vim.api.nvim_create_augroup("memoria-commands", { clear = true }),
  callback = function(event)
    if not config.options.add_commands then
      return
    end

    local bufnr = event.buf
    vim.api.nvim_buf_create_user_command(bufnr, "MiaPresent", mia.presentation.start_presentation, {})
    vim.api.nvim_buf_create_user_command(bufnr, "MiaToggleTask", mia.task.toggle, {})
  end,
})
