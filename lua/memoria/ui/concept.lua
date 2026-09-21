-- Concepts as the editor sees them: the pick-or-create picker, the prompts a
-- type's schema drives, and the list.
local M = {}

local atlas = require("memoria.modules.atlas")
local concept = require("memoria.modules.concept")
local config = require("memoria.config")
local message = require("memoria.ui.message")
local synapse = require("memoria.modules.synapse")
local synapse_lib = require("memoria.lib.synapse")
local ui_brain = require("memoria.ui.brain")

-- The picker's last entry, which is not a concept.
local CREATE = "+ Create new concept"

--- Ask for each meta key the type's schema names, then for any the concept
--- already carries that it does not, so nothing is dropped by being unasked.
--- An answer left empty removes the key; cancelling stops before any write.
---@param target memoria.Brain
---@param name string Concept name, for the prompt
---@param type? string Concept type, whose schema is asked for
---@param meta table<string, string> What it carries now
---@return table<string, string>? fields Nil when cancelled
local function ask_meta(target, name, type, meta)
  local cfg = config.load_brain_config(target.location)
  local keys = vim.deepcopy(concept.schema_fields(cfg, type))
  for _, key in ipairs(concept.unknown_fields(cfg, type, meta)) do
    table.insert(keys, key)
  end

  local fields = {}
  for _, key in ipairs(keys) do
    local answer = message.ask(message.in_brain(target.name, ("%s %s: "):format(name, key)), meta[key])
    if not answer then
      return nil
    end
    fields[key] = vim.trim(answer)
  end
  return fields
end

--- Register a concept: its name, its type, then whatever its type is asked for.
--- A `name` given is taken as given; a `suggest`ed one is only filled into the
--- prompt, for a mention that may want correcting before it becomes a name.
---@param target memoria.Brain
---@param opts { name?: string, suggest?: string, concept_type?: string }
---@param run fun(created: memoria.Concept)
local function create(target, opts, run)
  local name = opts.name
  if not name or vim.trim(name) == "" then
    name = message.ask(message.in_brain(target.name, "Concept name: "), opts.suggest)
  end
  if not name or vim.trim(name) == "" then
    return
  end

  local concept_type = message.ask(message.in_brain(target.name, "Type: "), opts.concept_type)
  if not concept_type or vim.trim(concept_type) == "" then
    return
  end

  local fields = ask_meta(target, vim.trim(name), vim.trim(concept_type), {})
  if not fields then
    return
  end

  local added, err = concept.create_concept(target.name, name, concept_type, fields)
  if not added then
    return message.error(message.in_brain(target.name, err --[[@as string]]))
  end
  run(added)
end

--- Pick a concept from the brain's registry, or register one. The interaction
--- shared by every place a concept is chosen — see |memoria-concepts|.
---@param target memoria.Brain Whose registry is picked from
---@param opts? { prompt?: string, name?: string, concept_type?: string } name: suggested when creating
---@param run fun(chosen: memoria.Concept) Called once something is chosen
function M.pick_or_create(target, opts, run)
  opts = opts or {}

  local concepts, err = concept.list(target.name)
  if not concepts then
    return message.error(message.in_brain(target.name, err --[[@as string]]))
  end
  local creating = { suggest = opts.name, concept_type = opts.concept_type }
  if #concepts == 0 then
    return create(target, creating, run)
  end

  -- The expected type first, never alone: the type is a hint, not a filter.
  local wanted, rest = {}, {}
  local by_name = {}
  for _, entry in ipairs(concepts) do
    by_name[entry.name] = entry
    table.insert(opts.concept_type and entry.type == opts.concept_type and wanted or rest, entry.name)
  end

  local items = vim.list_extend(wanted, rest)
  table.insert(items, CREATE)

  vim.ui.select(items, {
    prompt = message.in_brain(target.name, (opts.prompt or "Concept") .. ":"),
    format_item = function(item)
      local entry = by_name[item]
      return entry and entry.type and ("%s (%s)"):format(entry.name, entry.type) or item
    end,
  }, function(choice)
    if choice == CREATE then
      create(target, creating, run)
    elseif choice then
      run(by_name[choice])
    end
  end)
end

--- Create a concept in a brain: its name, its type, then its type's fields.
---@param brain_name? string Brain name, default: resolved (see ui/brain.resolve)
---@param name? string Concept name, asked for when not given
function M.create_concept(brain_name, name)
  ui_brain.resolve(brain_name, function(target)
    create(target, { name = name }, function(created)
      message.info(message.in_brain(target.name, ("created %s"):format(created.name)))
    end)
  end)
end

--- Put a concept in one of the current engram's concept fields, asking for
--- whatever `opts` leaves out: the field, then the concept, from those of the
--- field's `concept_type` first. The engram decides the brain.
---@param opts? { source?: string, field?: string, concept?: string }
function M.attach_concept(opts)
  opts = opts or {}

  local source = opts.source or vim.api.nvim_buf_get_name(0)
  local located, err = synapse.locate(source)
  if not located then
    return message.error(err --[[@as string]])
  end

  local target = located.brain
  local cfg = config.load_brain_config(target.location)

  ---@param field string
  ---@param name string
  local function finish(field, name)
    local attached, attach_err = concept.attach_concept({ source = source, field = field, concept = name })
    if not attached then
      return message.error(message.in_brain(target.name, attach_err --[[@as string]]))
    end
    message.info(
      message.in_brain(target.name, ("%s %s → %s"):format(attached.source, attached.field, attached.concept))
    )
  end

  ---@param field string
  local function pick_concept(field)
    if opts.concept then
      return finish(field, opts.concept)
    end
    M.pick_or_create(target, { prompt = field, concept_type = cfg.synapses[field].concept_type }, function(chosen)
      finish(field, chosen.name)
    end)
  end

  local fields = synapse_lib.field_names(cfg.synapses, "concept")
  if opts.field then
    if not vim.tbl_contains(fields, opts.field) then
      return message.error(message.in_brain(target.name, ("no concept field '%s'"):format(opts.field)))
    end
    pick_concept(opts.field)
  elseif #fields == 0 then
    message.warn(message.in_brain(target.name, "no concept fields configured"))
  elseif #fields == 1 then
    pick_concept(fields[1])
  else
    vim.ui.select(fields, { prompt = message.in_brain(target.name, "Concept field:") }, function(choice)
      if choice then
        pick_concept(choice)
      end
    end)
  end
end

--- Fill in a concept's meta, picked when not named.
---@param brain_name? string Brain name, default: resolved (see ui/brain.resolve)
---@param name? string Concept name, picked when not given
function M.set_concept_meta(brain_name, name)
  ui_brain.resolve(brain_name, function(target)
    ---@param chosen memoria.Concept
    local function fill(chosen)
      local fields = ask_meta(target, chosen.name, chosen.type, chosen.meta)
      if not fields then
        return
      end

      local written, err = concept.set_concept_meta(target.name, chosen.name, chosen.type, fields)
      if not written then
        return message.error(message.in_brain(target.name, err --[[@as string]]))
      end
      message.info(message.in_brain(target.name, ("wrote %s"):format(written.name)))
    end

    if not name or name == "" then
      return M.pick_or_create(target, {}, fill)
    end

    local chosen, err = concept.get(target.name, name)
    if not chosen then
      return message.error(message.in_brain(target.name, err --[[@as string]]))
    end
    fill(chosen)
  end)
end

--- Walk the concepts no entry answers to, most-used first: each one is either
--- registered under its own name, or attached to an existing concept as an
--- alias. The engrams are never touched.
---@param brain_name? string Brain name, default: resolved (see ui/brain.resolve)
function M.find_undeclared_concepts(brain_name)
  ui_brain.resolve(brain_name, function(target)
    local undeclared, err = concept.find_undeclared_concepts(target.name)
    if not undeclared then
      return message.error(message.in_brain(target.name, err --[[@as string]]))
    end
    if #undeclared == 0 then
      return message.info(message.in_brain(target.name, "no undeclared concepts"))
    end

    local filled = 0
    local function walk(index)
      if index > #undeclared then
        return message.info(message.in_brain(target.name, ("declared %d of %d"):format(filled, #undeclared)))
      end

      local mention = undeclared[index]
      M.pick_or_create(target, {
        name = mention.name,
        prompt = ("%s (%d engrams)"):format(mention.name, mention.count),
      }, function(chosen)
        -- An existing concept means the mention is another name for it.
        if chosen.name ~= mention.name then
          local aliased, alias_err = concept.add_alias(target.name, chosen.name, mention.name)
          if not aliased then
            return message.error(message.in_brain(target.name, alias_err --[[@as string]]))
          end
        end
        filled = filled + 1
        walk(index + 1)
      end)
    end

    walk(1)
  end)
end

--- Echo every concept by type: name, its aliases, how many engrams name it,
--- and ⚠ when none do.
---@param brain_name? string Brain name, default: resolved (see ui/brain.resolve)
function M.print_list(brain_name)
  ui_brain.resolve(brain_name, function(target)
    local concepts, err = concept.list(target.name)
    if not concepts then
      return message.error(message.in_brain(target.name, err --[[@as string]]))
    end
    if #concepts == 0 then
      return message.info(message.in_brain(target.name, "no concepts registered"))
    end

    local current = atlas.refresh(target) or { concepts = {} }
    local width = 0
    for _, entry in ipairs(concepts) do
      width = math.max(width, #entry.name)
    end

    -- By type, then by name inside it: the list answers "what is in this
    -- brain", and the type is how you read it.
    table.sort(concepts, function(a, b)
      local left, right = a.type or "", b.type or ""
      return left == right and a.name < b.name or left < right
    end)

    local chunks, shown = {}, nil
    for _, entry in ipairs(concepts) do
      local group = entry.type or "(no type)"
      if group ~= shown then
        table.insert(chunks, { (shown and "\n" or "") .. group .. "\n", "Title" })
        shown = group
      end

      table.insert(chunks, { "  " .. entry.name .. string.rep(" ", width - #entry.name + 2) })
      local count = #(current.concepts[entry.name] or {})
      table.insert(chunks, { ("%d engrams"):format(count) })
      if #entry.aliases > 0 then
        table.insert(chunks, { "  " .. table.concat(entry.aliases, ", "), "Comment" })
      end
      if count == 0 then
        table.insert(chunks, { "  ⚠ unused", "WarningMsg" })
      end
      table.insert(chunks, { "\n" })
    end

    vim.api.nvim_echo(chunks, false, {})
  end)
end

return M
