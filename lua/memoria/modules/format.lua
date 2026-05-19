-- lua/memoria/modules/format.lua

local M = {}

local function toggle_format(pattern)
  local bufnr = vim.api.nvim_get_current_buf()
  local start_pos = vim.api.nvim_buf_get_mark(0, "'<")
  local end_pos = vim.api.nvim_buf_get_mark(0, "'>")
  local selection = vim.api.nvim_buf_get_text(bufnr, start_pos[1] - 1, start_pos[2], end_pos[1] - 1, end_pos[2] + 1, {})[1]
  local new_text

  if selection:sub(1, #pattern) == pattern and selection:sub(-#pattern) == pattern then
    new_text = selection:sub(#pattern + 1, -#pattern - 1)
  else
    new_text = pattern .. selection .. pattern
  end

  vim.api.nvim_buf_set_text(bufnr, start_pos[1] - 1, start_pos[2], end_pos[1] - 1, end_pos[2] + 1, { new_text })
end

function M.toggle_bold()
  toggle_format("**")
end

function M.toggle_italic()
  toggle_format("*")
end

function M.toggle_strikethrough()
  toggle_format("~~")
end

function M.toggle_inline_code()
  toggle_format("`")
end

return M
