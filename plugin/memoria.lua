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
    vim.api.nvim_buf_create_user_command(bufnr, "MiaGenerateTOC", mia.generator.generate_toc, {})
    vim.api.nvim_buf_create_user_command(bufnr, "MiaAddCallout", mia.generator.add_callout, {})
    vim.api.nvim_buf_create_user_command(bufnr, "MiaAddTable", mia.generator.add_table, {})
    vim.api.nvim_buf_create_user_command(bufnr, "MiaAddLink", mia.generator.add_link, { range = true })
    vim.api.nvim_buf_create_user_command(bufnr, "MiaAddImage", mia.generator.add_image, {})
    vim.api.nvim_buf_create_user_command(bufnr, "MiaAddFootnote", mia.generator.add_footnote, {})
    vim.api.nvim_buf_create_user_command(bufnr, "MiaAddCodeBlock", mia.generator.add_code_block, {})
    vim.api.nvim_buf_create_user_command(bufnr, "MiaAddBlockQuote", mia.generator.add_block_quote, { range = true })
    vim.api.nvim_buf_create_user_command(bufnr, "MiaAddReferenceStyleLink", mia.generator.add_reference_style_link, { range = true })
  end,
})
