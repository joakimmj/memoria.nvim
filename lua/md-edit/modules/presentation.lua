-- lua/md-edit/modules/presentation.lua

local M = {}
local config = require("md-edit.config")

local state = {
  win_id = nil,
  bufnr = nil,
  slides = {},
  current_slide = 1,
  header_left = "",
  header_center = "",
}

local function show_slide()
  if not state.win_id then
    return
  end

  vim.api.nvim_buf_set_option(state.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_option(state.bufnr, "readonly", false)

  local display_lines = {}
  local total_width = vim.api.nvim_win_get_width(state.win_id)
  local total_height = vim.api.nvim_win_get_height(state.win_id)

  local gutter_width = 2 -- Approximation for signcolumn='yes'
  if
    vim.api.nvim_win_get_option(state.win_id, "number") or vim.api.nvim_win_get_option(state.win_id, "relativenumber")
  then
    gutter_width = gutter_width + vim.api.nvim_win_get_option(state.win_id, "numberwidth")
  end
  total_width = total_width - gutter_width

  -- Construct the new header
  local left_text = state.header_left or ""
  local center_text = state.header_center or ""
  local slide_counter = string.format("%d/%d", state.current_slide, #state.slides)

  -- Account for 1 space at each end
  local effective_total_width = total_width - 2

  local padding1 = math.floor((effective_total_width - #center_text) / 2) - #left_text
  if padding1 < 0 then
    padding1 = 0
  end

  local padding2 = effective_total_width - #left_text - padding1 - #center_text - #slide_counter
  if padding2 < 0 then
    padding2 = 0
  end

  local header_line_content = left_text
    .. string.rep(" ", padding1)
    .. center_text
    .. string.rep(" ", padding2)
    .. slide_counter
  header_line_content = header_line_content:sub(1, effective_total_width) -- Truncate if needed

  local header_line = " " .. header_line_content .. " "
  header_line = header_line:sub(1, total_width) -- Ensure it fits total_width
  table.insert(display_lines, header_line)

  -- Add the divider line
  table.insert(display_lines, string.rep("-", total_width))

  -- Add content
  local v_margin = 1
  for _ = 1, v_margin do
    table.insert(display_lines, "")
  end

  local current_content_lines = vim.split(state.slides[state.current_slide], "\n")
  for _, line in ipairs(current_content_lines) do
    table.insert(display_lines, line)
  end

  -- Add vertical padding to fill the rest of the screen
  local padding_needed = math.max(0, total_height - #display_lines)
  for _ = 1, padding_needed do
    table.insert(display_lines, "")
  end

  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, display_lines)
  vim.api.nvim_buf_set_option(state.bufnr, "modifiable", false)
  vim.api.nvim_buf_set_option(state.bufnr, "readonly", true)
  vim.cmd("doautocmd FileType markdown")
end

local function navigate(delta)
  if not state.win_id then
    return
  end
  local new_slide = state.current_slide + delta
  if new_slide >= 1 and new_slide <= #state.slides then
    state.current_slide = new_slide
    show_slide()
  end
end

local function close_presentation()
  if state.win_id then
    vim.api.nvim_win_close(state.win_id, true)
    state.win_id = nil
    state.bufnr = nil
  end
end

function M.start_presentation()
  local bufnr = vim.api.nvim_get_current_buf()

  state.slides = {}
  state.header_left = ""
  state.header_center = ""
  state.current_slide = 1

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local front_matter_end_line = 0

  -- Manually parse frontmatter
  if #lines > 1 and lines[1] == "---" then
    for i = 2, #lines do
      local line = lines[i]
      if line == "---" then
        front_matter_end_line = i
        break
      else
        local key, value = line:match("([^:]+):%s*(.*)")
        if key and value then
          key = key:gsub("^%s*(.-)%s*$", "%1")
          value = value:gsub("^%s*(.-)%s*$", "%1")
          if key == "header_left" then
            state.header_left = value
          elseif key == "header_center" then
            state.header_center = value
          end
        end
      end
    end
  end

  -- Manually split slides
  local current_slide_content = {}
  for i = front_matter_end_line + 1, #lines do
    local line = lines[i]
    -- A thematic break is ---, ***, or ___
    if line:match("^%s*([%-%*%_])%s*%1%s*%1%s*%s*$") then
      if #current_slide_content > 0 then
        table.insert(state.slides, table.concat(current_slide_content, "\n"))
        current_slide_content = {}
      end
    else
      table.insert(current_slide_content, line)
    end
  end

  if #current_slide_content > 0 then
    table.insert(state.slides, table.concat(current_slide_content, "\n"))
  end

  -- trim whitespace from slides
  for i, slide in ipairs(state.slides) do
    state.slides[i] = slide:gsub("^%s*(.-)%s*$", "%1")
  end

  if #state.slides == 0 then
    vim.api.nvim_err_writeln("No slides found. Separate slides with '---'.")
    return
  end

  state.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(state.bufnr, "filetype", "markdown")
  vim.api.nvim_buf_set_option(state.bufnr, "modifiable", false)
  vim.api.nvim_buf_set_option(state.bufnr, "readonly", true)
  vim.api.nvim_buf_set_option(state.bufnr, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(state.bufnr, "swapfile", false)
  vim.api.nvim_buf_set_option(state.bufnr, "wrap", false)

  local total_width = tonumber(vim.api.nvim_get_option("columns"))
  local total_height = tonumber(vim.api.nvim_get_option("lines"))
  local content_win_opts = {
    relative = "editor",
    width = total_width,
    height = total_height,
    row = 0,
    col = 0,
    style = "minimal",
    border = "none",
  }

  state.win_id = vim.api.nvim_open_win(state.bufnr, true, content_win_opts)

  vim.api.nvim_win_set_option(state.win_id, "number", config.options.presentation.show_line_numbers)
  vim.api.nvim_win_set_option(state.win_id, "relativenumber", config.options.presentation.show_relative_line_numbers)
  vim.api.nvim_win_set_option(state.win_id, "signcolumn", "yes")
  vim.api.nvim_win_set_option(state.win_id, "winhighlight", "Normal:Normal")
  vim.api.nvim_win_set_option(state.win_id, "numberwidth", config.options.presentation.gutter_width)

  show_slide()

  local keymaps = config.options.presentation.keymaps
  vim.keymap.set("n", keymaps.next, function()
    navigate(1)
  end, { buffer = state.bufnr, silent = true })
  vim.keymap.set("n", keymaps.previous, function()
    navigate(-1)
  end, { buffer = state.bufnr, silent = true })
  vim.keymap.set("n", keymaps.quit, close_presentation, { buffer = state.bufnr, silent = true })
end

return M
