-- lua/memoria/modules/generator.lua

local M = {}

local function get_visual_selection()
  local start_pos = vim.api.nvim_buf_get_mark(0, "<")
  local end_pos = vim.api.nvim_buf_get_mark(0, ">")
  if start_pos[1] == 0 or end_pos[1] == 0 or (start_pos[1] == end_pos[1] and start_pos[2] == end_pos[2]) then
    return nil
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_pos[1] - 1, end_pos[1], false)
  if #lines == 0 then
    return nil
  end
  if #lines == 1 then
    lines[1] = lines[1]:sub(start_pos[2] + 1, end_pos[2] + 1)
  else
    lines[1] = lines[1]:sub(start_pos[2] + 1)
    lines[#lines] = lines[#lines]:sub(1, end_pos[2] + 1)
  end
  return {
    text = table.concat(lines, "\n"),
    start_line = start_pos[1],
    start_col = start_pos[2],
    end_line = end_pos[1],
    end_col = end_pos[2],
  }
end

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
    vim.api.nvim_buf_set_lines(bufnr, toc_start - 1, toc_end, false, {})        -- Delete old TOC
    vim.api.nvim_buf_set_lines(bufnr, toc_start - 1, toc_start - 1, false, toc) -- Insert new TOC
  else
    vim.api.nvim_buf_set_lines(bufnr, vim.api.nvim_win_get_cursor(0)[1] - 1, vim.api.nvim_win_get_cursor(0)[1] - 1, false,
      toc)
  end
end

function M.add_table()
  local ok, cols = pcall(vim.fn.input, "Enter number of columns: ")
  if not ok then
    return
  end
  cols = tonumber(cols)

  if not cols or cols <= 0 then
    vim.api.nvim_err_writeln("Invalid input. Please enter a positive number for columns.")
    return
  end

  local tbl = {}
  local header = "| " .. string.rep("Header | ", cols)
  table.insert(tbl, header)

  local separator = "| " .. string.rep("--- | ", cols)
  table.insert(tbl, separator)

  local row = "| " .. string.rep("      | ", cols)
  table.insert(tbl, row)

  vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)[1] - 1,
    vim.api.nvim_win_get_cursor(0)[1] - 1, false, tbl)
end

local function getLinkDetailsFromSelection(bufnr)
  local selection = get_visual_selection()
  if not selection or selection.text == "" then
    return nil -- No valid selection, or empty selection
  end

  return {
    link_text_with_brackets = "[" .. selection.text .. "]",
    start_line = selection.start_line - 1,
    start_col = selection.start_col,
    end_line = selection.end_line - 1,
    end_col = selection.end_col + 1,
  }
end

local function getLinkDetails(bufnr)
  local ok, link_text = pcall(vim.fn.input, "Enter link text: ")
  if not ok or not link_text or link_text == "" then
    return nil -- User cancelled or entered empty text
  end

  local lnum, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line_content = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
  local cursor_col_1 = col + 1

  -- Find the end of the word at/before the cursor
  local word_end_pos = cursor_col_1
  if word_end_pos > 1 and line_content:sub(word_end_pos, word_end_pos):match("%s") then
    word_end_pos = word_end_pos - 1
  end
  while word_end_pos > 1 and line_content:sub(word_end_pos - 1, word_end_pos - 1):match("%S") do
    word_end_pos = word_end_pos - 1
  end
  while word_end_pos <= #line_content and line_content:sub(word_end_pos, word_end_pos):match("%S") do
    word_end_pos = word_end_pos + 1
  end

  local start_col_0 = word_end_pos - 1
  local end_col_0 = start_col_0

  -- Consume one space after the word if it exists
  if word_end_pos <= #line_content and line_content:sub(word_end_pos, word_end_pos) == " " then
    end_col_0 = end_col_0 + 1
  end

  local link_text_with_brackets = "[" .. link_text .. "]"
  if start_col_0 > 0 then
    link_text_with_brackets = " " .. link_text_with_brackets
  end

  return {
    link_text_with_brackets = link_text_with_brackets,
    start_line = lnum - 1,
    start_col = start_col_0,
    end_line = lnum - 1,
    end_col = end_col_0,
  }
end

local function isVisualMode(opts)
  if opts == nil then
    local current_mode = vim.api.nvim_get_mode().mode
    return current_mode == "v" or current_mode == "V"
  else
    return opts.range > 0
  end
end

function M.add_link(opts)
  local bufnr = vim.api.nvim_get_current_buf()

  local details
  if isVisualMode(opts) then
    details = getLinkDetailsFromSelection(bufnr)
  else
    details = getLinkDetails(bufnr)
  end

  if not details then
    return -- User cancelled link text input, or no valid selection
  end

  local ok, url = pcall(vim.fn.input, "Enter URL: ")
  if not ok or not url or url == "" then
    return -- User cancelled URL input
  end

  local final_link_content = details.link_text_with_brackets .. "(" .. url .. ")"

  vim.api.nvim_buf_set_text(
    bufnr,
    details.start_line,
    details.start_col,
    details.end_line,
    details.end_col,
    { final_link_content }
  )
  vim.api.nvim_win_set_cursor(0, { details.start_line + 1, details.start_col + #final_link_content })
end

function M.add_image()
  local ok, alt_text = pcall(vim.fn.input, "Enter image alt text: ")
  if not ok then
    return
  end
  local ok, url = pcall(vim.fn.input, "Enter image URL: ")
  if not ok then
    return
  end

  if not url or url == "" then
    vim.api.nvim_err_writeln("Invalid input. Please enter an image URL.")
    return
  end

  local image = "![" .. alt_text .. "](" .. url .. ")"
  vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)[1] - 1,
    vim.api.nvim_win_get_cursor(0)[1] - 1, false, { image })
end

function M.add_footnote()
  local bufnr = vim.api.nvim_get_current_buf()
  local ok, text = pcall(vim.fn.input, "Enter footnote text: ")
  if not ok then
    return
  end

  if not text or text == "" then
    vim.api.nvim_err_writeln("Invalid input. Please enter footnote text.")
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local max_num = 0
  for _, line in ipairs(lines) do
    for num_str in line:gmatch("%[%^([%d]+)%]") do
      local num = tonumber(num_str)
      if num and num > max_num then
        max_num = num
      end
    end
  end
  local footnote_num = max_num + 1

  local footnote_marker = "[^" .. footnote_num .. "]"
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local lnum = cursor_pos[1]
  local col = cursor_pos[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]

  local new_line = line:sub(1, col + 1) .. footnote_marker .. line:sub(col + 2)
  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { new_line })
  vim.api.nvim_win_set_cursor(0, { lnum, col + #footnote_marker })

  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", "[^" .. footnote_num .. "]: " .. text })
end

function M.add_code_block()
  local ok, lang = pcall(vim.fn.input, "Enter programming language (default: empty): ")
  if not ok then
    return
  end
  local ok, tangle = pcall(vim.fn.input, "Tangle this code block? (y/n): ", "n")
  if not ok then
    return
  end

  local info_string = lang
  if tangle:lower() == "y" then
    local ok, dest = pcall(vim.fn.input, "Enter destination file: ")
    if not ok then
      return
    end
    if dest and dest ~= "" then
      info_string = info_string .. ' { "tangle": true, "dest": "' .. dest .. '" }'
    else
      info_string = info_string .. ' { "tangle": true }'
    end
  end

  local code_block = {
    "```" .. info_string,
    "",
    "```",
  }
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), cursor_line - 1, cursor_line - 1, false, code_block)
  vim.api.nvim_win_set_cursor(0, { cursor_line + 1, 0 })
end

function M.add_block_quote()
  local bufnr = vim.api.nvim_get_current_buf()
  local start_line, end_line

  -- Check for visual selection
  local start_pos = vim.api.nvim_buf_get_mark(0, "<")
  local end_pos = vim.api.nvim_buf_get_mark(0, ">")
  if start_pos[1] ~= 0 and end_pos[1] ~= 0 then
    start_line = start_pos[1]
    end_line = end_pos[1]
  else
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    start_line = cursor_pos[1]
    end_line = cursor_pos[1]
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local new_lines = {}

  for _, line in ipairs(lines) do
    if line:match("^%s*$") then -- Empty or whitespace-only line
      table.insert(new_lines, "> ")
    elseif line:match("^> ") then
      table.insert(new_lines, ">" .. line)
    else
      table.insert(new_lines, "> " .. line)
    end
  end

  vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, new_lines)

  -- Move cursor to the end of the line if it was a single empty line
  if #lines == 1 and lines[1]:match("^%s*$") then
    vim.api.nvim_win_set_cursor(0, { start_line, #new_lines[1] })
  end
end

function M.add_callout()
  local config = require("memoria.config")
  local callout_types = config.options.callout_types

  vim.ui.select(callout_types, { prompt = "Select callout type:" }, function(choice)
    if not choice then
      return
    end

    local callout = {
      "> [!" .. choice .. "]",
      "> ",
    }

    local bufnr = vim.api.nvim_get_current_buf()
    local cursor_pos = vim.api.nvim_win_get_cursor(0)

    local parser = vim.treesitter.get_parser(bufnr, "markdown")
    local tree = parser:parse()[1]
    local root = tree:root()

    local node_at_cursor = root:descendant_for_range(cursor_pos[1] - 1, cursor_pos[2], cursor_pos[1] - 1, cursor_pos[2])

    local bq_node
    local temp_node = node_at_cursor
    while temp_node do
      if temp_node:type() == "block_quote" then
        bq_node = temp_node
        break
      end
      temp_node = temp_node:parent()
    end

    local insert_line_num = cursor_pos[1]
    if bq_node then
      local start_row, _, _, _ = bq_node:range()
      insert_line_num = start_row + 1
    end

    vim.api.nvim_buf_set_lines(bufnr, insert_line_num - 1, insert_line_num - 1, false, callout)
    vim.api.nvim_win_set_cursor(0, { insert_line_num, 3 })
  end)
end

function M.add_reference_style_link()
  local ok, text = pcall(vim.fn.input, "Enter link text: ")
  if not ok or not text or text == "" then
    return
  end

  local ok, ref_name = pcall(vim.fn.input, "Enter reference name (default: link text): ", text)
  if not ok then
    return
  end
  if ref_name == "" then
    ref_name = text
  end

  local bufnr = vim.api.nvim_get_current_buf()

  local parser = vim.treesitter.get_parser(bufnr, "markdown")
  local tree = parser:parse()[1]
  local root = tree:root()

  local query = vim.treesitter.query.parse("markdown", "(link_reference_definition) @def")
  local ref_exists = false
  if query then
    for id, node, metadata in query:iter_captures(root, bufnr) do
      for child in node:iter_children() do
        if child:type() == "link_label" then
          local label_text = vim.treesitter.get_node_text(child, bufnr)
          if label_text == "[" .. ref_name .. "]" then
            ref_exists = true
            break
          end
        end
      end
      if ref_exists then
        break
      end
    end
  end

  local url
  if not ref_exists then
    url = vim.fn.input("Enter URL: ")
    if not url or url == "" then
      return
    end
  end

  local link = "[" .. text .. "][" .. ref_name .. "]"
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local lnum = cursor_pos[1]
  local col = cursor_pos[2]
  local current_line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]

  local new_line = current_line:sub(1, col) .. link .. current_line:sub(col + 1)
  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { new_line })
  vim.api.nvim_win_set_cursor(0, { lnum, col + #link })

  if not ref_exists then
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", "[" .. ref_name .. "]: " .. url })
  end
end

return M
