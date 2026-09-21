-- The CLI: its command table, argument parsing, user-config loading and JSON
-- output. Run by bin/mia. See |memoria-cli|.
local M = {}

local atlas = require("memoria.modules.atlas")
local brain = require("memoria.modules.brain")
local config = require("memoria.config")
local engram = require("memoria.modules.engram")
local file = require("memoria.lib.file")
local synapse = require("memoria.modules.synapse")
local synapse_lib = require("memoria.lib.synapse")

---@class memoria.CliArgument
---@field name string As typed, e.g. "--brain" or "<file>"
---@field description string One line
---@field value? string What it takes, e.g. "name"; nil for a flag
---@field required? boolean Must be given
---@field repeated? boolean May be given more than once

---@class memoria.CliArgs
---@field positional string[] In the order given
---@field options table<string, string|boolean|string[]> By name without "--"

---@class memoria.CliCommand
---@field name string As typed
---@field description string One line
---@field arguments memoria.CliArgument[] Positionals first, then options
---@field run fun(args: memoria.CliArgs): table?, string? Result, or nil and why not

-- The brain every brain-scoped command takes.
local BRAIN = { name = "--brain", value = "name", description = "The brain to act in" }

--- A map for JSON: empty encodes as an object rather than a list.
---@param map table
---@return table
local function object(map)
  return next(map) == nil and vim.empty_dict() or map
end

--- Resolve the brain a command acts in and run it there, naming the brain in
--- anything it answers, the way a prompt does.
---@param args memoria.CliArgs
---@param run fun(target: memoria.Brain, cfg: memoria.Config): table?, string?
---@return table? result
---@return string? err
local function in_brain(args, run)
  local target, err = brain.resolve(args.options.brain --[[@as string?]])
  if not target then
    return nil, err
  end

  local result, run_err = run(target, config.load_brain_config(target.location))
  if not result then
    return nil, ("(%s) %s"):format(target.name, run_err)
  end
  return result
end

--- An engram's atlas entry, as the CLI hands it out: its filename, its title,
--- when it changed, and one list per concept field.
---@param filename string
---@param entry memoria.AtlasEngram
---@param cfg memoria.Config Brain config
---@return table
local function engram_summary(filename, entry, cfg)
  local summary = { file = filename, title = entry.title, modified = entry.modified }
  for _, field in ipairs(synapse_lib.field_names(cfg.synapses, "concept")) do
    summary[field] = entry[field] or {}
  end
  return summary
end

--- Rebuild an atlas and hand back its problems with file, line and kind.
---@param target memoria.Brain
---@param fix boolean Repair what can be repaired first
---@return table? result
---@return string? err
local function rebuilt(target, fix)
  local result, err = atlas.rebuild_atlas(target.name, { fix = fix })
  if not result then
    return nil, err
  end

  local problems = {}
  for _, problem in ipairs(atlas.locate_problems(target, result.problems)) do
    table.insert(problems, {
      engram = problem.engram,
      file = problem.file,
      line = problem.line,
      kind = problem.kind,
      text = problem.text,
    })
  end

  return { brain = target.name, engrams = vim.tbl_count(result.atlas.engrams), problems = problems }
end

--- `--field name=value,value` into `opts.fields`, once per field.
---@param items? string[] What --field was given, once per time it was
---@return table<string, string[]>? fields
---@return string? err
local function parse_fields(items)
  local fields = {}
  for _, item in ipairs(items or {}) do
    local name, value = item:match("^([^=]+)=(.*)$")
    if not name then
      return nil, "--field takes name=value"
    end

    local values = fields[name] or {}
    for _, one in ipairs(vim.split(value, ",", { plain = true })) do
      one = vim.trim(one)
      if one ~= "" then
        table.insert(values, one)
      end
    end
    fields[name] = values
  end
  return fields
end

---@type memoria.CliCommand[]
-- A list, not a map: `commands` prints it, and Lua maps have no order.
M.commands = {
  {
    name = "brains",
    description = "Every registered brain",
    arguments = {},
    run = function()
      local brains = {}
      for _, entry in ipairs(brain.list()) do
        table.insert(brains, {
          name = entry.name,
          location = entry.location,
          exists = vim.fn.isdirectory(entry.location) == 1,
        })
      end
      return { brains = brains }
    end,
  },
  {
    name = "engrams",
    description = "Every engram in a brain, from the atlas",
    arguments = {
      BRAIN,
      { name = "--concept", value = "concept", description = "Only engrams naming this concept" },
    },
    run = function(args)
      return in_brain(args, function(target, cfg)
        local current, err = atlas.refresh(target)
        if not current then
          return nil, err
        end

        local names = vim.tbl_keys(current.engrams)
        local concept = args.options.concept --[[@as string?]]
        if concept then
          names = current.concepts[concept] or {}
        end
        table.sort(names)

        local engrams = {}
        for _, name in ipairs(names) do
          if current.engrams[name] then
            table.insert(engrams, engram_summary(name, current.engrams[name], cfg))
          end
        end
        return { brain = target.name, engrams = engrams }
      end)
    end,
  },
  {
    name = "engram",
    description = "One engram: its atlas entry, its backlinks and its content",
    arguments = {
      { name = "<file>", required = true, description = "Engram filename in the brain" },
      BRAIN,
    },
    run = function(args)
      return in_brain(args, function(target)
        local current, err = atlas.refresh(target)
        if not current then
          return nil, err
        end

        local filename = vim.fs.basename(args.positional[1])
        local entry = current.engrams[filename]
        if not entry then
          return nil, "no engram " .. filename
        end

        local path = target.location .. "/" .. filename
        local lines = file.read_lines(path)
        return {
          brain = target.name,
          file = filename,
          path = path,
          entry = vim.tbl_extend("force", entry, { synapses = object(entry.synapses) }),
          backlinks = current.backlinks[filename] or {},
          content = table.concat(lines or {}, "\n"),
        }
      end)
    end,
  },
  {
    name = "tasks",
    description = "The brain's tasks, by state",
    arguments = {
      BRAIN,
      { name = "--state", value = "state", description = "Only 'not_done' or 'done'" },
    },
    run = function(args)
      return in_brain(args, function(target)
        local state = args.options.state --[[@as string?]]
        if state and state ~= "not_done" and state ~= "done" then
          return nil, ("no task state '%s'; it is 'not_done' or 'done'"):format(state)
        end

        local current, err = atlas.refresh(target)
        if not current then
          return nil, err
        end

        local tasks = {}
        for _, name in ipairs({ "not_done", "done" }) do
          if not state or state == name then
            tasks[name] = current.tasks[name] or {}
          end
        end
        return { brain = target.name, tasks = tasks }
      end)
    end,
  },
  {
    name = "check",
    description = "Rebuild the atlas and report what is wrong",
    arguments = { BRAIN },
    run = function(args)
      return in_brain(args, function(target)
        return rebuilt(target, false)
      end)
    end,
  },
  {
    name = "rebuild",
    description = "Rebuild the atlas, optionally repairing it first",
    arguments = {
      BRAIN,
      { name = "--fix", description = "Write missing inverses and backfill SYNAPSES blocks" },
    },
    run = function(args)
      return in_brain(args, function(target)
        return rebuilt(target, args.options.fix == true)
      end)
    end,
  },
  {
    name = "create-engram",
    description = "Create an engram, with the same header as one written in the editor",
    arguments = {
      BRAIN,
      {
        name = "--title",
        value = "title",
        required = true,
        description = "Title as typed; the filename uses its slug",
      },
      {
        name = "--field",
        value = "name=value",
        repeated = true,
        description = "Concept field values, comma-separated; once per field",
      },
      { name = "--body", value = "text", description = "Prose put where %cursor% is; '-' reads stdin" },
    },
    run = function(args)
      return in_brain(args, function(target)
        local fields, err = parse_fields(args.options.field --[[@as string[]? ]])
        if not fields then
          return nil, err
        end

        local body = args.options.body --[[@as string?]]
        if body == "-" then
          body = io.read("*a")
        end

        local new, add_err = engram.create_engram(target.name, {
          title = args.options.title --[[@as string]],
          fields = fields,
          body = body,
        })
        if not new then
          return nil, add_err
        end
        return { brain = target.name, file = vim.fs.basename(new.path), path = new.path }
      end)
    end,
  },
  {
    name = "attach-synapse",
    description = "Link two engrams, writing the inverse on the other one",
    arguments = {
      { name = "<source>", required = true, description = "Engram the field is written on" },
      { name = "<field>", required = true, description = "Engram field, e.g. 'up'" },
      { name = "<target>", required = true, description = "Engram it points at" },
      BRAIN,
    },
    run = function(args)
      return in_brain(args, function(target)
        local source = target.location .. "/" .. vim.fs.basename(args.positional[1])
        local added, err = synapse.attach_synapse({
          source = source,
          field = args.positional[2],
          target = args.positional[3],
        })
        if not added then
          return nil, err
        end
        return added
      end)
    end,
  },
  {
    name = "commands",
    description = "Every command and its arguments",
    arguments = {},
    run = function()
      local commands = {}
      for _, command in ipairs(M.commands) do
        table.insert(commands, {
          name = command.name,
          description = command.description,
          arguments = command.arguments,
        })
      end
      return { commands = commands }
    end,
  },
}

--- A command by name.
---@param name string
---@return memoria.CliCommand?
function M.find(name)
  for _, command in ipairs(M.commands) do
    if command.name == name then
      return command
    end
  end
end

--- Read a command's arguments: "--opt value", "--flag", the rest positional.
---@param command memoria.CliCommand
---@param argv string[] Arguments after the command name
---@return memoria.CliArgs? args
---@return string? err What was wrong with them
function M.parse(command, argv)
  local args = { positional = {}, options = {} }

  local options, positionals = {}, {}
  for _, argument in ipairs(command.arguments) do
    if vim.startswith(argument.name, "--") then
      options[argument.name:sub(3)] = argument
    else
      table.insert(positionals, argument)
    end
  end

  local index = 1
  while index <= #argv do
    local token = argv[index]
    if vim.startswith(token, "--") then
      local name = token:sub(3)
      local argument = options[name]
      if not argument then
        return nil, ("unknown option '%s' for '%s'"):format(token, command.name)
      end

      ---@type string|boolean
      local value = true
      if argument.value then
        if argv[index + 1] == nil then
          return nil, ("%s needs a value"):format(token)
        end
        value, index = argv[index + 1], index + 1
      end

      if argument.repeated then
        local given = args.options[name] or {}
        table.insert(given, value)
        args.options[name] = given
      else
        args.options[name] = value
      end
    elseif #args.positional < #positionals then
      table.insert(args.positional, token)
    else
      local count = #positionals
      return nil, ("'%s' takes %d argument%s"):format(command.name, count, count == 1 and "" or "s")
    end
    index = index + 1
  end

  -- In table order, so a command missing two arguments always names the first.
  local at = 0
  for _, argument in ipairs(command.arguments) do
    local missing
    if vim.startswith(argument.name, "--") then
      missing = args.options[argument.name:sub(3)] == nil
    else
      at = at + 1
      missing = args.positional[at] == nil
    end
    if argument.required and missing then
      return nil, ("%s needs %s"):format(command.name, argument.name)
    end
  end

  return args
end

--- How a command is called: its arguments in order, the required ones bare
--- and the rest in brackets.
---@param command memoria.CliCommand
---@return string line
local function usage_line(command)
  local parts = { command.name }
  for _, argument in ipairs(command.arguments) do
    local text = argument.value and ("%s <%s>"):format(argument.name, argument.value) or argument.name
    table.insert(parts, argument.required and text or ("[%s]"):format(text))
  end
  return table.concat(parts, " ")
end

--- What `--help` prints: every command's usage line, or one command's with
--- what each of its arguments is for.
---@param name? string A command name, for that command's help
---@return string[] lines
function M.usage(name)
  local command = name and M.find(name)
  if not command then
    local lines = { "bin/mia <command> [--brain <name>] [args]", "" }
    for _, each in ipairs(M.commands) do
      table.insert(lines, "  " .. usage_line(each))
    end
    vim.list_extend(lines, { "", "bin/mia <command> --help   what one command takes" })
    return lines
  end

  local lines = { usage_line(command), "", command.description }
  if #command.arguments == 0 then
    return lines
  end

  local shown, width = {}, 0
  for _, argument in ipairs(command.arguments) do
    local text = argument.value and ("%s <%s>"):format(argument.name, argument.value) or argument.name
    width = math.max(width, #text)
    table.insert(shown, { text = text, argument = argument })
  end

  table.insert(lines, "")
  for _, each in ipairs(shown) do
    local notes = {}
    if each.argument.required then
      table.insert(notes, "required")
    end
    if each.argument.repeated then
      table.insert(notes, "repeatable")
    end

    local description = each.argument.description
    if #notes > 0 then
      description = ("%s (%s)"):format(description, table.concat(notes, ", "))
    end
    table.insert(lines, ("  %s  %s"):format(each.text .. string.rep(" ", width - #each.text), description))
  end
  return lines
end

--- Run one command. Nothing is printed here.
---@param argv string[] The command name and its arguments
---@return table? result
---@return string? err
function M.run(argv)
  local name = argv[1]
  if not name or name == "" then
    return nil, "no command given; 'commands' lists them, --help explains them"
  end

  local command = M.find(name)
  if not command then
    return nil, ("unknown command '%s'; 'commands' lists them, --help explains them"):format(name)
  end

  local args, err = M.parse(command, vim.list_slice(argv, 2))
  if not args then
    return nil, err
  end
  return command.run(args)
end

--- Send everything but the result to stderr, so stdout stays one JSON object.
--- `nvim -l` runs verbose, which would otherwise put `print` and `:echo` on
--- stdout.
local function to_stderr()
  _G.print = function(...)
    local parts = {}
    for index = 1, select("#", ...) do
      parts[index] = tostring((select(index, ...)))
    end
    io.stderr:write(table.concat(parts, "\t"), "\n")
  end

  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(text)
    io.stderr:write(tostring(text), "\n")
  end
end

--- Load the user's config, so an engram written here has the same header and
--- template as one written in the editor. $MEMORIA_INIT names the file to
--- source; "NONE" skips it and sets memoria up with its defaults. See
--- |memoria-cli-config|.
---@return boolean? ok
---@return string? err
function M.load_config()
  local init = vim.env.MEMORIA_INIT
  if not init or init == "" then
    init = vim.fn.stdpath("config") .. "/init.lua"
  end

  if init == "NONE" then
    return require("memoria").setup({})
  end

  if vim.fn.filereadable(init) == 0 then
    return nil, ("no config at %s; set $MEMORIA_INIT, or MEMORIA_INIT=NONE to skip it"):format(init)
  end

  local sourced, err = pcall(function()
    vim.cmd({ cmd = "source", args = { init }, mods = { silent = true } })
  end)
  if not sourced then
    return nil, ("%s: %s"):format(init, err)
  end

  -- Falling back to the built-in defaults here is exactly the engram in the
  -- wrong shape, so this refuses instead.
  if not config.configured then
    return nil,
      ('%s did not call require("memoria").setup() — memoria may be lazy-loaded on a command or key, '):format(init)
        .. "or md-drafting.nvim may be missing"
  end
  return true
end

--- The whole run: the user's config, the command, one JSON object on stdout.
---@param argv string[] `_G.arg`: the command name and its arguments
---@return integer status 0 when it worked, 1 otherwise
function M.main(argv)
  to_stderr()

  -- Help is for a person reading it, so it is plain text rather than the one
  -- JSON object every other run prints, and it loads no config: being told
  -- how to call something has to work when nothing else does.
  if vim.tbl_contains(argv, "--help") then
    io.stdout:write(table.concat(M.usage(argv[1]), "\n"), "\n")
    io.stdout:flush()
    return 0
  end

  local result, err
  local loaded, config_err = M.load_config()
  if loaded then
    result, err = M.run(argv)
  else
    err = config_err
  end

  io.stdout:write(vim.json.encode(result and { ok = true, result = result } or { ok = false, error = err }), "\n")
  io.stdout:flush()
  return result and 0 or 1
end

return M
