-- lua/memoria/modules/generator.lua

local M = {}

function M.generate_toc()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Find existing TOC
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local toc_start, toc_end
  for i, line in ipairs(lines) do
    if string.find(line, "<!-- TOC -->", 1, true) then
      toc_start = i
    elseif string.find(line, "<!-- /TOC -->", 1, true) then
      toc_end = i
    end
  end

  local parser = vim.treesitter.get_parser(bufnr, "markdown")
  local tree = parser:parse()[1]
  local root = tree:root()

  local query = vim.treesitter.query.parse("markdown", "(atx_heading) @heading")
  local toc = { "<!-- TOC -->" }

  for _, match, _ in query:iter_captures(root, bufnr, 0, -1) do
    local start_row, _, _, _ = match:range()
    -- if we have a toc, and the heading is inside it, skip
    if not (toc_start and toc_end and start_row + 1 >= toc_start and start_row + 1 <= toc_end) then
      local node_text = vim.treesitter.get_node_text(match, bufnr)
      local level = 0
      for i = 1, #node_text do
        if node_text:sub(i, i) == "#" then
          level = level + 1
        else
          break
        end
      end
      local header_text = node_text:match("#+s*(.*)")
      if header_text then
        header_text = header_text:gsub("^%s+", ""):gsub("%s+$", "")
      end
      if header_text and header_text ~= "" then
        local link_text = header_text:gsub("[^%w%s-]", ""):gsub("%s", "-"):lower()
        table.insert(toc, string.rep("  ", level - 1) .. "- [" .. header_text .. "](#" .. link_text .. ")")
      end
    end
  end
  table.insert(toc, "<!-- /TOC -->")

  if toc_start and toc_end then
    vim.api.nvim_buf_set_lines(bufnr, toc_start - 1, toc_end, false, {}) -- Delete old TOC
    vim.api.nvim_buf_set_lines(bufnr, toc_start - 1, toc_start - 1, false, toc) -- Insert new TOC
  else
    vim.api.nvim_buf_set_lines(
      bufnr,
      vim.api.nvim_win_get_cursor(0)[1] - 1,
      vim.api.nvim_win_get_cursor(0)[1] - 1,
      false,
      toc
    )
  end
end

return M
