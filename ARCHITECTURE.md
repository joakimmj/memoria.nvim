## Table of contents

- [Part 1 — md-drafting.nvim](#part-1-md-draftingnvim)
  - [1. Exposure model](#1-exposure-model)
    - [1.1 Module layout](#11-module-layout)
  - [2. Actions menus](#2-actions-menus)
  - [3. Text formatting](#3-text-formatting)
  - [4. Task cycling](#4-task-cycling)
  - [5. TOC generation](#5-toc-generation)
  - [6. Quotes and callouts](#6-quotes-and-callouts)
  - [7. Generators](#7-generators)
    - [7.1 Table](#71-table)
    - [7.2 Footnote](#72-footnote)
    - [7.3 Link](#73-link)
    - [7.4 Reference-style link](#74-reference-style-link)
    - [7.5 Image](#75-image)
    - [7.6 Code block](#76-code-block)
  - [8. Jump navigation — next/previous target](#8-jump-navigation-nextprevious-target)
  - [9. Focused view](#9-focused-view)
    - [9.1 Why a floating window](#91-why-a-floating-window)
    - [9.2 `focused_view` — the shared internal primitive](#92-focused_view-the-shared-internal-primitive)
  - [10. Presentation mode](#10-presentation-mode)
  - [11. Typewriter scrolling](#11-typewriter-scrolling)
  - [12. Focus mode](#12-focus-mode)
    - [12.1 Color scheme adjustment — scoped, not global](#121-color-scheme-adjustment-scoped-not-global)
    - [12.2 Stats](#122-stats)
  - [13. Config](#13-config)
  - [14. Open items](#14-open-items)
- [Part 2 — Using md-drafting.nvim from another plugin](#part-2-using-md-draftingnvim-from-another-plugin)
  - [1. Syntax utilities](#1-syntax-utilities)
  - [2. Fenced sections](#2-fenced-sections)
  - [3. Link providers](#3-link-providers)
- [Part 3 — memoria.nvim](#part-3-memorianvim)
  - [1. Vocabulary and the dependency](#1-vocabulary-and-the-dependency)
    - [1.1 Dependency: `md-drafting.nvim`](#11-dependency-md-draftingnvim)
    - [1.2 Installation and the missing-dependency case](#12-installation-and-the-missing-dependency-case)
    - [1.3 Module layout](#13-module-layout)
  - [2. Brains](#2-brains)
    - [2.1 Registry](#21-registry)
    - [2.2 Commands](#22-commands)
    - [2.3 Brain contents (flat, no subfolders)](#23-brain-contents-flat-no-subfolders)
  - [3. Configuration layers](#3-configuration-layers)
    - [3.1 Config resolution](#31-config-resolution)
  - [4. Filenames](#4-filenames)
    - [4.1 Concept-prefix selection](#41-concept-prefix-selection)
  - [5. Synapses (engram-to-engram connections)](#5-synapses-engram-to-engram-connections)
    - [5.1 Where they live](#51-where-they-live)
    - [5.2 Field config](#52-field-config)
    - [5.3 Format rules](#53-format-rules)
    - [5.4 Write (regenerate block)](#54-write-regenerate-block)
    - [5.5 Parse](#55-parse)
    - [5.6 attach_synapse (inverse sync)](#56-attach_synapse-inverse-sync)
  - [6. Concepts (persons, topics, etc.)](#6-concepts-persons-topics-etc)
    - [6.1 Storage — `mia_concepts.json`, keyed by name](#61-storage-mia_conceptsjson-keyed-by-name)
    - [6.2 Concept type schemas (config, under `concepts` in `setup({})`)](#62-concept-type-schemas-config-under-concepts-in-setup)
    - [6.3 Resolving mentions](#63-resolving-mentions)
    - [6.4 Finding & filling in undeclared concepts](#64-finding-filling-in-undeclared-concepts)
  - [7. Atlas (index)](#7-atlas-index)
    - [7.1 Storage — `.mia_atlas.json` (hidden)](#71-storage-mia_atlasjson-hidden)
    - [7.2 Rebuild / consistency check](#72-rebuild-consistency-check)
  - [8. Creating and appending to engrams](#8-creating-and-appending-to-engrams)
    - [8.1 `create_engram(brain_name, opts?)`](#81-create_engrambrain_name-opts)
    - [8.2 `append_to_engram(brain_name, engram_file, template_name, input?)`](#82-append_to_engrambrain_name-engram_file-template_name-input)
  - [9. Navigation & index](#9-navigation-index)
    - [9.1 Navigation history](#91-navigation-history)
    - [9.2 Link-or-create at cursor](#92-link-or-create-at-cursor)
    - [9.3 Generated index](#93-generated-index)
    - [9.4 Agenda](#94-agenda)
    - [9.5 Diary / quick-open](#95-diary-quick-open)
    - [9.6 Engram search](#96-engram-search)
  - [10. Renaming and deleting engrams](#10-renaming-and-deleting-engrams)
    - [10.1 `rename_engram(brain_name, engram_path, new_title?)`](#101-rename_engrambrain_name-engram_path-new_title)
    - [10.2 `delete_engram(brain_name, engram_path, opts?)`](#102-delete_engrambrain_name-engram_path-opts)
  - [11. The CLI](#11-the-cli)
    - [11.1 Invocation and config](#111-invocation-and-config)
    - [11.2 Output](#112-output)
    - [11.3 Commands](#113-commands)
    - [11.4 Running beside the editor](#114-running-beside-the-editor)
  - [12. Decisions](#12-decisions)

---

# Part 1 — md-drafting.nvim

Design principles:

- **No plugin-owned keybinds**, except presentation mode (navigation only makes
  sense inside its own modal view, so it's the one exception).
- **Fixed markers, not configurable** — the TOC and any other fenced-section
  mechanism always use the same constant marker shape, so any downstream tool
  (including `memoria.nvim`) can rely on them.
- **Functions first, commands optional** — every feature is a Lua function;
  `:Md*` commands are generated only when `add_commands = true`.
- **Extensible via registration, not forks** — the one feature that could
  plausibly want extra sources, the link generator, exposes a registration API
  rather than requiring a dependent plugin to reimplement the whole feature.

---

## 1. Exposure model

Every feature ships as a plain Lua function, grouped by module:

```lua
require("md-drafting").format.toggle_bold()
require("md-drafting").generator.generate_toc()
require("md-drafting").task.toggle()
require("md-drafting").jump.next("heading")
```

Users bind these themselves — the plugin never calls `vim.keymap.set` on their
behalf (except presentation mode, §10).

When `add_commands = true`, each function also gets a matching buffer-local user
command, created on the `markdown` filetype:

```
:MdToggleBold
:MdGenerateToc
:MdToggleTask
```

`add_commands = false` is the default.

### 1.1 Module layout

Which directory a file sits in says what may call it:

| Path | Contents | Reached from outside as |
|---|---|---|
| `modules/` | One file per feature — `format`, `task`, `generator`, `jump`, `presentation`, `focus`, `typewriter` | a field on the plugin table |
| `syntax/` | Every markdown construct the plugin knows, one file each | `api.syntax` (Part 2 §1) |
| `lib/` | Shared machinery — `actions`, `section`, `link_providers`, `file_browser`, `focused_view`, `util`, `text` | only where a section below says so |

`lib/` is the one worth saying out loud, because it is mixed: `actions` is
re-exported on the plugin table (§2), `section` under `api` (Part 2 §2) and
`link_providers.register` under `api` as `register_link_provider` (Part 2 §3),
while `file_browser` (the walk behind the built-in `File or URL` provider) and
`focused_view` (§9) are deliberately internal, and `util` (buffer, cursor,
selection, prompt, treesitter root, the minimal-span buffer write
`replace_lines`) and `text` (string handling that is not markdown) are helpers
with no contract at all. Nothing outside the plugin
requires a `lib/` path directly — what is meant to be reached has a name on the
plugin table or under `api`.

---

## 2. Actions menus

A picker over registered actions, so one mapping reaches many features rather
than one mapping per feature. The menus hold no knowledge of what is in them —
entries are registered into them, including by users adding their own:

```lua
actions.register(menu, { label, run(opts) })      -- performed once chosen
actions.register(menu, { label, prepare(opts) })  -- resolves its target while the
                                                  -- menu is built, returns the run
actions.open_menu(names, opts?)   -- one menu name, or a list of them
actions.open_all(opts?)           -- every action, whichever menu it is in
actions.menu_names()              -- the registered names, sorted
```

Actions are grouped rather than flat: the plugin ships `formatting`, `insert`
and `view`, and a menu is created by registering into it. One picker over
every action in the plugin would be long enough to be worse than the mapping
it replaces, and a menu name is the natural thing to bind a key to. Opening
several at once is one picker, in registration order, and an action registered
to two of the menus asked for is offered once.

```
:MdActions              -- every action
:MdActions insert       -- one menu
:MdActions insert view  -- several, as one picker
```

`prepare` exists because `vim.ui.select` is asynchronous: visual mode is gone
by the time a choice comes back. Every entry acting on a selection registers a
`prepare`, never a `run`.


---

## 3. Text formatting

Toggle-style, works both ways:

- **Visual mode** — wraps the current selection in the style's markers;
  re-selecting already-wrapped text and toggling again unwraps it (toggle, not
  just wrap)
- **Normal mode on a word** — the word under the cursor is the region, so a bare
  toggle formats it and toggling again strips the markers back off
- **Normal/insert mode with no word** — inserts an empty wrapper pair at the
  cursor, cursor lands between them

| Function | Wrapper |
|---|---|
| `format.toggle_bold()` | `**text**` |
| `format.toggle_italic()` | `*text*` |
| `format.toggle_strikethrough()` | `~~text~~` |
| `format.toggle_inline_code()` | `` `text` `` |

Unwrapping recognises both shapes: the markers inside the selection
(`**world**` selected whole) and the markers just outside it (`world` selected
inside `**world**`), the latter only when a second marker pair does not sit
outside those, so `**` inside `****bold****` is not mistaken for the pair.

Reaching for a format mid-sentence does not drop out of insert mode: when the
toggle was started from insert mode, the cursor resumes typing where the
formatted text now ends.

`format.prepare(pattern, opts?)` resolves what to act on now and returns the
function that performs the toggle later — the shape the actions menu (§2)
requires.

---

## 4. Task cycling

Cycles the current line's checkbox state, full loop (no dead end). The markers
come from `task_states`, which groups them by meaning: the cycle runs through
`not_done` in order, then `done` in order, so a third state is a matter of
configuration rather than a code change:

```
task.toggle():          -- task_states = { not_done = { "[ ]" }, done = { "[x]" } }
  plain list item → "- [ ] "
  "- [ ]"         → "- [x]"
  "- [x]"         → plain list item (marker removed entirely)
  → loop continues
```

The grouping is what lets a reader — and `jump`'s `NOT_DONE_TASK` target (§8) —
ask which markers mean unfinished, rather than inferring it from a marker's
position in a flat list.

`task.toggle()` — single function, operates on the line under the cursor. A
plain list item is not one of the states: it is where the cycle starts and ends.
A line that is not a list item at all is an error, not a state to start from.

It reads and rewrites the line through `parse_list_item`/`format_list_item`
(Part 2 §1), keeping its own configurable notion of what the markers mean.

`[ ]`/`[x]` are the only markers a renderer such as GitHub treats as interactive
checkboxes. Extending `task_states` with more (e.g. `not_done = { "[ ]", "[/]" }`
for "in progress") is supported; anything beyond the two degrades to plain text
outside this plugin.

---

## 5. TOC generation

"Regenerate fully between fixed markers."

**Markers** (fixed, not configurable):

```markdown
<!-- TOC -->
- [Some Note heading](#some-note-heading)
  - [Subheading](#subheading)
<!-- /TOC -->
```

```
generate_toc():
  1. scan buffer for markdown headers (# through ######) via treesitter,
     skipping any inside the existing TOC block
  2. parse_heading → level, text; build nested list: indent per heading depth,
     link text = heading text, target = format_anchor(text)
  3. lines = section.set(buffer lines, "TOC", list, { at = cursor row })
  4. util.replace_lines(bufnr, lines)   -- writes only the span that changed
```

`generate_toc()` is safe to re-run any time — always fully regenerates, never
appends/patches. Headings are read from the syntax tree rather than by regex, so
a `#` inside a fenced code block is not mistaken for one.

Marker handling belongs to Part 2 §2. Passing the cursor row as `opts.at`
decides where the block lands on a first generation — the writer is the one who
knows where it belongs.

---

## 6. Quotes and callouts

One operation, exposed twice. A callout *is* a block quote with a `> [!TYPE]`
line on top of it, so `add_block_quote()` and `add_callout()` share a single
internal `quote_range()` and differ only in whether a type is passed to it.

```lua
callout_types = { "NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION" },
```

```
quote_range(range?, type?):
  range   → every line in it prefixed with "> ", already-quoted lines nesting
  no range → the line under the cursor
  blank line → "> " and the cursor lands inside it, in insert mode
  type    → "> [!TYPE]" written above the quoted lines

add_block_quote()  = quote_range(selection, nil)
add_callout()      = picker over callout_types → quote_range(selection, type)
```

A blank line inside the range is quoted as a bare `> ` rather than left alone:
an unquoted line in the middle would end the quote and start a second one.

One exception to the shared path: with **no selection** and the cursor already
inside a block quote, `add_callout()` inserts only the header at that quote's
first line, promoting the existing quote to a callout instead of quoting one of
its lines a second time. This is the only place the feature reaches for
treesitter.

Both are line-based, so each ships a `prepare_*()` twin (§2). The actions menu
registers the twins, not the plain functions.

---

## 7. Generators

The broader "quickly create X" surface. Each generator is its own function and
an entry in the actions menu (§2). Block quote and callout are in §6, being one
feature with two entry points.

### 7.1 Table

```
add_table():
  1. prompt: columns
  2. insert skeleton, one blank body row:
     |  |  |
     | --- | --- |
     |  |  |
  3. cursor lands in first header cell, in insert mode
```

Columns only. A table grows downwards by typing, so a row count is a prompt that
saves nothing.

### 7.2 Footnote

```
add_footnote():
  1. prompt: footnote text
  2. insert reference after the word under the cursor: [^n]
     (n = highest footnote number in the buffer + 1)
  3. append the definition at the end of the buffer: [^n]: text
  4. cursor stays at the reference, where writing was interrupted
```

The text is asked for up front rather than typed at the definition, so that a
footnote is written without leaving the sentence that needed it. The definition
always goes at the end of the buffer; there is no notion of a footnotes section
to insert in front of. A blank line is put before it unless the buffer already
ends in one or in another definition, so definitions gather in a block.

### 7.3 Link

```
add_link():
  1. capture the target: a selection is replaced by the link and supplies the
     label; with none, the link goes after the word under the cursor
  2. ask a provider for the target (Part 2 §3) — the built-in one browses the
     files around the document, or takes a URL typed into the same list
  3. prompt: link text, when neither the selection nor the provider knew one
  4. insert format_link(text, path)
```

`add_link` has a `prepare_link()` twin (§2), for the same reason every
selection-acting entry in the actions menu does.

The label is asked for after the target, so abandoning the provider costs no
prompt for a link it then cannot write.

### 7.4 Reference-style link

The same target capture as `add_link` (§7.3), writing the other link shape:

```
add_reference_style_link():
  1. capture the target exactly as add_link does
  2. ask a provider for the target, label and all, exactly as add_link does
  3. prompt: reference name, defaulting to the link text
  4. insert format_reference_link(text, ref)  --> "[text][ref]"
  5. append format_reference_definition(ref, path) at the end of the buffer,
     unless the buffer already defines that name
```

A document referring to the same URL five times writes the definition once: a
name the buffer already defines keeps the definition it has, and the path the
provider answered with is dropped. The reference name is only known after the
label, so the check cannot come early enough to skip asking the provider. The
existence check reads
`link_reference_definition` nodes out of the syntax tree rather than matching
text, so a `[ref]: url` inside a code block does not count as one.

### 7.5 Image

```
add_image():
  1. ask a provider for the source (Part 2 §3)
  2. alt text prompt, naming the source, may be left blank
  3. insert format_image(alt, path) on its own line at the cursor
```

Target first, text after it — the same way round as `add_link` (§7.3), so
inserting either reads the same. The prompt names the target because alt text is
written about a picture the writer may not have in mind yet.

The alt text has no default. Deriving one from the filename produces alt text
that describes the file rather than the picture, which is worse than none for
the reader it exists for. Blank is an answer of its own: an image with no alt
text is a picture missing its description, the document's business rather than
the plugin's. A link with no text is nothing to click, so there an empty answer
abandons the insert instead. Part 2 §3 has the provider side.

### 7.6 Code block

````
add_code_block():
  1. prompt: language (may be left blank)
  2. insert fence:
     ```lang
     <cursor here>
     ```
````

The info string carries the language and nothing else. Anything richer is a
downstream convention, not this plugin's.

---

## 8. Jump navigation — next/previous target

Move the cursor to the next or previous occurrence of a markdown construct: one
motion pair over a fixed set of targets.

```lua
md.jump.TARGETS = {
  LINK = "link",
  REFERENCE_LINK = "reference_link",
  HEADING = "heading",
  TASK = "task",
  NOT_DONE_TASK = "not_done_task",
  CODE_BLOCK = "code_block",
  TABLE = "table",
  THEMATIC_BREAK = "thematic_break",
  FOOTNOTE = "footnote",
}

md.jump.next(target)         -- forward, wrapping to the first match
md.jump.previous(target)     -- backward, wrapping to the last
md.jump.target_names()       -- the target names, in the order the menu offers them
```

```
jump.next(target):
  1. positions = the target's find(bufnr), in document order
  2. find the first position after the cursor
  3. if none, wrap to the first in the buffer
  4. move the cursor there
```

`jump.previous` is the mirror, searching backward with wraparound to the last.
Both are no-ops with a message when the buffer holds no match at all, rather
than jumping to the cursor's own position.

`target` must be one of `md.jump.TARGETS`. There is no default: every call site
names the construct it moves between. An unrecognised value is a message
listing `target_names()`.

**The targets**, each `find` built on what Part 2 §1 already parses:

| Target | Found via |
|---|---|
| `LINK` | `syntax.parse_links` — text and column per match, images skipped |
| `REFERENCE_LINK` | `syntax.parse_reference_links`, plus treesitter `link_reference_definition` |
| `HEADING` | treesitter `atx_heading`, the same source `generate_toc` reads, so a `#` inside a fenced code block is not one |
| `TASK` | `syntax.parse_list_item` — any list item carrying a bracketed marker |
| `NOT_DONE_TASK` | a list item whose marker is one of `task_states.not_done` |
| `CODE_BLOCK` | treesitter `fenced_code_block` |
| `TABLE` | treesitter `pipe_table` |
| `THEMATIC_BREAK` | `syntax.parse_thematic_break` |
| `FOOTNOTE` | `syntax.parse_footnote_refs` |

`REFERENCE_LINK` covers both halves of the construct — the `[text][ref]` left in
the prose and the `[ref]: url` giving it a destination — since a writer checking
one is on their way to the other, and definitions gathered at the end of a file
are not worth a target of their own. Its definitions come from the syntax tree
for the same reason §7.4's existence check does: a `[ref]: url` inside a fenced
code block is not one. `LINK` stays inline-only; the two are separate targets
because a document reads with mostly one shape or the other, and a motion that
mixed them would stop in places the writer was not looking for.

A target is a name and a `find(bufnr)` answering `{ {row, col}, ... }` in
document order, so adding one is a table entry rather than a change to the
motion. A target built from more than one source sorts them back into that
order. There is no display name beside the internal one: the name is what a
call site passes, what a command completes to and what a picker offers, so a
target is spelled one way everywhere.

No default keymaps. Bound to whatever the user prefers, per-target:

```lua
vim.keymap.set("n", "]l", function() md.jump.next(md.jump.TARGETS.LINK) end)
vim.keymap.set("n", "[h", function() md.jump.previous(md.jump.TARGETS.HEADING) end)
```

The actions menu (§2) registers two entries, "Jump to next…" and "Jump to
prev…", each opening a picker over `target_names()`. The direction is the
choice a writer has already made by the time they reach for the menu; the
construct is the one still open, so it is what the picker asks for.

---

## 9. Focused view

The shared internal mechanism behind the two full-screen floating-window
features that follow: presentation mode (§10) and focus mode (§12).

---

### 9.1 Why a floating window

A regular split can hide numbers/signcolumn/statusline easily enough, but true
**centering with side padding** can't be done by resizing the current window
alone — a float sized narrower than the terminal, positioned centered, leaves
the margin as the space between its edge and the terminal's.

Gutter options are not an alternative: `signcolumn`, `foldcolumn`, `numberwidth`
and `statuscolumn` all pad the **left only**, so a symmetric margin can't be
built from them without rewriting the text itself — which a feature editing the
user's real buffer can never do. `foldcolumn` also caps at 9, and
`style = "minimal"` disables it outright.

What fills the margin is a second, full-screen float **behind** the first
(`zindex` 40 vs. 50, `focusable = false`), whose `winhighlight` points
`Normal`/`NormalNC` at `MdDraftingBackdrop`. Without it the previous window's
contents would show through on either side.

**Spacing between the heading and the content needs a window of its own.**
Neither obvious approach works: virtual lines placed *above the first buffer
line* are not drawn at rest — Neovim starts the display at line 1, so nothing
above it is ever on screen unless the view is scrolled up into it (which the
typewriter module does deliberately, for a different purpose — §11) — and real
blank lines would mean writing into a buffer that, for focus mode, is the user's
own document. So when a gap is asked for, the heading moves out of the content
window's winbar and into a separate float whose own empty rows are the gap. That
also pins the spacing: text scrolling underneath cannot push it away.

A winbar is drawn *inside* its window's height rather than on top of it, so the
heading window is `gap + 1` rows tall. Leaving the winbar's row out of that count
leaves no room for the gap and makes setting `'winbar'` fail with `E36: Not
enough room`.

With `header_gap = 0` there is no third window at all and the heading is the
content window's winbar.

Statusline and tabline (`laststatus`, `showtabline`) are global, not per-window
— hiding them has to be save-and-restore around the whole session rather than
scoped to the float. In practice this is invisible (the float covers the screen
either way), but it matters for getting restore-on-exit exactly right.

---

### 9.2 `focused_view` — the shared internal primitive

An internal module both features are built on; not part of the public API.

```lua
-- internal, not exposed on the module table

focused_view.open(opts):
  opts = {
    buf,                      -- required; the caller owns it, scratch or real
    width,                    -- >= 1 → columns; 0 < n < 1 → fraction of the terminal
    header = fn() -> string,  -- rendered into winbar
    header_events,            -- e.g. {"CursorMoved", "TextChanged"} — when to re-render header
    header_hl,                -- highlight group for the heading strip
    header_gap,               -- blank rows between the heading and the content
    normal_hl,                -- highlight group for the content window itself
    backdrop,                 -- highlight group for the margins, or false for none
    win_opts = {},            -- extra win-local options specific to the caller
    on_close = fn(),          -- cleanup hook
  }
  1. close any view already open — a second would save the first's already
     modified globals and restore the wrong values on the way out
  2. save the global options a full-screen view hides (laststatus, showtabline)
  3. compute centered geometry:
       width = opts.width < 1 and floor(columns * opts.width) or floor(opts.width)
       width = clamp(width, 1, vim.o.columns)   -- narrow terminal → full width
       height = vim.o.lines - vim.o.cmdheight
       col = (vim.o.columns - width) / 2
     then split it between the heading and the content when a gap is asked for:
       heading: height = header_gap + 1        -- + 1 for the winbar's own row
       content: row += header_gap + 1, height -= header_gap + 1
  4. open the backdrop float (full screen, zindex 40, focusable=false), if asked for
  5. open opts.buf in the content float at that geometry, zindex 50
  5a. open the heading float above it (empty buffer, focusable=false), if a gap
      was asked for; it takes the content's 'winhighlight' so its blank rows
      read as the top of the page rather than as margin
  6. apply shared base options: number=false, relativenumber=false, signcolumn="no"
  7. apply opts.win_opts on top (mode-specific overrides, e.g. conceallevel)
  8. build 'winhighlight' by key: Normal/NormalNC → opts.normal_hl on the
     content and heading windows, WinBar/WinBarNC → opts.header_hl on whichever
     of them carries the heading. One option holds every remapping for a
     window, so the caller's entries for other keys are kept and only the ones
     the view owns are replaced. They are replaced rather than appended to
     because Neovim accepts a repeated key but leaves it undefined which wins
  9. set winbar to opts.header(); wire opts.header_events to re-render it on demand
  10. register autocmds:
       VimResized → recompute the layout, reposition/resize every float
       WinClosed  → the view can be dismissed by closing its window directly
                    (:q), which must still restore globals and dispose of the
                    other floats; the window is already going, so drop it from
                    the handle rather than close it again, and defer the rest
  11. return a handle exposing .win, .buf, .closed, .cursor(), .refresh_header()
      and .close()

handle.close():
  1. return immediately if already closed — nvim_win_close fires WinClosed,
     which would otherwise re-enter here
  2. delete the augroup
  3. run opts.on_close, if given
  4. close the content, heading and backdrop floats, each guarded by nvim_win_is_valid
  5. restore the saved globals

focused_view.header_line({ left, center, right }):
  each section is a string, or { text, hl } to give it a group of its own
  (closed with "%*" so its color does not bleed into the sections after it).
  Escapes "%" in each (winbar content is parsed as a statusline, so raw document
  text would otherwise be read as items) and joins them with "%=", which spreads
  them across the width, plus a space at either end to keep the text off the
  window edge. No measurement, so nothing to get wrong on multi-byte or
  double-width text.

focused_view.define_highlight(name, value):
  defines a group with `default = true` and defines it again on ColorScheme,
  which clears every group.
```

Buffer ownership sits with the caller because the two features need opposite
things: presentation renders into a scratch buffer so the document is never
touched, focus mode edits the real one.

#### What's shared vs. what each feature supplies

| Shared (in `focused_view`) | Per-feature (supplied via `opts`) |
|---|---|
| Centering/geometry math | `width` |
| `VimResized` repositioning | — |
| Backdrop float behind the margins | `backdrop` highlight group |
| Heading float and the spacing under it | `header_gap` |
| Option save/restore, and owning the `winhighlight` keys the styling hangs off | `win_opts` (mode-specific overrides, straight from the user's config) |
| Shared groups, and redefining them on `ColorScheme` (`define_highlight`) | Each mode's own groups, and which windows use them |
| Winbar-as-header mechanism, `header_line()` | `header()` render function, its update events, `header_hl` |
| Open/close lifecycle, `WinClosed` and re-entry handling | `on_close` cleanup hook |
| — | The buffer itself (`buf`) |
| | Mode-specific keymaps (owned entirely by the feature, not the primitive) |

Getting option save/restore and resize-handling exactly right is the trickiest,
most bug-prone part of a floating-window feature — centralizing it means that
work only has to happen once, and a future third focused-view feature would
mostly just need a `header()` function and some `win_opts`, not a float built
from scratch.

---

#### 9.2.1 Styling

Colors are highlight groups, not config options — a colorscheme can then theme
the plugin, and users change them the same way they change everything else.
Three roles exist for a view: the heading strip (`header_hl`), the content
window's `Normal` (which the gap under the heading also takes), and the backdrop.

They come in **two levels**. The primitive defines the shared groups; each
feature links its own to them:

```
MdDraftingHeader   → StatusLine     MdDraftingPresentationHeader   → MdDraftingHeader
MdDraftingNormal   → Normal         MdDraftingPresentationNormal   → MdDraftingNormal
MdDraftingBackdrop → Normal         MdDraftingPresentationBackdrop → MdDraftingBackdrop
```

Callers name their groups through `header_hl`, `normal_hl` and `backdrop` rather
than writing a `winhighlight` string, so no feature module has to know how that
option is spelled and none of them can reach past the seam by setting it in
`win_opts`.

Windows are pointed at the *mode's* groups, never the shared ones. Setting a
shared group therefore retints every view at once, while a mode's own group can
be set without disturbing the others — which is what lets focus mode look
different from presentation mode without either having to know about the other.
Focus mode's are `MdDraftingFocus*`.

The heading links to **`StatusLine`** rather than `WinBar`. `WinBar` is styled
wildly differently across colorschemes — sometimes linked to `Normal`, sometimes
to `StatusLine`, often bold — so a heading built on it has no consistent
appearance. `StatusLine` reliably carries a background distinct from `Normal`,
which is what makes the heading read as a bar rather than as the first line of
content. That distinct background is also why no rule underneath is needed to
separate the two.

Links rather than copied colors, so a colorscheme changing `StatusLine` carries
through without the plugin noticing. Everything is defined with `default = true`,
so a colorscheme or user definition already in place wins. `:colorscheme` clears
every group, so they are all defined again on that event.

The alternative — one group per section, with the title emphasised over the
counter — is available at no cost through `header_line`'s `{ text, hl }` form,
but is not used by default: a statusline-style bar conventionally reads at
uniform weight.

---


---

## 10. Presentation mode

The one feature allowed to own its own keymaps, since navigation only makes
sense within the modal view it creates.

```lua
presentation = {
  width = 80,
  header_gap = 1,
  win_opts = { wrap = true, linebreak = true },
  keymaps = {
    next = "n",
    previous = "p",
    quit = "q",
  },
},
```

Renders the current buffer as a slide deck directly within Neovim, using the
configured slide width, window options and navigation keys, scoped only to the
presentation buffer/window.

Slides are split on thematic breaks — `---`, `***`, `___`, via Part 2 §1's
`parse_thematic_break` — rather than on a heading level, so the split is
something the writer puts in the document deliberately, and a deck reads as a
deck in any markdown viewer. An optional frontmatter block, read by Part 2 §1's
`parse_frontmatter`, supplies the heading text:

```markdown
---
header_left: My Talk
header_center: Introduction
---
```

The heading's right-hand side is the slide counter, which the view owns.

Window options are a `win_opts` passthrough merged over the defaults rather than
a setting per option, so anything window-local is reachable without the plugin
having to mirror Neovim's option list. `winhighlight` is the exception: the view
owns the keys the highlight groups hang off.

Internally:

```
start_presentation():
  parse frontmatter and split slides on thematic breaks
  scratch = a new unlisted buffer, filetype=markdown, nomodifiable, bufhidden=wipe
  handle = focused_view.open({
    buf = scratch,
    width = config.presentation.width,
    header = function()
      return focused_view.header_line({
        left = header_left, center = header_center,
        right = string.format("%d/%d", current_slide, total_slides),
      })
    end,
    header_events = {},  -- updated manually on next()/previous(), not on text change
    header_hl = "MdDraftingPresentationHeader",
    header_gap = config.presentation.header_gap,
    normal_hl = "MdDraftingPresentationNormal",
    backdrop = "MdDraftingPresentationBackdrop",
    win_opts = config.presentation.win_opts,
  })
  render_slide(current_slide)
```

Rendering a slide is just writing its lines into the scratch buffer and calling
`handle.refresh_header()`. Nothing restores the original view on close, because
nothing changed it: the document was never opened in the float, so closing the
float is the whole of the cleanup.

Long lines are folded at word boundaries by `wrap`/`linebreak` rather than by
hand. Setting the scratch buffer's `filetype` is enough to get treesitter
highlighting — the `markdown` ftplugin calls `vim.treesitter.start()`, and the
parser reattaches across slide changes on its own.

The keymap exception (`next`/`previous`/`quit`) is scoped to slide navigation
inside the modal view; the windowing mechanics themselves stay inside the
shared, keymap-free primitive (§9).

---

## 11. Typewriter scrolling

The line being written keeps a fixed screen row while the text moves under it.
Its own module, switched on **per buffer** — `md.typewriter.toggle()`,
`:MdTypewriter` — and usable anywhere, not only inside a focused view. Focus mode
turns it on while it is open when `focus_mode.typewriter` is set, leaving it
alone on the way out if it was already on by hand.

```lua
typewriter = {
  position = 0.5,   -- fraction of the window height
},
```

Four functions, each taking the buffer to act on and defaulting to the current
one:

```lua
md.typewriter.toggle(bufnr?)
md.typewriter.enable(bufnr?)
md.typewriter.disable(bufnr?)
md.typewriter.is_enabled(bufnr?)   --> boolean
```

`toggle()` is what a mapping binds, but it is not enough on its own: focus mode
(§12) has to turn typewriter scrolling on and leave it alone on the way out when
it was already on by hand, and asking "is it on?" then setting it explicitly is
the only way to express that. Toggling twice around the view would switch off a
typewriter the writer had switched on.

**`scrolloff` cannot do this.** A very
high `scrolloff` asks for that many lines above and below the cursor and simply
stops scrolling when the document doesn't have them, rather than padding. So it
holds in the middle of a file and lets go at both ends — precisely where writing
happens. Measured on a 21-row window: line 30 → `winline=11`, line 60 →
`winline=21`, line 1 → `winline=1`.

Four parts, each earned by a bug:

- **The bottom needs no padding.** Vim already scrolls past the last line — `zz`
  on it gives `winline=11` of 21. Only `scrolloff` refuses to, so the fix is to
  stop relying on it. `scrolloff` is set to `0`, since two things steering the
  view means the second undoes the first.
- **The top needs padding, and `virt_lines_above` on line 0 supplies it.** Those
  lines are not drawn at rest (§9.1), but they *can be scrolled into*:
  `winrestview({ topline = 1, topfill = N })` reaches them, producing state
  identical to pressing `<C-y>` N times. `position - 1` rows' worth are hung
  there, resized with the window.
- **`zz` alone is not exact, and `smoothscroll` is why.** With wrapped lines
  above the cursor `zz` lands a row or two off, so the remainder is walked off
  with `<C-e>`/`<C-y>`. Without `'smoothscroll'` those scroll by whole *buffer*
  line, which overshoots across a wrapped line and shows as the text jumping up
  and down as the cursor moves past one. With it they scroll by *screen* line and
  the row holds exactly. Measured over 40 lines with every third wrapped: 10 rows
  off-target without it, none with.
- **The cursor has to be put back afterwards.** `:normal!` runs in normal mode,
  which clamps the column to the last character — past the end of a line, or on
  an empty one, that is not where insert mode was. Without restoring
  `lnum`/`col`/`coladd`/`curswant` around the scroll, typing `Hello` on an empty
  line at the end of a document produced `elloH`: the first character landed, the
  clamp moved the cursor before it, and the rest went in ahead. A re-entrancy
  flag guards the same scrolling from firing `CursorMoved` back into itself.

Driven from `CursorMoved`/`CursorMovedI`/`WinScrolled`, with
`TextChanged`/`TextChangedI` additionally re-placing the filler — rewriting every
line drags the extmark off line 0, while moving the cursor cannot. Everything it
touches is given back: `scrolloff` and `smoothscroll` are saved per window and
restored, and the filler extmark is cleared from the buffer, which for focus mode
is the user's real document.

---

## 12. Focus mode

Distraction-free writing view, built on the same `focused_view` primitive
(§9).

```lua
focus_mode = {
  width = 80,
  header_gap = 1,
  stats = { "words", "lines" },
  typewriter = true,   -- turn typewriter scrolling on while focus mode is open
  win_opts = {
    wrap = true, linebreak = true,
    conceallevel = 2, cursorline = false, spell = false,
  },
},
```

`spell` ships `false`: it needs `spelllang` set up to be useful and underlines
every code block and URL in a technical document, so it is visible-but-off
rather than on.

```
focus.toggle():
  open  → the current buffer in a centered float, file name and live counts
          in the heading, the line being written held at a fixed screen row
  close → carry the cursor back to the window it was started from
```

`md.focus.toggle()` is the whole API; `:MdFocus` and `:q` also close it.
**No keymap exception** — presentation mode's (§10) is scoped to slide
navigation, and in a writing view every letter key belongs to the writer.

Unlike presentation mode, this opens the **real document** rather than a scratch
copy, which is the case `focused_view`'s caller-supplied `buf` exists for. Edits
go into the buffer and `:w` behaves normally.

Typewriter scrolling (§11) is a separate, independent feature; focus mode
simply turns it on when it opens and off when it closes, unless
`focus_mode.typewriter = false`, leaving it alone if it was already on by hand.

Colors are `MdDraftingFocus*`, linking to the same shared groups presentation
mode's link to, so either mode can be retinted alone or both at once.

Internally:

```
toggle():
  already open → handle.close(), and stop
  MdDraftingFocusHeader/Normal/Backdrop link to the shared groups (§9.2.1)
  handle = focused_view.open({
    buf = the current buffer — the real document, not a copy
    width = config.focus_mode.width,
    header = function()
      return focused_view.header_line({ left = file name, right = stats })
    end,
    header_events = { "TextChanged", "TextChangedI" },
    header_hl = "MdDraftingFocusHeader",
    header_gap = config.focus_mode.header_gap,
    normal_hl = "MdDraftingFocusNormal",
    backdrop = "MdDraftingFocusBackdrop",
    win_opts = config.focus_mode.win_opts,
    on_close = carry the cursor back to the window it was started from,
  })
  put the cursor where the document was left, rather than at line 1
```

Because the document also stays displayed in the window focus mode was started
from, and windows hold cursor positions of their own, leaving the view would
otherwise drop the writer back where the session started. `on_close` copies the
position across — guarded by the origin window still being valid and still
showing the same buffer, since either can have changed while the view was open.

On the `:q` path the primitive drops the window from the handle before running
`on_close`, so the position could not be read out of it afterwards.
`handle.cursor()` answers with the live position when the window is still there
and with the one recorded during `WinClosed` when it is not.

`toggle()` is the whole API.

### 12.1 Color scheme adjustment — scoped, not global

Rather than switching `colorscheme` globally (which would affect all windows and
need explicit unwinding on exit), the adjustment is scoped to just the floating
window, through `normal_hl` pointing `Normal`/`NormalNC` at
`MdDraftingFocusNormal`. Nothing to undo globally on exit beyond closing the
window — `focused_view`'s close handles that as part of its normal option
restore.

Because that group links to the shared `MdDraftingNormal` (§9.2.1), focus mode
picks up any retint applied to every view, while still being able to take colors
of its own — a darker page for writing than for presenting, say — without
presentation mode changing with it.

### 12.2 Stats

Word/line count (configurable via `focus_mode.stats`) rendered into the
winbar-as-header, same mechanism presentation mode uses for its slide counter —
just updated on text-change events instead of on manual slide navigation. No
separate floating stats window needed. The file name goes in the header's left
section, since with the statusline and tabline hidden nothing else on screen
names the document.

Each stat is a function in a table keyed by name; `focus_mode.stats` is the
ordered list of which to render, joined with `" · "` — e.g. `"142 words · 12
lines"`, with singular forms handled. Adding one (reading time, say) is a
function and a name, with no change to the header mechanism, which only ever
sees a string. Unknown names are skipped rather than raising.

`header_events` is `TextChanged` and `TextChangedI` only — **not**
`CursorMoved`: the counts cover the whole buffer, so
moving the cursor cannot change them, and `wordcount()` on every motion is wasted
work on a long document. `wordcount()` also reads whichever buffer is current and
takes no argument for another, so it is called inside `nvim_buf_call`, rather
than trusting the float to be current when the header renders.

---

## 13. Config

```lua
require("md-drafting").setup({
  add_commands = false,

  task_states = {
    not_done = { "[ ]" },
    done = { "[x]" },
  },

  callout_types = { "NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION" },

  link_providers = {
    order = {},
    file_or_url = {
      image_extensions = { "png", "jpg", "jpeg", "gif", "webp", "svg" },
    },
  },

  presentation = {
    width = 80,
    header_gap = 1,
    win_opts = { wrap = true, linebreak = true },
    keymaps = { next = "n", previous = "p", quit = "q" },
  },

  focus_mode = {
    width = 80,
    header_gap = 1,
    stats = { "words", "lines" },
    typewriter = true,
    win_opts = {
      wrap = true, linebreak = true,
      conceallevel = 2, cursorline = false, spell = false,
    },
  },

  typewriter = {
    position = 0.5,
  },
})
```

`typewriter` is its own top-level block rather than living under `focus_mode`,
since typewriter scrolling is a per-buffer feature usable anywhere;
`focus_mode.typewriter` only decides whether focus mode turns it on for you.

`presentation.width`, `focus_mode.width` and `typewriter.position` are validated
in `setup` and fall back to their defaults with a message, since a width of zero
or a position outside the window is not a view anything can be rendered in.

`link_providers` is the whole of the link generator's configuration, and Part 2
§3 is where it is explained: which providers lead the picker, and what the
built-in one lists for an image. There is no setting for where the file browser
starts — it is always the document's own directory.

Jump navigation has no config: its targets are a fixed list (§8), not something
a setting selects from, and it owns no keys.

Fully independent of `memoria.nvim`'s own `setup({})` — no shared config
surface, only the runtime registration calls and Part 2's API connect the two.

---

## 14. Open items

- Whether `task.toggle()` should support multi-line visual ranges, or stay
  single-line only.
- Whether focus mode should offer a stat covering the current section rather
  than the whole buffer (words since the last heading). That one *would* need
  `CursorMoved` in `header_events`, and with it a reason to care about how
  often the header re-renders.
- Whether `header_line`'s `{ text, hl }` form should be used to dim the stats
  against the file name, rather than the bar reading at one weight.


# Part 2 — Using md-drafting.nvim from another plugin

Everything a dependent plugin (e.g. `memoria.nvim`) is meant to build on, and
nothing else. It lives on its own table:

```lua
local api = require("md-drafting").api
```

`api.syntax` (§1), `api.section` (§2) and `api.register_link_provider`
(§3) are the whole of it. **Nothing under `api` is reachable elsewhere on the
plugin table**, so there is one name per thing and
no question about which is the supported one: the rest of Part 1 is this
plugin's own features, `api` is its contract with what is built on top.
`md-drafting.nvim` stays unaware that anything is calling it or why.

This Part mirrors the implemented contract. The authoritative copy is
`md-drafting.nvim`'s own `PLUGIN_AUTHORS.md` (and `:help md-drafting-link-providers`);
where the two disagree, that one wins and this one is out of date.

---

## 1. Syntax utilities

Pure functions over strings — no buffer, no config. **Every markdown construct
the plugin knows lives here**, rather than in the feature that happens to need
it. One file per construct under `syntax/` — `link`, `list`, `heading`, `block`,
`footnote`, `frontmatter`, `emphasis` — flattened onto the one table, so which
file a function is written in is where to go and read it rather than something a
caller has to know.

Two things follow from keeping them all here, and both are the point:

- each construct is written and read in one place, so how it is written and how
  it is parsed cannot drift apart;
- what a dependent plugin gets is what `md-drafting.nvim` itself runs on, not a
  parallel implementation maintained for someone else's benefit.

```lua
-- links and images
drafting.api.syntax.format_link(text, path)                  --> "[text](path)"
drafting.api.syntax.format_image(alt, path)                  --> "![alt](path)"
drafting.api.syntax.format_reference_link(text, ref)         --> "[text][ref]"
drafting.api.syntax.format_link_label(ref)                   --> "[ref]"
drafting.api.syntax.format_reference_definition(ref, url)    --> "[ref]: url"
drafting.api.syntax.parse_links(content)                     --> [{text, path, col}, ...]
drafting.api.syntax.parse_reference_links(content)           --> [{text, ref, col}, ...]

-- list items and checkboxes
drafting.api.syntax.parse_list_item(line)                    --> prefix, marker, text
drafting.api.syntax.format_list_item(prefix, marker, text)   --> "- [x] text"
drafting.api.syntax.parse_checkbox(line, markers?)           --> "not_done" | "done" | nil
drafting.api.syntax.marker_state(marker, markers?)           --> "not_done" | "done" | nil
drafting.api.syntax.marker_cycle(markers?)                   --> { "[ ]", "[x]", ... }
drafting.api.syntax.TASK_STATES                              --> { "not_done", "done" }

-- headings
drafting.api.syntax.parse_heading(line)                      --> level, text
drafting.api.syntax.format_anchor(text)                      --> "#some-heading"

-- quotes, footnotes, tables, fences, breaks, emphasis
drafting.api.syntax.format_quote(line)                       --> "> line"
drafting.api.syntax.format_callout(type)                     --> "> [!TYPE]"
drafting.api.syntax.format_footnote_ref(n)                   --> "[^n]"
drafting.api.syntax.format_footnote_definition(n, text)      --> "[^n]: text"
drafting.api.syntax.parse_footnote_refs(content)             --> [{n, col}, ...]
drafting.api.syntax.format_table_row(cells)                  --> "| a | b |"
drafting.api.syntax.format_code_fence(lang?)                 --> "```lang"
drafting.api.syntax.parse_thematic_break(line)               --> "-" | "*" | "_" | nil
drafting.api.syntax.format_emphasis(text, marker)            --> "**text**"
drafting.api.syntax.EMPHASIS                                 --> { bold, italic, strikethrough, code }

-- frontmatter
drafting.api.syntax.parse_frontmatter(lines)                 --> fields, closing row | nil
```

`parse_links` skips images, which are only told apart from links by the `!` in
front, and carries each match's column so Part 1 §8's jump targets have somewhere to
land; `parse_reference_links` and `parse_footnote_refs` carry one for the same
reason. The two link parsers stay separate because a reference-style link
carries a label rather than a destination: folding them together would answer
with a `path` that is sometimes nil, and every caller would have to ask which
kind it got. The collapsed form, `[text][]`, is one of these with an empty ref;
the shortcut form, a bare `[text]`, is not read as a link at all, since nothing
tells it apart from ordinary brackets. `parse_list_item`
is the single home of the bullet pattern and
`format_list_item` is its exact inverse; a bracketed run only counts as a marker
when whitespace or the end of the line follows it, so `- [Note](note.md) matters`
is a list item holding a link, not one in the "Note" state. `parse_heading`
applies the same rule to `#`: `#hashtag` is a word.

`parse_checkbox` defaults to GitHub-flavored markers (`not_done = { "[ ]" }`,
`done = { "[x]", "[X]" }`) and takes `markers` (`{ not_done = {...}, done =
{...} }`, the shape `task_states` uses) to recognise others. That argument
**replaces** the default rather than merging with it, and is deliberately
unrelated to `task_states`: which markers a caller indexes is the caller's
concern, not this plugin's configuration. Since brains should stay readable
anywhere, the default is what memoria ships with.

`parse_checkbox(line, markers)` is `parse_list_item` followed by
`marker_state(marker, markers)`; a caller that has already split the line (to
rewrite it with `format_list_item`, say) asks `marker_state` directly rather
than parsing twice. `marker_cycle` flattens `markers` into toggle order,
`not_done` before `done`. States are always named by `TASK_STATES`, and a
`markers` table keyed any other way silently matches nothing, since a missing
state is read as an empty list.

`parse_frontmatter` reads the `---`-delimited block a document may open with,
returning its fields and the row it closes on. Scalars and single-level lists —
enough for a document's own header, which is all presentation mode's heading
keys and memoria's `tags`/`participants` (Part 3 §5.1) need. An opening
delimiter that is never closed is not frontmatter: reading the whole document as
one turns every prose colon into a field. The block must open on line 1, and no
frontmatter is `nil` for both returns.

Lists come in both YAML shapes: block style (`- item` lines under the key) and
**flow style** on the key's own line — `tags: [java, proj/web]`, `tags: []`,
items optionally quoted so one can hold a comma (`["Smith, Alice"]`). Flow style
is what memoria writes, one line per field however many values it holds
(Part 3 §5.1).

A fourth return, `spans`, gives the rows each field is written on
(`{ first, last }`), which is what the writer needs: `set_frontmatter_field(
lines, name, value)` replaces a field's rows with one line, adds a missing field
before the closing delimiter, gives a document without frontmatter a block, and
removes the field for a `nil` value — every other line kept as it was. A block
list it rewrites comes back as a flow list; a comment among the field's lines
is kept, after the new one. Frontmatter it cannot read is an error, never
written over, and so is a field it cannot rewrite whole: one followed by
indented lines the reader does not model (a block scalar, a nested mapping),
which would otherwise be left behind under the new value, or a key written
twice. The reader skips YAML comments, so `# see: x` is not a field. `format_frontmatter_value` is the value half of
that: a flow list for a list, and a string plain when that reads back
unambiguously, double-quoted otherwise — for flow and mapping punctuation, a
comment `#`, a quote, a line break, edge whitespace, a leading YAML indicator,
or the empty string.

Field values are `string | string[]`, decided by what follows the key rather
than by any schema: a flow list or `- java` lines is a list (`[]` the empty
one), `tags: java` is a string, and a bare `tags:` with nothing under it is the
empty **string** `""`, not an empty list. A caller expecting a list normalises
the scalar cases.

This is the one place the module admits a syntax that is not markdown, on the
grounds that the block is part of how a markdown document is written in
practice, and two hand-rolled scanners for it would be one too many.

**There is no `format_checkbox`.** Nothing writes a bare checkbox: `task.toggle`
composes a whole line, which is `format_list_item`'s job, and memoria's append
templates carry the literal marker in the template string (Part 3 §8.2). A
function taking a marker and returning it would be an identity with a name. The
same rule keeps `format_heading` and a thematic-break formatter out — the
constructs are here in the direction they are actually used.

## 2. Fenced sections

The "regenerate fully between fixed markers" mechanism behind the TOC, shared
with the synapse block (Part 3 §5.1), `append_to_engram` (Part 3 §8.2) and the
generated index (Part 3 §9.3), which want exactly the same thing.

```lua
drafting.api.section.get(lines, name)              --> string[] | nil
drafting.api.section.set(lines, name, body, opts?) --> the rewritten lines
```

That is the whole module — `get` and `set`, nothing else, and the plugin's own
tests hold it to exactly those two.

**Both are pure, over a list of lines.** There is no buffer variant: a
dependent plugin's quick-capture path rewrites a file it never opened, and a
buffer is just lines read with `nvim_buf_get_lines` and written back.

- `get` answers the lines between the markers. An empty section is `{}`, which
  is not the same answer as `nil` — there being no section at all.
- `set` replaces the body wholesale. With no section present it writes one,
  markers included, at `opts.at` (a **1-indexed** row, inserted before whatever
  is there) or, without it, at the end of the lines. Idempotent: the result
  depends only on `body`, never on what was there before. Content outside the
  markers is never touched.

**The pair round-trips** — `get(set(lines, name, body), name)` is `body` — so
every other edit is a composition, not a function of its own:

```lua
local body = api.section.get(lines, "LOG") or {}
table.insert(body, "- " .. entry)
lines = api.section.set(lines, "LOG", body)
```

Appending, prepending, dropping a line, sorting, de-duplicating: all are `get`,
an edit, `set`. Appending to a section that does not exist yet falls out of the
same three lines, since `get` answers `nil → {}` and `set` then writes the
section at the end.

Marker shape is `<!-- NAME -->` / `<!-- /NAME -->`, a constant rather than a
setting. The functions that build and find the markers are **private** to the
module; a dependent plugin names a section and never spells the comment out.
Matching compares each line trimmed, so indentation around a marker is
tolerated; the section is the first opening marker and the first closing marker
after it. Both markers must be present to count as a section: a lone opening
marker would otherwise swallow the rest of the file. The name is concatenated
verbatim, so a name like `INDEX:STATS` is fine.

**Writing the result into a buffer is the caller's job, and the obvious way is
the wrong one.** `nvim_buf_set_lines(bufnr, 0, -1, false, updated)` drags every
extmark to the end of the replaced range — signs, diagnostics, git hunks all
jump to the bottom — even when the lines written are identical. `md-drafting`
trims the common prefix and suffix and writes only the span in between
(`util.replace_lines`, which the TOC uses), but that helper is internal: a
dependent plugin carries its own copy of the same dozen lines.

## 3. Link providers

Where `add_link`, `add_reference_style_link` (Part 1 §7.3–7.4) and `add_image`
(Part 1 §7.5) get their target. `md-drafting.nvim` asks; it does not itself know
what a link or an image can point at — that knowledge lives entirely in
providers.

```lua
drafting.api.register_link_provider({
  label = "Engram",
  kinds = { "link" },   -- default: both
  resolve = function(ctx, done) ... end,
})
```

`resolve(ctx, done)` is handed `ctx.kind` (`"link"` or `"image"`) and `ctx.text`
(the selection's label, for a link) and answers `done{ text, path }`, or
`done(nil)` to abort. `text` is the link text, or an image's alt text; a
provider knowing neither asks for one *after* it has the target, naming that
target in the prompt (`Enter link text (note.md): `). It answers through a
callback rather than by returning, since a provider is free to open a picker of
its own.

What a provider answers is written as-is. `ctx.text` is only a hint: the caller
does not fall back to it, so a provider that wants a selected label to win over
its own idea of the text returns `ctx.text` itself (the built-in one does). A
link answered without a non-empty `text` **and** `path` is abandoned without a
message — the provider has already had its chance to prompt or notify.

`ctx` carries no buffer and registration is global: a provider is offered in
every markdown buffer, not only where it makes sense, and reads the current
buffer itself when its answer depends on the document (for a relative path, or
to decide it has nothing to offer here and answer `done(nil)`).

`kinds` says which callers a provider is offered to; a provider with no `kinds`
is offered to both. This is what keeps memoria's "Engram" and "Concept"
providers, registered at its own setup time (Part 3 §9.2), out of `add_image`'s
picker — an engram or a concept is not something an image inserts as, so those
two set `kinds = { "link" }`.

One provider ships with the plugin, **`File or URL`**, and it is the only one a
bare install has — so `pick`'s "one source is not a choice" rule means inserting
a link never begins with a provider menu. It walks the files around the document
one directory at a time through `vim.ui.select`, which is also why everything it
can do is an entry in the list rather than a key binding. Folders and files are
one listing sorted without regard to case, a name looked for where its name puts
it rather than in whichever half its kind belongs to:

| Entry | Target |
|---|---|
| `[Enter URL…]` | Type it instead — a URL, or a path to something not there yet, written as given |
| `[Insert this folder]` | Link the directory you are in (links only) |
| `[Show hidden files]` | List dotfiles here and from then on |
| `../` | The parent directory |
| `assets/` | Walk into it |
| `cat.png` | The file, written relative to the document |

Every list opens in the document's own directory — no configured folder, nothing
created on disk, and the same place every time, so reaching a folder is a habit
rather than a guess at where the last insert ended. A path is always written
relative to the document (`../../assets/x.png` when it has to be), so it keeps
working wherever the folder is opened from.

`add_image` lists only `file_or_url.image_extensions`, since a picker of every
file is a worse way to find a picture; folders are never filtered, or a tree
with no images at this level would be a dead end, and anything the filter hides
is still reachable through `[Enter URL…]`, which takes any text. Hiding dotfiles
is the same idea — `.git/`, `.obsidian/` and a dependent plugin's own files are
not what someone is looking for — and the toggle lasts as long as the session,
so a writer who works in them turns it on once.

```lua
link_providers = {
  order = {},   -- providers that lead, by label; the rest follow in
                -- registration order

  file_or_url = {
    image_extensions = { "png", "jpg", "jpeg", "gif", "webp", "svg" },
  },
},
```

A caller may also name the provider it wants and skip the question, which is
what a mapping bound at one source does — `provider` takes a label or a provider
itself, and a name nothing registered for that kind answers to is an error
rather than a reason to ask after all:

```lua
drafting.generator.add_image({ provider = "File or URL" })
```

Jump navigation (Part 1 §8) is not part of this API: its targets are a closed
list rather than a registry.

---
---

# Part 3 — memoria.nvim

Design principles running through every decision below:

- **Plain markdown first.** Files should be usable/readable without the plugin
  (GitHub, any editor, grep).
- **Readable over ID-based**, where the tradeoff is reasonable (filenames,
  concept names) — accept that renames require propagation as the cost of this.
- **Derived data is always rebuildable.** The atlas (index) can be deleted and
  regenerated from source files at any time with zero data loss.
- **Config only holds deltas.** Override files should never duplicate the full
  default config — only what differs.
- **No unnecessary state.** Nothing is plugin-managed at runtime unless it
  strictly can't live in a file (e.g. paths are inherently per-machine).
- **Syntax vs. semantics.** Generic markdown mechanics (how a link/checkbox is
  written and parsed) live in the `md-drafting.nvim` dependency. `memoria.nvim`
  owns only note-graph meaning (what a link *means* — a synapse, a backlink).
- **Headless core.** A feature function never prompts, never opens a window,
  and answers one `result` or `nil, err` — unprefixed, since who is being told
  decides how it reads. Prompts, pickers, buffers, `vim.notify` and the
  quickfix list are a layer on top (§1.3's `ui/`), which is what the `:Mia*`
  commands and a user's own keymaps call; the CLI (§11) and the tests call the
  headless layer directly.

## 1. Vocabulary and the dependency

| Term | Meaning |
|---|---|
| **brain** | A self-contained folder of engrams — a collection |
| **engram** | A single stored note/file — the unit of content (meeting note, recipe, plan, etc.) |
| **synapse** | A structural connection between two engrams (e.g. `up`/`down`) |
| **concept** | A referenced person/topic/etc. that isn't itself a file (e.g. a person, a project) |
| **mia** | Short form of memoria — prefix used for plugin-managed files and commands |

Commands, functions and CLI commands are named by what they do to their noun,
one meaning per verb, each with its inverse:

| Verb | Means | Applies to | Inverse |
|---|---|---|---|
| **Register** | record something that exists outside memoria | brain | Deregister |
| **Create** | make something new | engram (a file), concept (a registry entry) | Delete (§10.2) |
| **Attach** | put a relation on the current engram | synapse, concept | Detach |
| **Edit** | change what an existing thing carries | a concept's `meta` | — |

The rest keep one meaning each already: List, Switch, Config, Rebuild, Fill,
Search. A new feature picks its verb from this table; one that fits none adds a
row here first. "Registered" still describes a concept with an entry in
`mia_concepts.json` — the registry is the file's name — but the verb that makes
one is Create, since nothing exists before it.

### 1.1 Dependency: `md-drafting.nvim`

`memoria.nvim` depends on the standalone `md-drafting.nvim` plugin (hard
dependency) for generic markdown syntax handling — formatting toggles,
generators, TOC, callouts, task cycling, jump navigation, presentation and focus
modes. `md-drafting.nvim` has no knowledge of brains, engrams, synapses, or
concepts; it only knows markdown.

`memoria.nvim` reuses `md-drafting`'s exposed API (Part 2) rather than
reimplementing link/checkbox parsing or fenced-block handling internally:

```lua
drafting.api.syntax.format_link(text, path)          --> "[text](path)"
drafting.api.syntax.parse_links(content)             --> [{text, path, col}, ...]
drafting.api.syntax.parse_checkbox(line, markers?)   --> "not_done" | "done" | nil
drafting.api.syntax.parse_heading(line)              --> level, text
drafting.api.syntax.parse_frontmatter(lines)         --> fields, closing row | nil
drafting.api.syntax.parse_list_item(line)            --> prefix, marker, text
drafting.api.syntax.format_list_item(prefix, marker, text)
drafting.api.syntax.marker_state(marker, markers?)   --> "not_done" | "done" | nil

drafting.api.section.get(lines, name)                --> string[] | nil
drafting.api.section.set(lines, name, body, opts?)   --> the rewritten lines

drafting.api.register_link_provider({ label, resolve, kinds? })
```

Where each is used:

| Function | memoria |
|---|---|
| `format_link` / `parse_links` | `write_synapse_block` / `parse_synapse_block` (§5.4–5.5), inline body links (§7.1), `link_or_create_at_cursor` (§9.2), `rename_engram` (§10.1) |
| `parse_checkbox` | the task index (§7.2) |
| `parse_list_item` / `format_list_item` | `parse_synapse_block` / `write_synapse_block` (§5.4–5.5) |
| `parse_list_item` / `marker_state` / `format_list_item` | the agenda's task toggle (§9.4) |
| `parse_frontmatter` | `tags` / `participants` and any other concept field (§5.1, §7.2); where the synapse block goes (§5.4) |
| `format_frontmatter_value` / `set_frontmatter_field` | the generated header (§8.1), `attach_concept` (§6.4) |
| `parse_heading` | an engram's `title` for the atlas (§7.1) |
| `section.get` | `parse_synapse_block` (§5.5), the atlas (§7.2), `append_to_engram` (§8.2) |
| `section.set` | `write_synapse_block` (§5.4), the atlas (§7.2), `append_to_engram` (§8.2), the generated index (§9.3) |
| `register_link_provider` | the Engram and Concept link providers (§9.2) |

`md-drafting.nvim` holds **every markdown construct it knows** in one module, not
just the handful memoria needs, so anything memoria reads out of an engram is
parsed by the same code that writes it there. Frontmatter included: memoria does
not carry its own YAML-ish scanner. `section` is the shared "read/replace
within fixed markers" mechanism, the same one that generates `md-drafting`'s
table of contents. It is two pure functions over lines, `get` and `set`, which
is what lets `append_to_engram` rewrite a file without opening it in a buffer.
Appending is not on the seam — it is `get`, insert, `set` (Part 2 §2), and
memoria writes that composition where it needs it rather than expecting a
function for it.

Two small pieces of machinery the seam deliberately does not provide, so memoria
owns them:

- **A minimal-span buffer write.** Whenever memoria rewrites an engram that is
  loaded in a buffer (a synapse added from the current note, the index
  regenerated while open), it trims the common prefix/suffix and writes only
  the span between, for the extmark reason in Part 2 §2, then saves the
  buffer. `md-drafting`'s own `util.replace_lines` is internal and not to be
  required. This is `lib/file.lua`: `read_lines` and `write_lines` take a path
  and go through the buffer when one is loaded, disk otherwise. Reading first
  runs `:checktime` on that buffer, so a file changed underneath an unmodified
  buffer is reloaded rather than written over.
- **Frontmatter list normalisation.** `parse_frontmatter` answers
  `string | string[]`, and a bare `tags:` is `""` (Part 2 §1). memoria always
  writes flow lists (`tags: []`), but a hand-edited engram need not, so every
  concept field it reads goes through one helper turning `nil`/`""` into `{}`
  and a scalar into a one-item list.

There is no `format_checkbox`: the task lines memoria writes come from
`append_templates` strings that already carry the marker (§8.2), and the agenda's
toggle (§9.4) swaps the marker through `parse_list_item`/`format_list_item`.

**Every call goes through `lib/md-drafting.lua`.** No other memoria file requires
`md-drafting`: `lib/md-drafting.lua` wraps each `api` function memoria uses, under
the same names (`md_drafting.syntax.format_link`, `md_drafting.section.set`), and
looks `api` up on each call. Two things follow:

- the file is the complete, current list of what memoria depends on — the
  table above describes intent, the wrapper is what is actually called;
- loading a memoria module never loads `md-drafting`, so a missing dependency
  surfaces as `setup()`'s message (§1.2), not as a `require` error.

A wrapper is added when a delivery first needs the function, not ahead of it.
The plugin's tests hold both properties: every wrapper names a real `api`
function, and no other file requires `md-drafting`.

See Part 2 for that API's full contract.

### 1.2 Installation and the missing-dependency case

Three package managers are assumed: `lazy.nvim`, `packer.nvim`, and Neovim's
built-in `vim.pack`. All three can declare the dependency; only the first two
resolve it automatically.

```lua
-- lazy.nvim
{ "joakimmj/memoria.nvim", dependencies = { "joakimmj/md-drafting.nvim" } }

-- packer.nvim
use({ "joakimmj/memoria.nvim", requires = { "joakimmj/md-drafting.nvim" } })

-- vim.pack — no dependency field; both must be listed
vim.pack.add({
  { src = "https://github.com/joakimmj/md-drafting.nvim" },
  { src = "https://github.com/joakimmj/memoria.nvim" },
})
```

`vim.pack.add` has no transitive resolution: it installs exactly the list
given it. For a `vim.pack` user, a missing `md-drafting.nvim` is not a
misconfiguration `lazy`/`packer` would have caught — it is one missing line,
easy to have written. The runtime guard below is not just a fallback for
that manager; it is the only thing that ever checks.

```lua
local md_drafting = require("memoria.lib.md-drafting")   -- §1.1: loads nothing yet

if not md_drafting.available() then   -- md-drafting installed, with its api table
  vim.notify(
    "memoria.nvim requires md-drafting.nvim (with its api table) — " ..
      "add it as a dependency and restart",
    vim.log.levels.ERROR
  )
  return   -- setup() aborts here; no commands or keymaps are registered
end
```

Checked once, at `setup()`, not on first use — the failure is visible the
moment Neovim starts rather than the moment `create_engram` is first called.
Checked against `drafting.api` specifically, not just that `require`
succeeded — an installed-but-stale `md-drafting.nvim` predating Part 2's
`api` table fails the same way a missing one does, rather than loading and
breaking on the first call that reaches for `api.section`. No degraded mode:
every delivery from §8.1 onward reaches into `api`, so there is nothing
partial left to offer.

### 1.3 Module layout

The same split as `md-drafting` (Part 1 §1.1) — which directory a file sits in
says what may call it:

| Path | Contents | Reached from outside as |
|---|---|---|
| `init.lua` | `setup()`: dependency guard (§1.2), config, commands | `require("memoria")` |
| `commands.lua` | Every `:Mia*` command, created by `setup()` unless `add_commands` is off | — |
| `cli.lua` | The CLI (§11): its command table, argument parsing, user-config loading, JSON output | `bin/mia` |
| `config.lua` | Built-in defaults and the tier merge (§3) | — |
| `modules/` | One file per feature — `brain`, `engram`, `synapse`, `atlas`, … | `memoria.core.<feature>` |
| `ui/` | One file per feature, mirroring `modules/` — every prompt, picker, echo, buffer and quickfix list a feature opens — plus `message` (what memoria says, and the brain it is about) | `memoria.<feature>` |
| `lib/` | Shared machinery — `md-drafting` (the only path to the dependency, §1.1), `json`, `date`, `file` (engram read/write through a loaded buffer, §1.1), `synapse` (block read/write, §5.4–5.5) | internal only |

Commands live in `lua/` rather than `plugin/` because they may only exist once
the guard has passed, which `setup()` decides. `bin/mia`, outside `lua/`, is
the CLI's executable (§11).

`modules/` is the model, `ui/` the view, and `commands.lua` and `cli.lua` the
two controllers over them. `commands.lua` holds registrations only; everything
it does is in `ui/`, so a keymap bound to `require("memoria").engram.create_engram`
behaves exactly like `:MiaEngramCreate`. `cli.lua` requires nothing under `ui/` —
it has no editor to ask in — and the tests hold that, the same way they hold
`md-drafting` to `lib/md-drafting`.

`synapse` appears three times on purpose: `lib/synapse.lua` reads and writes the
block over lines, the way `md-drafting`'s `section` does, `modules/synapse.lua`
holds `attach_synapse` (§5.6), the feature built on it, and `ui/synapse.lua` the
pickers that fill in what the user did not type. A view function carries the
same name as the model function behind it, so the two read as one feature a
layer apart.

Lua functions are snake_case, matching `md-drafting`: `create_engram`,
`write_synapse_block`.

---

## 2. Brains

A **brain** is a self-contained folder of engrams. Users can have multiple (e.g.
`work`, `personal`), located wherever they like on disk.

### 2.1 Registry

Brains are **not** part of the shared Neovim config (dotfiles), since folder
locations are machine-specific. Instead:

- Stored at `stdpath('data')/memoria/brains.json`
- Per-machine, not synced/version-controlled
- Sole source of truth for "which brains exist and where"
- Locations are stored as absolute paths, so a brain resolves the same way
  whatever the working directory

```json
{
  "work": { "location": "/home/me/dev/notes/work" },
  "personal": { "location": "/mnt/sync/dropbox/notes" }
}
```

### 2.2 Commands

Created unless `add_commands = false` (§3). `md-drafting` makes its commands
opt-in; memoria's are on by default, because there are few of them, they are
`Mia`-prefixed, and a brain is useless until one is added. They are also global
rather than buffer-local: a brain is managed from anywhere, not only from
inside a markdown buffer. Every command is
a thin wrapper over a Lua function, so nothing here needs the command to exist.

| Command | Behavior |
|---|---|
| `:MiaBrainRegister <path> [name]` | Creates `path` if missing. `name` defaults to `basename(path)`, overridable. Errors on name collision. |
| `:MiaBrainDeregister [name]` | Removes the registry entry **only** — never touches files on disk. Picks the brain when not named. |
| `:MiaBrainList` | Lists name, location, and an existence check (⚠ if location is missing/unmounted). `*` marks the active brain, `>` the one holding the current buffer, and `(config)` a brain with its own `.mia_dna.json` (§3). |
| `:MiaBrainSwitch [name]` | Sets the active brain for the session. Picks the brain when not named. |
| `:MiaBrainConfig [brain]` | Opens the brain's `.mia_dna.json` (§3), creating it as `{}` when it has none. Never fills it in: an override is what differs. |
| `:MiaEngramCreate [brain]` | Creates an engram (`create_engram`, §8.1) in the given brain. |
| `:MiaEngramSearch [brain] [query]` | Fuzzy-searches engrams by title, filename, tags and participants (`search_engrams`, §9.6); opens a picker over the results. |
| `:MiaSynapseAttach [field]` | Links the current engram to another (`attach_synapse`, §5.6), asking for the field when not given and for the target. |
| `:MiaConceptCreate [brain]` | Registers a concept (§6): name, type, then the type's schema fields. |
| `:MiaConceptAttach [field]` | Puts a concept in the current engram's concept field (§6.4): the field picked when not given, then the concept, its `concept_type` first. The engram decides the brain, as for `:MiaSynapseAttach`. |
| `:MiaConceptEdit [brain]` | Picks a concept and fills in its `meta`, one prompt per schema field (§6.4). |
| `:MiaConceptList [brain]` | Lists the brain's concepts by type, with how many engrams name each and ⚠ for none. |
| `:MiaConceptFill [brain]` | Walks the undeclared concepts, most-used first (§6.4): each is registered, or made an alias of an existing one. |
| `:MiaAtlasRebuild[!] [brain]` | Rebuilds the atlas and reports problems in the quickfix list (§7.2). `!` repairs what can be repaired first. |

The active brain is in-memory only and starts unset. Anything acting on "the
current brain" without being given one resolves it in this order:

```
1. the brain named by the caller
2. the registered brain whose location holds the current buffer's file
3. the active brain
4. the only registered brain, when there is exactly one
5. a picker over registered brains
```

Step 2 comes before the active brain because a note being edited says which
brain it belongs to more reliably than a switch made earlier in the session.
That also means the active brain is not always the one acted on, which is why
`:MiaBrainList` marks both — `>` wins over `*` when they differ. Step 4 means
a registry with one brain in it never opens a one-entry picker.

Steps 1–4 are the model's (`brain.resolve`), step 5 the view's: a picker has no
answer until it is asked, and there is nobody to ask headless. That split is
also why **a brain that was named but is not registered is an error and never
reaches the picker** — the caller said which one. Headless (the CLI, §11) there
is no buffer and no active brain, so steps 1 and 4 are the two that can answer,
and anything else is an error.

**A missing argument is asked for, not an error** — with one exception. How it
is asked depends on what the command does with a brain:

- Commands that act *in* a brain (`:MiaBrainConfig`, `:MiaEngramCreate`,
  `:MiaAtlasRebuild`, the four `:MiaConcept*`) resolve it in the order above,
  and ask for anything else inside it. The concept commands take the brain,
  not a concept name, as their argument for that reason: a concept name typed
  before its brain is decided could name a concept in a brain the picker then
  does not choose, and its completion could only guess which brain to list.
  The view functions behind them take `(brain, name?)` — a name given there is
  taken as given, never prompted for again.
- Commands that *choose* a brain (`:MiaBrainSwitch`, `:MiaBrainDeregister`) go
  straight to step 4's picker. Switching to the brain already in use does
  nothing, and deregistering whichever brain the open buffer belongs to is a
  surprise, not a default.
- `:MiaBrainRegister` requires its path. A folder is not something a prompt or a
  list of names picks well, so it waits for a folder browser rather than
  asking with the wrong tool.

**Anything that prompts names its brain**, e.g. `(work) Engram title:` — every
prompt and picker a brain-scoped feature opens, in this delivery and later ones.
The resolution above is invisible otherwise: a prompt would not say which of
the four steps answered it, and creating a note in the wrong brain is only
noticed afterwards. Step 4's own picker is the exception, since it is what
decides the brain.

### 2.3 Brain contents (flat, no subfolders)

```
my-brain/
├── mia_concepts.json    (visible — hand-editable registry, mia-branded but not hidden)
├── .mia_atlas.json      (hidden — derived, rebuildable index)
├── .mia_dna.json        (hidden — optional, brain-specific config overrides)
├── index.md             (optional — generated overview, see §9.3)
├── 20260801_project-x.md
├── java_optional-stream.md
└── ...
```

A bare folder with nothing but `.md` files is a valid brain — `.mia_atlas.json`,
`.mia_dna.json` and `index.md` are all optional, generated/used on demand.
Unlike the other two, `index.md` is a normal engram once created: no `mia_`
brand, no dot-prefix, since it lives in the brain the same way any other note
does.

`mia_concepts.json` is deliberately styled differently from the two hidden
`.mia_*` files: it carries the `mia_` brand (so it visually reads as
plugin-related, distinct from the engram files sitting next to it) but is **not**
dot-prefixed, since it's the one file meant to be casually browsed and
hand-edited. In a sorted listing you end up with three distinct shapes at a
glance — dated engram files, a plain `mia_`-prefixed registry, and dot-hidden
plugin internals.

---

## 3. Configuration layers

Three tiers, merged in order (later overrides earlier, deep-merged so partial
overrides don't wipe sibling keys):

```
1. Plugin built-in defaults
2. require('memoria').setup({...})   — shared, safe for dotfiles
3. <brain>/.mia_dna.json             — per-brain delta only
```

Config is grouped by the three core concepts — `engrams`, `synapses`, `concepts`
— rather than a flat/misc `defaults` bucket:

```lua
require('memoria').setup({
  add_commands = true,           -- create the :Mia* commands (§2.2)
  engrams = {
    date_format = "YYYYMMDD",    -- used by both filename prefix and %date% placeholder
    filename = {
      prefix = "date",           -- "date" | "concept" | "none"
      separator = "_",
    },
    content_template = "# %title%\n\n%cursor%",
    task_markers = {             -- passed straight to parse_checkbox: keys must be
      not_done = { "[ ]" },      -- md-drafting's state names, not_done / done
      done = { "[x]", "[X]" },
    },
    index = {
      filename = "index.md",     -- lives at brain root
      sections = { "stats", "recent", "concepts", "roots", "not_done_tasks", "tasks" },
      stats = { "total_engrams", "total_concepts", "not_done_tasks" },
    },
  },
  synapses = {
    up   = { target = "engram", inverse = "down", list = true, show_empty = true },
    down = { target = "engram", inverse = "up",   list = true, show_empty = true },
    tags = { target = "concept", concept_type = "tag", list = true },
  },
  concepts = {
    tag = { fields = { "description" } },
  },
  append_templates = {
    todo = { section = "TASKS", render = "- [ ] %input%" },
    log  = { section = "LOG",   render = "- %date% — %input%" },
  },
})
```

Keys are snake_case throughout, the same as `md-drafting`'s own config, and
`.mia_dna.json` spells them the same way.

`add_commands` is the one key read from the first two tiers only: commands are
global to the editor, so a brain has no say in whether they exist.

`:MiaBrainConfig` (§2.2) opens the file, creating an empty `{}` when the brain
has none — the file is hand-edited from there. It is deliberately not seeded
with the merged config: a copy of every value would freeze that brain against
later changes to the defaults or to `setup({})`, and hide what is actually
special about the brain. JSON has no comments, so what may go in the file is
documented rather than written into it.

`.mia_dna.json` (per-brain) contains **only the fields that differ** from the
merged defaults — kept minimal and diffable, e.g.:

```json
{
  "engrams": { "filename": { "prefix": "none" } }
}
```

### 3.1 Config resolution

```
load_brain_config(brain_path):
  1. built_in = plugin_built_in_defaults
  2. user_config = neovim_setup_config
  3. merged = deep_merge(built_in, user_config)
  4. override_path = brain_path + "/.mia_dna.json"
  5. if exists(override_path):
       merged = deep_merge(merged, read_json(override_path))
  6. restore_required(merged)   -- see null, below
  7. return merged
```

`deep_merge` follows `md-drafting`'s rule: maps merge by key, **lists replace
wholesale**. `task_markers = { done = { "[x]" } }` means exactly `[x]`, not the
default's `[x]`/`[X]` plus another `[x]`; the same goes for `index.sections`.

A `.mia_dna.json` that cannot be read or is not valid JSON is reported with an
error naming the file, and that tier is skipped — the brain still works on the
first two.

**`null` means "not the value from above"** — a missing key and a `null` are
different answers. Left out, a key follows the tier above it. Set to `null` —
`vim.NIL` from `setup({})`, where a plain `nil` cannot be told from absent — it
is removed, and what that leaves depends on the key:

- **An entry in `synapses`** is optional, so it stays removed:
  `{ "synapses": { "up": null } }` gives that brain no `up` field. This is the
  only way to drop a default field, since maps otherwise only ever merge in.
- **Any other setting** is required, so it falls back to the **built-in**
  default, skipping `setup({})`'s value: `{ "engrams": { "date_format": null } }`
  undoes a date format set globally. A config never ends up without a setting
  the code reads.

---

## 4. Filenames

Three prefix modes, set via `engrams.filename.prefix`:

| `prefix` | Example | Notes |
|---|---|---|
| `"date"` (default) | `20260801_project-x.md` | Uses `engrams.date_format` (default `YYYYMMDD`). Mixed formats across engrams in the same brain are harmless — purely cosmetic, doesn't affect parsing/linking, just slightly noisier sort order. |
| `"concept"` | `java_optional-stream.md` | See §4.1 — prefix is picked from (or added to) `mia_concepts.json`. |
| `"none"` / unset | `optional-stream.md` | No prefix. |

The slug is derived from the **title** the user types at creation, which is
kept as typed for `%title%` (§8.1): `Note about Java` → `note_about_java`. The
title stays readable in the document; the filename stays safe and predictable.

```
slugify(title, separator):
  1. trim, lowercase (Unicode-aware — `Østers` → `østers`)
  2. drop characters no common filesystem allows: / \ : * ? " < > |
  3. whitespace runs → separator
  4. collapse repeated separators; strip separators and dots at either end
```

Everything else is kept — `project-x` stays `project-x`, non-ASCII letters stay
letters. A title that slugifies to nothing (`???`) is asked for again.

- `engrams.date_format` — used by the `"date"` filename prefix *and* the `%date%`
  content-template placeholder (§8.1). One setting, two consumers — no risk of
  filename dates and in-content dates disagreeing.
- `date_format` tokens: `YYYY`, `YY`, `MM`, `DD`, `HH`, `mm`, `ss`; anything else
  is written literally
- `filename.separator` — default `"_"`
- Collision rule (same prefix + slug already exists): prompt the user to edit the
  title (see §12); headless, where there is nobody to prompt, it is an error

Filename is treated as **immutable identity** once created — it should not change
even if the engram's title (H1/frontmatter) is edited later. This avoids
propagating a rename through every synapse link every time a typo is fixed in the
display title. A deliberate house-keeping rename is a separate, explicit action
(§10.1).

### 4.1 Concept-prefix selection

When `prefix == "concept"`, engram creation includes a picker step:

```
:MiaEngramCreate, prefix == "concept":
  1. pick_or_create(brain): the registry's concepts + "+ Create new concept"
  2a. existing concept selected → it is the prefix
  2b. "create new" selected →
        prompt for name, type, then the type's schema fields
        create_concept(name, type, fields)   // registers it
  3. only then the title prompt — a collision re-asks the title, never the concept
  4. create_engram(brain, { title, concept = name })

create_engram, prefix == "concept":
  1. no opts.concept → nil, "a concept is required", code "concept"
  2. resolve_concept(opts.concept) — unknown → code "concept"; an alias
     resolves to its concept, whose own name is what is used from here on
  3. slugify(name, separator) (§4) for the prefix
  4. add the name to its concept field: the first whose concept_type is the
     concept's type, else the first expecting no type, else the first
```

`M.filename(cfg, slug, opts)` takes the concept as `opts.concept`, beside
`opts.time`. The headless path asks nothing: the CLI passes `--concept`, and a
concept that is not registered is an error there rather than an implicit
registration — registering needs a type nobody supplied.

This reuses the same "pick or create a concept" interaction needed elsewhere
(e.g. resolving undeclared concepts, filling `participants`) rather than being
bespoke to filenames.

**The chosen concept is also added to the engram's tags/concept fields**, not
just used cosmetically as a prefix. This keeps the two in sync — a `java_` prefix
without a `java` tag would be findable by eye in a file listing but invisible to
search/index, which defeats the purpose. As a side effect, this closes the
"undeclared concept" gap for prefix-picked concepts specifically: since the
picker forces resolution (existing entry or newly registered) at creation time, a
prefix concept can never end up undeclared the way a freely-typed tag elsewhere
in a note still could.

---

## 5. Synapses (engram-to-engram connections)

### 5.1 Where they live

Not YAML frontmatter — a **fenced body block**, using the same "regenerate fully
between markers" mechanism as TOC generation (Part 2 §2):

```markdown
---
participants: [Alice Smith, Pete Park]
tags: [java]
---
<!-- SYNAPSES -->
- **down:** [note1aa](note1aa.md), [note1ab](note1ab.md)
- **up:**
***
<!-- /SYNAPSES -->
# Some Note heading
...
```

Rationale: plain markdown links (`[text](path)`) render as clickable in any
markdown viewer, including GitHub. YAML frontmatter values do not.

**The whole header is laid out for vertical space**, since it sits above the
text the writer opened the engram for. Everything is one line per field, and
nothing costs a line of its own that does not have to:

- **Frontmatter uses flow lists** (`tags: [java]`): a field stays one line
  whatever it holds, where block style costs a line per value (Part 2 §1).
- **Synapse fields are list items**, one per field. A tight list puts each
  field on its own rendered line with no blank lines between items and no
  hard-break syntax to maintain.
- **The separator is inside the section, as `***`.** Being inside, it is
  regenerated with the block, so it is always present and never orphaned.
  `***` cannot be read as a setext underline and does not look like a
  frontmatter delimiter.
- **Fields are sorted by name**, in frontmatter and in the block. Lua tables
  have no key order, so config order cannot be the rule; sorting keeps every
  generated header identical for the same config.
- **One blank line between the header and the prose**, written by `create_engram`
  rather than the template, and only when there is a header: it separates the
  two parts, so it belongs to whichever of them can be absent. A template
  cannot know whether the brain's config leaves any header (§5.4, §8.1).

Rendered (CommonMark, verified): frontmatter table on GitHub, a two-item list,
a rule, the heading.

The block sits at the top, directly under the frontmatter, so all note data is
together; the end of the file belongs to `append_to_engram`'s sections (§8.2).

### 5.2 Field config

Each synapse field is declared under `synapses` in config:

| Property | Meaning |
|---|---|
| `target` | `"engram"` (relative link to another engram) or `"concept"` (name/alias, resolved against `mia_concepts.json`) |
| `concept_type` | (target: concept only) which concept `type` this field expects, e.g. `"person"`, `"tag"`. Advisory, not enforced — see below. |
| `list` | whether multiple values are allowed. `false` also writes the value itself rather than a list of one — `room: kitchen`, or a bare `room:` when empty — which reads back the same either way |
| `inverse` | (target: engram only) the paired field to auto-sync, e.g. `up ↔ down` |
| `show_empty` | whether the field's line always appears, even with no values (default: `true`) |

Only `target: "engram"` fields live in the synapse block. `target: "concept"`
fields (e.g. `tags`, `participants`) are flow-style YAML lists in frontmatter — no
inverse, since concepts aren't files.

`participants` is the other obvious concept field — a `person`-typed one — but
it is configured per brain rather than shipped: not every brain is about
meetings, and an empty `participants: []` in every engram of a recipe brain is
noise. The default is the three fields every brain uses: `up`, `down`, `tags`.

**`tags` is a normal configured field**, not a special case — it ships as
`{ target = "concept", concept_type = "tag", list = true }` by default, which is
what makes tag metadata possible at all (a bare string can't hold a `meta`
object; a field resolving against `mia_concepts.json` can). A tag that's never
given a `mia_concepts.json` entry behaves exactly as a plain label always has —
metadata is opt-in, not required.

`concept_type` is **required on every concept field, and is a constraint**: the
field takes that one type and refuses every other, so `participants` holds
people and `tags` holds tags. It is what the config has to say "only people
belong here" with, and a field declaring none takes nothing — a mistake
reported at `setup()` rather than a field read as taking anything.

Putting a `room` on an engram therefore means configuring a field for rooms
(`rooms = { target = "concept", concept_type = "room" }`), not writing one into
`tags`. Only a name the registry does not answer to is free: it has no type, so
it contradicts no field and stays the plain label a bare tag has always been —
`check` reports it as undeclared (§7.2), which is the state `:MiaConceptFill`
exists to clear.

The field also decides what its pickers offer (§4.1, §6.4): attaching to
`participants` lists `person` concepts and nothing else, and a concept created
there is a `person` without being asked.

### 5.3 Format rules

- One list item per field: `- **label:** item1, item2`, written and read through
  `drafting.api.syntax.format_list_item` / `parse_list_item`
- Always `- ` as the bullet, no checkbox marker
- An empty field is `- **label:**` with no trailing space — trailing whitespace
  is what editors strip, and a line that changes on save is a spurious diff
- All configured fields always emitted (per `show_empty`), even blank — a visible
  "no parent" is a feature, not noise
- One line, no wrapping regardless of item count
- Comma-separated markdown links; parsed via `drafting.api.syntax.parse_links` —
  no bracket-nesting needed
- Link text is the target's filename without `.md`
  (`[20260801_project-x](20260801_project-x.md)`): it is the engram's identity
  (§4), so it never goes stale the way a copied title would
- Last body line is `***`; anything that is not a field item is ignored on
  parse and dropped on the next write
- A field item the config does not name — one added by hand, or a field since
  removed from config (§3.1) — is kept on every write, sorted in with the rest
- Labels match `[%w_]+`, so a configured field like `related_to` parses

### 5.4 Write (regenerate block)

```
write_synapse_block(lines, engram, synapse_fields):
  1. body = []
  2. names = synapse_fields where target == "engram"
             ∪ every other key in engram.synapses   -- hand-added fields kept
     for name in names, sorted:
       values = engram.synapses[name] || []
       if name is configured, values is empty and show_empty == false: continue
       link_str = values.map(v => drafting.api.syntax.format_link(v.title, v.path)).join(", ")
       text = `**${name}:**` + (link_str == "" ? "" : " " + link_str)
       body.push(drafting.api.syntax.format_list_item("- ", nil, text))
     if body is empty: return lines   -- no field line, no block
     body.push("***")
  3. _, fm_end, err = drafting.api.syntax.parse_frontmatter(lines)
     if err: return nil, err            -- unreadable, not absent
  4. return drafting.api.section.set(lines, "SYNAPSES", body, { at = (fm_end or 0) + 1 })
```

The markers themselves are `drafting.api.section`'s business, not this
function's — same mechanism, same marker shape, as the table of contents. A first
write with no block present puts one in.

A block with no field line to show is not written at all: a rule between two
markers says nothing. That covers a brain whose config removes every engram
field (§3.1) and one whose fields are all `show_empty = false` with no values
yet. Nothing depends on the block existing ahead of time, since the first write
that has something to show creates it.

**Frontmatter is only ever read here, never rewritten**, so fields memoria does
not know — `author:`, `status:` — survive every block write. Frontmatter that
cannot be read is an error rather than "no frontmatter": treating it as absent
would put the block at row 1, above the opening `---`, which then no longer
opens the file and stops being frontmatter for every reader. The write is
refused with the parse error instead, and the file is left as it is.

`opts.at` matters only on that first write, and it cannot be left out: `set`
defaults to the **end** of the file, while the block belongs directly under the
frontmatter (row after its closing `---`, or row 1 without any). An existing
block is replaced where it stands, wherever that is.

Returns lines rather than writing: callers either write the file (most paths)
or push it into a loaded buffer through memoria's minimal-span write (§1.1).

### 5.5 Parse

```
parse_synapse_block(lines):
  1. lines = drafting.api.section.get(lines, "SYNAPSES")    // nil = no block, {} = empty block
  2. result = {}
  3. for line in lines:
       prefix, marker, text = drafting.api.syntax.parse_list_item(line)
       if not prefix: continue                        // the *** rule, stray prose
       label, content = text.match("^%*%*([%w_]+):%*%*%s*(.*)$")
       if not label: continue
       result[label] = drafting.api.syntax.parse_links(content)  // [{text, path, col}, ...]
  4. return result
```

`marker` is ignored rather than rejected: an accidental `task.toggle` on a field
line (`- [ ] **up:** …`) still parses, and the next write drops the checkbox.

### 5.6 attach_synapse (inverse sync)

```
attach_synapse(opts):           -- opts = { source?, target, field }
                             -- → { brain, source, field, target } | nil, err
  1. source = opts.source or the current buffer's file; locate() gives the
     brain whose folder holds it directly — no brain picker, the engram decides
  2. refuse a missing field or target
  3. connect(brain, source, target, field)
  4. refresh the atlas (§7.1)

connect(brain, source, target, field):     -- → true | nil, err
  1. refuse: field not a configured engram field, source == target, either
     file missing
  2. add target to source.synapses[field], unless already there
  3. inverse = field.inverse, if it names a configured engram field:
       add source to target.synapses[inverse], unless already there
  4. a field with list = false gives up the value it held, and that engram
     loses source from its inverse field
  5. every touched file: read_lines → parse_synapse_block → edit →
     write_synapse_block; any unreadable frontmatter aborts before any write
  6. write_lines each file whose lines changed (§1.1)
```

`connect` is idempotent: values already present are left alone, so running it
on a one-sided synapse writes only the missing inverse. That is also how
`rebuild_atlas` repairs one (§7.2). A field with no `inverse`, or whose
`inverse` is not a configured engram field, is written on the source only.

`attach_synapse` opens nothing and asks nothing — that is how the CLI calls it
(§11), where there is no current buffer to take the source from. The pickers
that fill in `field` ("(work) Synapse field:", skipped when the brain has only
one engram field) and `target` (over the atlas's engrams, the source left out,
"(work) up:", entries as "Title (filename)") are `:MiaSynapseAttach`'s, in `ui/`,
the same way the brain picker is (§2.2).

Note: fields are only ever *auto-generated* by the plugin according to config —
nothing prevents a user from manually adding an unconfigured field, or removing
`tags`, directly in the file. The config defines what the plugin automates, not
what's valid.

---

## 6. Concepts (persons, topics, etc.)

Concepts are lightweight, non-file "things" an engram can reference — replacing
what would otherwise require an engram-per-person.

### 6.1 Storage — `mia_concepts.json`, keyed by name

Flat object, visible (not hidden), hand-editable:

```json
{
  "Alice Smith": {
    "type": "person",
    "aliases": ["Alice", "AS"],
    "note": "Met at conference 2024",
    "meta": {
      "email": "alice@example.com",
      "role": "designer"
    }
  },
  "java": {
    "type": "tag",
    "meta": { "description": "Java-related engrams", "color": "#f89820" }
  }
}
```

- `type` — required, and one the brain has: a type with a schema under
  `concepts` (§6.2), or one the registry already uses. Nothing else is offered
  or accepted, so a type cannot be coined by a typo; a genuinely new one starts
  with its schema in the config
- `aliases`, `note` — optional
- `meta` — free-form, shaped (advisory only) by `concepts[type].fields` in config
- Written two-space indented with keys sorted, one per line: it is the file
  meant for hand-editing, and a problem pointing at an entry (§7.2) needs a row
  to point at. Empty `aliases`/`meta` are left out rather than written empty.
- Known limitation: renaming a concept means changing its key, and propagating
  that change to every engram referencing the old name (including any filenames
  prefixed with it). Same class of problem as file renames — no separate `id`
  layer, traded for readability.

### 6.2 Concept type schemas (config, under `concepts` in `setup({})`)

```json
{
  "person": { "fields": ["email", "role", "org"] },
  "tag": { "fields": ["description", "color"] }
}
```

Drives UI form fields when editing a concept's `meta`, and is the list a type
is picked from (§6.1): the schema keys, plus the types the registry already
uses. A type with an entry here but no fields asks for nothing beyond the
name and the type.

Only `tag = { fields = { "description" } }` ships as a default, since `tags` is
the one concept field that ships (§5.2); `person` above is an example, for the
same reason `participants` is. `concepts` is an optional-entries map like
`synapses` (§3): a schema removed with `null` stays removed.

The "form" is one prompt per schema field (`(work) Alice Smith email: `),
filled in with the current value, then one per `meta` key the concept already
carries that the schema does not name, so nothing is dropped by going unasked.
Leaving a prompt as it is keeps the value; clearing it removes the key.

### 6.3 Resolving mentions

```
resolve_concept(mention_text):
  1. if mention_text is a key in mia_concepts.json → return it
  2. else scan all concepts' aliases for a match → return it
  3. else → undeclared
```

Object-keyed-by-name structure guarantees no duplicate names, sidestepping the
collision problem entirely.

### 6.4 Finding & filling in undeclared concepts

```
find_undeclared_concepts(brain):      -- → { name, count, engrams }[] | nil, err
  1. mentions = the atlas's concepts map (§7.1), refreshed
  2. undeclared = [ m for m in mentions if resolve_concept(m) is null ]
  3. count = how many engrams name it (not occurrences within one)
  4. return undeclared, sorted by count desc, then by name
```

```
set_concept_meta(brain, name, type?, fields):   -- → concept | nil, err
  1. entry = concepts[name] || { type }   // type required only for a new one
  2. entry.meta = entry.meta || {}
  3. for key in fields:
       entry.meta[key] = fields[key]      // "" removes the key
  4. concepts[name] = entry; write mia_concepts.json

create_concept(brain, name, type, fields?):        -- → concept | nil, err
  refuse a name already registered, else set_concept_meta

add_alias(brain, name, alias):                  -- → concept | nil, err
  refuse an alias that already resolves to another concept

attach_concept(opts):       -- opts = { source?, field, concept }
                            -- → { brain, source, field, concept } | nil, err
  1. source = opts.source or the current buffer's file; locate() gives the
     brain — no brain picker, the engram decides (as for attach_synapse, §5.6)
  2. refuse a field that is not a configured concept field, or no concept
  3. name = resolve_concept(opts.concept), else opts.concept as given
  4. already in the field → nothing written; list = false → it replaces
  5. set_frontmatter_field (Part 2 §1), written through a loaded buffer
     (§1.1); unreadable frontmatter aborts before any write
  6. refresh the atlas (§7.1)
```

Unknown meta keys are written like any other; saying so is the caller's job
(the view warns), since the model notifies nothing. `create_concept` is the
create-only door `:MiaConceptCreate` and the CLI's `create-concept` use, so a
duplicate name is an error rather than a silent merge; `set_concept_meta` is the
upsert `:MiaConceptEdit` uses.

Reviewing/filling undeclared concepts is an optional, user-initiated cleanup pass
— never blocks writing. (Concept-prefixed filenames are the one exception: see
§4.1, where resolution happens at creation time via the same picker.)
`:MiaConceptFill` walks them through the pick-or-create picker: picking an
existing concept makes the mention its alias (`add_alias`), creating one
registers the mention under its own name. No engram is rewritten either way.

The one pick-or-create lives in the view (`ui/concept.lua`) and is shared by
`:MiaConceptAttach`, `:MiaConceptEdit`, `:MiaConceptFill`, the concept filename
prefix (§4.1), and the Concept link provider (§9.2).

`attach_concept` writes a name nothing declares as given, the way a hand-typed
tag would be: bare labels stay possible headless (`attach-concept`). Through
`:MiaConceptAttach` a name that is not picked is created first — the picker
always ends at a declared concept, which is what keeps the editor from
producing the undeclared state `:MiaConceptFill` exists to clean up. A caller passes the expected `concept_type`
(§5.2) to list that type first — never to hide the rest.

---

## 7. Atlas (index)

Fully derived data — disposable, rebuildable from engrams + concepts at any time.

### 7.1 Storage — `.mia_atlas.json` (hidden)

```json
{
  "engrams": {
    "20260801_project-x.md": {
      "title": "Project X",
      "tags": ["java"],
      "synapses": { "up": ["..."], "down": [] },
      "links": ["20260731_meeting-notes.md"],
      "participants": ["Alice Smith"],
      "modified": "2026-08-01T10:00:00Z",
      "hash": "a1b2c3"
    }
  },
  "backlinks": {
    "20260731_meeting-notes.md": ["20260801_project-x.md"]
  },
  "concepts": {
    "java": ["20260801_project-x.md", "java_optional-stream.md"]
  },
  "concepts_by_type": {
    "person": ["Alice Smith", "Pete Park"],
    "tag": ["java"]
  },
  "tasks": {
    "not_done": [
      { "engram": "20260801_project-x.md", "line": 12, "text": "Call Alice about budget" }
    ],
    "done": [
      { "engram": "20260731_meeting-notes.md", "line": 4, "text": "Send follow-up email" }
    ]
  }
}
```

- `backlinks`, `concepts`, `concepts_by_type`, and `tasks` are all derived from
  `engrams` + `mia_concepts.json` — regeneratable, not authoritative
- Per engram: `title` is the first heading (the filename without `.md` when
  there is none), `synapses` the block's fields as filenames, `links` the
  engrams its body links to, and one list per concept field (`tags`,
  `participants`, …) read from frontmatter. A field sharing a name with one of
  these keys is not indexed. An engram whose frontmatter cannot be read also
  carries `error`.
- `backlinks` maps a filename to every engram linking it, by synapse or inline
  link, whether that file exists or not
- `hash`/`modified` per file enables incremental re-indexing (skip unchanged
  files). A top-level `config` fingerprint of `synapses` and
  `engrams.task_markers` re-parses everything when either changes.
- A second top-level fingerprint, `concept_registry`, hashes `mia_concepts.json`
  — which is not an engram, so the per-file pass never sees it. It is kept apart
  from `config` on purpose: a `config` mismatch re-parses every engram, while a
  registry edit changes nothing about how an engram parses, only what is
  derived from it and what `check` reports. So a registry mismatch re-derives
  and writes, and re-parses nothing. An atlas that predates the key has it
  empty, which costs one re-derive.
- **The atlas refreshes on read.** Whatever reads it (`attach_synapse`'s picker,
  `create_engram` after writing, `rebuild_atlas`) first brings it up to date:
  every top-level `.md` file is hashed, new and changed ones parsed, vanished
  ones dropped, and the file written only when something changed. No autocmds,
  so an engram edited outside Neovim is picked up the same way as one edited
  inside it.
- Inline body links (not synapses) are tracked here only — never written back
  into the referenced engram's file. Backlinks are computed/displayed live from
  this atlas, not "materialized" into files, to avoid drift/noise from
  frequently-changing prose.
- The `concepts` map covers both registered concepts (with a `mia_concepts.json`
  entry) and plain tags without one (e.g. `#todo`) — same lookup shape, string
  key to list of files. A mention is keyed by the concept it resolves to
  (§6.3), so an engram writing the alias `Alice` indexes under `Alice Smith`:
  otherwise a concept used only by alias would read as orphaned, and asking
  for it by name would find nothing. `engrams --concept` (§11.3) resolves its
  argument the same way, so either spelling finds it.
- `concepts_by_type` exists purely to make `concept_type`-filtered pickers fast
  (§4.1, §5.2, §6.4) — grouping-by-type stays out of `mia_concepts.json` itself
  (which remains flat, uniquely-keyed by name) and lives only here, where it's
  free to regenerate on rebuild. A concept with no `type`-schema entry still
  appears here, grouped under whatever string its `type` happens to be. It
  lists every registered concept, referenced or not — a concept not yet used is
  exactly what a picker should offer — and one with no `type` at all groups
  nowhere.
- `tasks` is a simple two-bucket (`not_done`/`done`) index over checkbox syntax —
  deliberately no metadata (no due dates, no priority), so task lines stay plain,
  portable markdown readable anywhere, including GitHub. Populated via
  `drafting.api.syntax.parse_checkbox(line, engrams.task_markers)` during rebuild.
  The bucket names are the states `parse_checkbox` answers with, so the result
  indexes `tasks[state]` directly with no translation table in between.
  This is what powers `:MiaAgenda` (§9.4) and the generated index's task
  sections (§9.3) without re-scanning every file live.
- `engrams.task_markers` (§3) says which markers land in which bucket, defaulting
  to GitHub-flavored `[ ]` and `[x]`/`[X]`. It is handed to `parse_checkbox`
  as-is, so it has that argument's shape exactly — `{ not_done, done }`. A key
  named anything else is not an error, just a bucket that never fills. Supplying it replaces `md-drafting`'s defaults rather
  than merging with them (Part 2 §1). It exists because a brain may already
  be full of notes written with someone else's convention, and an unrecognised
  marker is a task silently missing from the agenda. It is memoria's setting, not
  `md-drafting`'s: `md-drafting`'s own `task_states` governs what its cycling
  command *writes* and has nothing to do with what memoria *indexes*, so changing
  one never quietly changes the other.

### 7.2 Rebuild / consistency check

One traversal, several jobs:

```
rebuild_atlas(brain):
  for each engram in brain:
    drafting.api.syntax.parse_frontmatter → tags, participants, any other concept field
                (normalised to lists, §1.1)
    parse_synapse_block + drafting.api.syntax.parse_links over the body
    drafting.api.syntax.parse_heading on the first heading → title
    scan lines outside the SYNAPSES section:
                state = drafting.api.syntax.parse_checkbox(line, config.engrams.task_markers)
                → state and tasks[state].push(...)   -- "not_done" | "done"
                (field items carry no checkbox, but one toggled by accident must
                not land in the agenda)
    check: do synapse targets exist as files?
    check: does each synapse have its inverse written on the target?
    check: does each participant/concept resolve via resolve_concept?
    check: can the frontmatter be read?
    update engrams/backlinks/concepts/concepts_by_type/tasks in atlas
  write .mia_atlas.json

  report, into the quickfix list, each at the offending line:
    - broken links, synapse or inline (target file missing)
    - missing inverse synapses
    - unreadable frontmatter
    - undeclared concepts in use
    - orphaned concepts (registered, zero engrams reference them)
```

`rebuild_atlas(brain_name?, opts?)` ignores every stored hash — the same
result as deleting `.mia_atlas.json` first — and answers `{ atlas, problems }`
(`nil, err` when the brain cannot be read). Each problem carries a `kind` —
`broken_synapse`, `missing_inverse`, `broken_link`, `unreadable_frontmatter`,
`undeclared_concept`, `wrong_concept_type`, `orphaned_concept` — and
`locate_problems(brain,
problems)` resolves each one's file and row, reading every file it names once.

The two concept kinds differ in what they belong to:

- `undeclared_concept` — one per engram naming it, reported with that engram's
  other rows, anchored on the concept field's frontmatter line (`tags:`) rather
  than wherever the text next appears in the prose.
- `wrong_concept_type` — a concept in a field that takes another type (§5.2),
  anchored on the same line and naming both types. Only a hand-edited engram
  can hold one: every command and the CLI refuse to write it.
- `orphaned_concept` — belongs to no engram. It carries `concept` and no
  `engram`, and `locate_problems` points it at `mia_concepts.json`, on the line
  of its quoted key — the line you would delete. An alias naming it counts as
  a reference.

All three are reported **only once the registry holds a concept**. A brain that has
declared nothing is not told that everything it writes is undeclared, which
would otherwise happen the moment an empty `{}` registry appeared. Declaring
one concept opts the brain in. None has a `repair`: registering needs a type
nobody can invent, and deleting an entry is destructive, so
`:MiaAtlasRebuild!` leaves both in the report and `:MiaConceptFill` (§6.4) is
the fixer for the first. `:MiaAtlasRebuild` is it as a command, and the
command is what reports: the quickfix list opens when there is anything in it,
and a summary line (`(work) 42 engrams, 3 problems`) is notified either way.
The CLI's `check` and `rebuild` hand the same located problems back as JSON
(§11).

**Repair is opt-in**: `opts.fix` (`:MiaAtlasRebuild!`) first writes every
missing inverse through `attach_synapse`'s `connect` (§5.6), then regenerates
every existing `SYNAPSES` block from config — which backfills a field line for
engrams predating a newly-added synapse field (config always wins going
forward; old engrams aren't rewritten until this runs). Engrams without a
block are left alone. What cannot be repaired — a link to a file that is not
there — stays in the report.

---

## 8. Creating and appending to engrams

### 8.1 `create_engram(brain_name, opts?)`

The standard "start a new note" flow. Content is assembled in two parts: a
**generated header** (always structurally correct per config, never
hand-templated) and a **user-authored prose template**.

```
create_engram(brain_name, opts?):   -- opts = { title, fields?, body?, concept? }
                                 -- → { path, cursor } | nil, err, code
  1. resolve brain config
  2. determine filename per config.engrams.filename (§4)
     - title = opts.title, required; a missing one is an error
     - slug = slugify(title, config.engrams.filename.separator) (§4)
  3. header_lines =
       { "---", render_frontmatter_fields(config.synapses where target == "concept") ..., "---" }
       // one flow-style line per field, sorted by name: "tags: []",
       // filled from opts.fields where given: "tags: [java, streams]"
       // no concept fields → {} — no frontmatter at all
     generated_header = write_synapse_block(header_lines, empty_engram, config.synapses where target == "engram")
       // no block yet → set writes one at the row after the frontmatter, i.e. the end here;
       // the *** separator is part of the block; no engram field lines → no block
  4. prose = render_template(config.engrams.content_template, { title, date })
  5. content = generated_header + (generated_header is empty ? [] : [""]) + prose
  6. cursor_pos = locate "%cursor%" in rendered prose (default to end-of-content if absent)
  7. write file (%cursor% replaced by opts.body, or stripped), refresh the atlas (§7.1)
  8. answer the path and cursor_pos
```

`opts.fields` maps a concept field to its values, `{ tags = { "java" } }` (a
bare string is one value); a key that is not a configured concept field is an
error rather than a line the header would not otherwise have. A value that would
read as flow-list structure rather than text — one holding `[`, `]`, `,`, `:`, a
quote, or edge whitespace — is written double-quoted, so what memoria writes is
what `parse_frontmatter` reads back. `opts.body` lands where the cursor would,
so the template's heading and layout still frame it.

A failure that a re-typed title would fix carries a `code`: `empty_slug` for a
title that slugifies to nothing, `collision` for a filename already taken,
`prefix` for an unsupported `filename.prefix`, which no title can fix, and
`concept` for a `"concept"` prefix given no concept, or one not registered
(§4.1) — which the command has already picked, so it does not re-ask either.
`opts.concept` names that concept; it is also merged into `opts.fields`.
`:MiaEngramCreate` is what asks: it prompts `(work) Engram title:`, and asks again
on the first two codes with the error in the prompt. `create_engram` itself prompts
for nothing.

Resulting structure:

```markdown
---
tags: []
---
<!-- SYNAPSES -->
- **down:**
- **up:**
***
<!-- /SYNAPSES -->

# %title%

```

The blank line under the block is `create_engram`'s, not the template's; with no
header at all the file starts at `# %title%`.

`content_template` only ever covers the prose — the header (frontmatter + synapse
block) is always generated straight from `synapses` config, the same way
`write_synapse_block` generates it for existing engrams. One source of truth; no
risk of a hand-written template drifting from what a rebuild would actually
produce.

**Placeholders:**

| Placeholder | Expands to |
|---|---|
| `%title%` | Title as typed at creation (not the slug) |
| `%date%` | Current date, per `engrams.date_format` |
| `%cursor%` | Where the cursor lands after the buffer opens (stripped from final content) |

Default `content_template`: `"# %title%\n\n%cursor%"` — heading, blank line,
cursor ready to write.

`create_engram` opens nothing — opening the buffer at the answered cursor is
`:MiaEngramCreate`'s, which is why the function answers where the cursor goes
rather than putting it there. The command opens it because you're starting
something to actively write; the CLI (§11) has no editor to open it in, and so
simply does not.

### 8.2 `append_to_engram(brain_name, engram_file, template_name, input?)`

Fast, no-buffer-switch capture into an **existing** engram's fenced section — for
adding a quick line to, say, a running `todo.md` without leaving what you're
doing.

```lua
append_templates = {
  todo = { section = "TASKS", render = "- [ ] %input%" },
  log  = { section = "LOG",   render = "- %date% — %input%" },
}
```

```
append_to_engram(brain_name, engram_file, template_name, input?):
  1. resolve brain + engram path
  2. template = append_templates[template_name]
  3. if input not provided → prompt (floating window, single line)
  4. line = render template with %input%, %date% substituted
  5. body = drafting.api.section.get(lines, template.section) or {}
     table.insert(body, line)
     lines = drafting.api.section.set(lines, template.section, body)
       - no such section → get answers nil, set writes one at the end of the file
  6. write file silently — no buffer opened, focus stays wherever the user was
  7. update atlas for that engram
```

The marker in a task template (`"- [ ] %input%"`) is part of the user's own
template string — memoria substitutes `%input%` and writes the line as given,
rather than reassembling the checkbox from a state. This is why the seam has no
`format_checkbox` (Part 2 §1).

Unlike `create_engram`, this never opens a buffer — the entire point is avoiding a
context switch. `template_name` is required (not picker-driven), so it's meant to
be bound directly per-template for speed, e.g. one key for "append a todo to
work/todo.md."

`append_to_engram`, the synapse block, the generated index and `md-drafting`'s TOC
generation share the same "read/replace within fixed markers" mechanism, and
share one implementation of it: `drafting.api.section` (Part 2 §2). Append is
not a separate operation there — it is the `get`/insert/`set` composition in
step 5 — and because both functions are pure over lines, this path rewrites a
file it never opened.

If the engram happens to be loaded in a buffer, writing the file underneath it
leaves the buffer stale (`W12`/`:checktime`). That case goes through the buffer
instead: same lines computed from `nvim_buf_get_lines`, written back with
memoria's minimal-span write (§1.1), buffer saved.

---

## 9. Navigation & index

### 9.1 Navigation history

A lightweight, in-memory back-navigation stack across engram jumps — inspired by
vimwiki's parent-link navigation, deliberately kept simple (no
branching/forward history, not persisted across restarts).

```
nav_history = []  -- stack of engram paths, in-memory only, cleared on restart

push_nav_history(engram_path):
  nav_history.push(engram_path)

go_back():
  if nav_history is empty: no-op (or notify "no history")
  previous = nav_history.pop()
  open(previous)
```

Every plugin action that navigates *to* an engram — following a synapse link,
following an inline link, opening from a picker or search result — calls
`push_nav_history(current_engram_path)` immediately before the jump. `go_back()` is
exposed as a plain function; no default binding, consistent with the rest of both
plugins' keybind stance.

Movement *within* an engram is not memoria's, and memoria adds nothing to it:
`md-drafting`'s jump navigation (Part 1 §8) already moves between links,
headings and tasks in the current buffer, and a synapse is a link, so
`md.jump.next(md.jump.TARGETS.LINK)` walks the `SYNAPSES` block along with the
rest of the document. `md-drafting`'s targets are a closed list (Part 1 §8), and
memoria registers none. Following a synapse is `go_back`'s counterpart, a
cross-engram move, which *is* memoria's.

### 9.2 Link-or-create at cursor

Word (or visual selection) under the cursor becomes a link — to an existing
engram/concept if one resolves, or to a newly-created engram if not. Reuses
`resolve_concept` (§6.3), engram lookup, and `create_engram` (§8.1); uses
`drafting.api.syntax.format_link` for the actual insertion syntax, same
shared-seam pattern as synapses.

```
link_or_create_at_cursor():
  1. text = word under cursor, or visual selection if active
  2. resolved = resolve_concept(text) or matching engram (by title/slug)
  3a. resolved →
        if concept: insert per configured concept-link syntax
        if engram, and cursor is already on an existing [text](path) link: follow it
                    (push_nav_history(current_engram_path) first)
        if engram, not yet a link: wrap text as drafting.api.syntax.format_link(text, path)
  3b. not resolved →
        prompt: "Create new engram '<text>'?"
        create_engram(current_brain, { title = text })
        wrap original text as a link to the new engram
```

Exposed as `link_or_create_at_cursor()` — no default binding.

The same two resolutions are also what memoria's **link providers** offer
inside `md-drafting`'s link generator (Part 1 §7.3): an "Engram" provider whose
`resolve` opens a picker over the atlas's engrams and answers
`done{ text = ctx.text or title, path = relative filename }`, and a "Concept"
provider whose `resolve` opens the pick-or-create concept picker (§4.1). Both
set `kinds = { "link" }` (Part 2 §3), since an engram or a concept is not
something `add_image` inserts as.

Consequences of how the implemented provider seam works (Part 2 §3):

- **`ctx.text` first.** `md-drafting` writes the provider's `text` as-is and
  never falls back to the selection, so a selected label survives only if the
  provider answers with it. The title is the fallback, not the override.
- **Registration is global, not per brain.** Registered once at memoria's
  setup, the providers are offered in *every* markdown buffer — `:MdAddLink`
  anywhere offers File or URL, Engram, Concept; `:MdAddImage` still offers only
  File or URL, so no provider menu for an image. `ctx` carries no buffer, so
  `resolve` reads the current buffer's path itself: inside a registered brain it
  uses that brain; outside one it falls back to the active brain (§2.2), and
  with none it notifies and answers `done(nil)`.
- **`path` is relative to the document, not the brain.** Within a flat brain
  (§2.3) that is the bare filename; from a document elsewhere it is the relative
  path to the brain's file, the same rule `File or URL` follows, so the link
  keeps working wherever the folder is opened from.
- **Order is the user's.** Providers follow registration order after
  `File or URL`; someone who mostly links engrams sets
  `link_providers.order = { "Engram" }` in `md-drafting`'s setup. memoria sets
  nothing there — it has no config surface on the other plugin (Part 1 §13).

Nothing is created inside the brain, so a flat brain (§2.3) stays flat.

### 9.3 Generated index

A regenerable, human-readable overview engram — plain markdown, so it's
trivially exportable to HTML or anything else via an external tool (e.g.
`pandoc`) with no export pipeline of memoria's own needed.

```lua
engrams = {
  ...
  index = {
    filename = "index.md",   -- lives at brain root
    sections = { "stats", "recent", "concepts", "roots", "not_done_tasks", "tasks" },
    stats = { "total_engrams", "total_concepts", "not_done_tasks" },   -- STATS block's
                                                                         -- own bullets, in order
  },
},
```

Two separate lists, because they answer two separate questions: `sections`
says which blocks appear in the file at all, `stats` says what shows up
*inside* the `STATS` block specifically. Dropping `"recent"` from `sections`
removes the whole `INDEX:RECENT` block; dropping `"not_done_tasks"` from `stats`
just removes that one bullet from `INDEX:STATS`, leaving `INDEX:NOT_DONE_TASKS`
(a different section, despite the shared name) untouched.

```
generate_index(brain_name):
  1. read atlas for the brain
  2. lines = existing index.md lines, or { "# <Brain name>", "" } for a new file
     for each name in config.sections, in order, build its body and
     lines = drafting.api.section.set(lines, "INDEX:" .. NAME, body)
     — a section not listed is left untouched if present, or simply never
     created. With no opts.at, a new section lands at the end of the file, so
     a first generation writes them in config order; later reorderings of
     config.sections do not move sections already in the file

       # <Brain name>

       <!-- INDEX:STATS -->
       - Engrams: 42            (one bullet per entry in config.stats, in order)
       - Concepts: 18
       - Open tasks: 5
       <!-- /INDEX:STATS -->

       <!-- INDEX:RECENT -->
       - [Project X](20260801_project-x.md) — modified 2026-08-01
       <!-- /INDEX:RECENT -->

       <!-- INDEX:CONCEPTS -->
       - **person**: Alice Smith, Pete Park
       - **tag**: java, proj/web
       <!-- /INDEX:CONCEPTS -->

       <!-- INDEX:ROOTS -->
       - [Project X](20260801_project-x.md)
       - [Reading list](java_optional-stream.md)
       <!-- /INDEX:ROOTS -->

       <!-- INDEX:NOT_DONE_TASKS -->
       - [ ] Call Alice about budget ([Project X](20260801_project-x.md))
       <!-- /INDEX:NOT_DONE_TASKS -->

       <!-- INDEX:TASKS -->
       - [ ] Call Alice about budget ([Project X](20260801_project-x.md))
       - [x] Send follow-up email ([Meeting notes](20260731_meeting-notes.md))
       <!-- /INDEX:TASKS -->

  3. write to <brain>/index.md (through the buffer, minimal-span, if it is open — §8.2)
```

`INDEX:NOT_DONE_TASKS` reads `atlas.tasks.not_done`; `INDEX:TASKS` reads
`atlas.tasks.not_done` and `atlas.tasks.done` together (§7.1) — no rebuild of their own, one
line per entry, linking back to the engram it came from. The `[ ]`/`[x]`
marker is written literally rather than through a formatter, the same way
`append_templates` strings already carry theirs (§8.2) — there is no
`format_checkbox` on the seam (§1.1) for either to call. This is the static,
regenerate-on-request counterpart to `:MiaAgenda` (§9.4): the same underlying
data, written to a file instead of opened as a live view.

`INDEX:ROOTS` lists every engram with an empty `up` field — found by one pass
over `atlas.engrams[*].synapses.up`, no separate index needed. It is the
closest thing a flat brain has to a table of contents: everything reachable by
following `down` from one of these.

The six sections (`INDEX:STATS`, `INDEX:RECENT`, `INDEX:CONCEPTS`,
`INDEX:ROOTS`, `INDEX:NOT_DONE_TASKS`, `INDEX:TASKS`) are `api.section` sections
like any other, so they follow the same fixed-marker, fully-regenerate pattern
as the synapse block and the TOC — safe to re-run any time, and content placed
*outside* them (e.g. a hand-written intro at the top of the file) survives
regeneration untouched. Separate sections rather than one, so a hand-written
note can sit between them.

`index.md` is otherwise a completely normal engram — flat in the brain root,
linkable, indexable — its content just happens to be plugin-generated on request
rather than hand-typed.

### 9.4 Agenda

A read-only, cross-engram list of open tasks — `:MiaAgenda`'s live counterpart
to `INDEX:NOT_DONE_TASKS`/`INDEX:TASKS` (§9.3), for sitting in and working through
rather than a one-shot snapshot written to disk.

```
:MiaAgenda        -- current brain
:MiaAgenda --all   -- every registered brain
```

A plain buffer in a split, not a floating view — an agenda is meant to sit
alongside the notes it points at, which is a different shape than the
single-document case `focused_view` (Part 1 §9.2) is for. `buftype=nofile`,
`readonly` and `modifiable=false`, `filetype=markdown` for free treesitter
highlighting, the same trick presentation mode uses.

```
agenda_open(opts?):
  1. brains = opts.all and every registered brain or just the current one
  2. for each brain: read atlas.tasks.not_done and atlas.tasks.done, group by engram
  3. state = { show_done = false, tasks = <everything loaded above> }
  4. render(state)
  5. open in split, apply buffer-local options and keymaps
```

```
render(state):
  1. tasks = state.show_done and (not_done ++ done) or not_done only
  2. group by engram, engrams ordered by most recently modified first
  3. write buffer, holding cursor position across a re-render;
     also build a line → {brain, engram_path, source_line} table, so cursor
     position maps back to a real task
```

```markdown
# Agenda — work

## Project X (20260801_project-x.md)
- [ ] Call Alice about budget

## Meeting notes (20260731_meeting-notes.md)
- [ ] Follow up on contract
```

Everything is loaded once, open and done alike; `show_done` only changes what
`render` filters to, so toggling it is a re-render, not a reload.

**Keymaps**, buffer-local to the agenda — a second exception to "no
plugin-owned keybinds," scoped the same way as presentation mode's: only
inside a view the plugin itself creates.

```
t    toggle_task_under_cursor()
<CR> jump_to_source()
za   toggle state.show_done; render()
q    close the buffer
```

```
toggle_task_under_cursor():
  1. look up {brain, engram_path, source_line} for the cursor's line
  2. read the line at source_line from the engram file:
       prefix, marker, text = drafting.api.syntax.parse_list_item(line)
       state = drafting.api.syntax.marker_state(marker, engrams.task_markers)
       not a task (state nil) or line no longer matches the atlas → notify, rebuild that engram, stop
       new_marker = state == "not_done" and task_markers.done[1] or task_markers.not_done[1]
       line = drafting.api.syntax.format_list_item(prefix, new_marker, text)
  3. write it back, save — no buffer opened, same pattern as append_to_engram (§8.2),
     including going through the buffer when the engram is loaded in one
  4. update the atlas for that one engram (incremental, not a full rebuild)
  5. render(state)

jump_to_source():
  1. push_nav_history(current) (§9.1)
  2. open the engram at source_line, in the window the agenda was opened from
```

The toggle is memoria's own flip between two states, driven by
`engrams.task_markers` and operating on a file rather than the cursor line, so a
task always stays a task. It is built from the seam's `parse_list_item`,
`marker_state` and `format_list_item`.

Always opens open-only (`show_done = false`), every time — not a persisted
preference, so the default stays the default across sessions. `za` mirrors
Neovim's own fold-reveal key, since there is no fold interaction inside this
buffer to conflict with.

### 9.5 Diary / quick-open

Two related but distinct conveniences — worth keeping separate rather than
merging, since they answer different questions ("what's today's entry" vs. "what
did I touch most recently").

**`open_or_create_today(brain_name)`** — opens today's dated entry, creating it if it
doesn't exist yet. A "diary" is just a brain used this way consistently; no
separate diary concept needed, since date-prefixed filenames already exist for
exactly this.

```
open_or_create_today(brain_name):
  1. resolve brain config
  2. expected_filename = today's date (per engrams.date_format) + separator + "diary"
       (or whatever slug convention the brain uses — same filename machinery as §4)
  3. if a file matching expected_filename exists → open it, push_nav_history(previous)
  4. else → create_engram(brain_name, { title = "diary" })
       -- same creation flow as any new engram: normal content_template,
          synapse scaffolding, filename rules, opens the buffer
```

**`open_last_edited(brain_name)`** — opens whatever engram in the brain was most
recently modified, purely informational, never creates anything.

```
open_last_edited(brain_name):
  1. read atlas.engrams for the brain
  2. find the entry with max(modified)
  3. open it, push_nav_history(previous)
```

These can diverge in practice — e.g. yesterday's most-recently-touched engram
might be an old project note, with no diary entry created yet for today — so
`open_or_create_today` and `open_last_edited` are kept as two separate functions
rather than one with a mode flag.

### 9.6 Engram search

Fuzzy match over an engram's title, filename, tags and participants, read
from the atlas — no prose/body search, since nothing in the atlas holds
engram bodies, and that is a different kind of feature.

```
search_engrams(brain_name, query?, opts?):   -- opts = { fields? }
                                              -- → { path, title, score }[] | nil, err
  1. resolve brain config
  2. query = opts given one, or prompt "(brain_name) Search:"
  3. candidates = atlas.engrams for brain_name, refreshed (§7.1)
  4. score each candidate's title, filename, tags and participants against
     query (opts.fields narrows which of these are matched; default: all)
  5. return candidates sorted by score, best first
```

`:MiaEngramSearch [brain] [query]` resolves the brain through §2.2's
`resolve()`, the same as every other brain-scoped command; prompts for
`query` only when not given, step 2's own fallback; and opens a picker over
the results, `push_nav_history` (§9.1) before opening whichever one is chosen.

`bin/mia search --query Q [--brain B]` (§11.3) calls the same function with
both arguments given, so step 2 never prompts — the headless case, same as
every other CLI command.

The CLI's `engrams [--concept C]` (§11.3) is the exact-match, concept-only
case of what this searches more generally; the two share the atlas read but
answer different questions.

---

## 10. Renaming and deleting engrams

Filenames are treated as immutable identity by default (§4) — these are the
explicit, deliberate exceptions to that rule, not casual operations.

### 10.1 `rename_engram(brain_name, engram_path, new_title?)`

```
rename_engram(brain_name, engram_path, new_title?):
  1. resolve brain config
  2. if new_title not given → prompt for it
  3. compute new filename: same prefix mode as the original (date/concept/none),
     new slug derived from new_title
  4. collision check against existing filenames → same "prompt to edit name" rule as creation (§4)
  5. rename the file on disk
  6. scan atlas for every engram whose synapses reference the old path →
       write_synapse_block(its_lines, ...) with the path updated to the new filename
  7. best-effort scan of raw engram content, brain-wide, for the old path string
     appearing in inline markdown links → replace with the new path
       (this is the one place inline links ARE touched — a rename is a structural
       change to the filesystem, not a content edit, so it's treated differently
       from the "inline links are never materialized" rule for synapses)
  8. update atlas: move the entry to the new key, update backlinks map accordingly
```

Step 7 is a known limitation, not a guarantee: brain-wide raw-text scanning
catches links written the normal way (`api.syntax.format_link` output), but won't
catch a manually hand-typed or unusually-formatted link. `rebuild_atlas`'s
broken-link check (§7.2) is the safety net for anything this step misses.

### 10.2 `delete_engram(brain_name, engram_path, opts?)`

```
delete_engram(brain_name, engram_path, opts?):
  1. look up atlas entry for engram_path — its synapses and backlinks
  2. referencing = other engrams whose synapses point here, or that inline-link here
  3. if referencing is non-empty and not opts.force:
       prompt for confirmation, showing the count/list of referencing engrams
  4. for each referencing engram with a synapse field pointing to engram_path:
       remove that value from the field, write_synapse_block to persist
  5. delete the file from disk
  6. remove the entry from the atlas; drop it from any backlinks/concepts lists it appeared in
```

Structural synapse references are actively cleaned up (step 4), matching how
`attach_synapse` keeps both sides in sync — deleting should undo that sync, not leave
a dangling reference. Inline body-text links to the deleted engram are **not**
rewritten (consistent with inline links never being materialized elsewhere in
this design) — they'll surface as broken links on the next `rebuild_atlas`, same
as any other stale inline reference.

---

## 11. The CLI

`bin/mia` is memoria with no editor running: the same functions the commands
call, from a shell. A script, a git hook, another editor, an AI agent — anything
that can run a command and read JSON.

A brain is readable without memoria, being markdown and JSON. What is not
writable without it is a correct one: a hand-written engram misses the generated
header (§8.1), a hand-added synapse misses its inverse (§5.6), and neither
reaches the atlas until something refreshes it. That is what the CLI is for.

### 11.1 Invocation and config

```
bin/mia <command> [--brain <name>] [args]
bin/mia [command] --help
```

`bin/mia` is a Lua script run by `nvim -l` (its shebang). `-l` skips the user's
config, and with it the `setup({})` tier (§3) — an engram written without that
tier would have the built-in synapse fields and template, not the user's. So
the script loads the config itself:

```
1. prepend its own lua/ to package.path, and require it     -- one memoria:
   this checkout's
2. print / vim.notify → stderr, for the whole run, so stdout stays JSON
3. source $MEMORIA_INIT, else stdpath("config")/init.lua; "NONE" skips it
4. a config was sourced but setup() has not run → error, naming the likely
   cause (memoria lazy-loaded on a command or key, md-drafting missing);
   NONE → setup({}) here
5. run the command
```

Step 1 requires memoria as well as putting it on the path, because the
runtimepath searcher (`vim._load_package`) outranks the `package.path` one: a
copy installed by a plugin manager would otherwise answer the `require` inside
the user's config. `package.loaded` outranks both.

Step 4 refuses rather than falling back to the built-in defaults, since that
fallback is exactly the engram in the wrong shape. It is decided by a flag
`setup()` sets last, so a `setup()` that stopped on the missing dependency
(§1.2) fails here too, naming it. `MEMORIA_INIT=NONE` is the deliberate way to
skip the config — for tests, and for a machine with no config worth loading —
and the brain's `.mia_dna.json` still applies on top. Note that `nvim -l` loads
no packages, so under `NONE` md-drafting has to be on `package.path` already.

The stderr redirect in step 2 covers the whole run, not just the sourcing:
`nvim -l` runs verbose, so `print` and `:echo` go to stdout by default, and a
diagnostic memoria itself notifies (an unreadable registry, an invalid
`.mia_dna.json`) has to land beside the config's own output rather than in the
result.

### 11.2 Output

One JSON object on stdout, exit status to match:

```json
{ "ok": true, "result": { "path": "/home/me/notes/work/20260801_project-x.md" } }
{ "ok": false, "error": "(work) engram 20260801_project-x.md already exists" }
```

`0` for `ok`, `1` otherwise. Errors are the `err` the function answered
(the headless core, top of Part 3), prefixed with the brain the same way prompts are
(§2.2).

`--help` is the one run that prints something else: the usage lines as plain
text, exit `0`. It is read by a person rather than parsed, which is also why it
loads no config (§11.1) — being told how to call something has to work when
nothing else does. `--help` after a command narrows it to that command and what
each of its arguments is for; `commands` is the same surface as JSON, for
whatever does parse it.

### 11.3 Commands

Brain-scoped commands take `--brain`, resolved as in §2.2's headless case: the
named brain, or the only one registered.

| Command | Calls | Result |
|---|---|---|
| `brains` | the registry (§2.1) | name, location, whether it exists |
| `engrams [--concept C]` | the atlas, refreshed (§7.1) | per engram: filename, title, concept fields, `modified`; only those referencing `C` when given |
| `search --query Q [--fields F]` | `search_engrams` (§9.6) | matching engrams, best first, each with its score |
| `engram <file>` | the atlas + the file | its atlas entry, its backlinks, its content |
| `tasks [--state not_done\|done]` | the atlas's `tasks` | the bucket, or both |
| `check` | `rebuild_atlas` (§7.2) | the problems, each with file, line and kind |
| `rebuild [--fix]` | `rebuild_atlas`, `opts.fix` with `--fix` | the problems left after it |
| `create-engram --title T [--field k=v,…] [--body -] [--concept C]` | `create_engram` (§8.1), which opens nothing | the new engram's path |
| `attach-synapse <source> <field> <target>` | `attach_synapse` (§5.6) | the brain, source, field and target it linked |
| `concepts [--type T] [--undeclared]` | the registry + the atlas (§6, §7.1) | per concept: name, type, aliases, note, meta, the engrams naming it; with `--undeclared`, `find_undeclared_concepts` instead |
| `create-concept --name N --type T [--meta k=v]` | `create_concept` (§6.4) | the concept registered; a name already registered is an error |
| `edit-concept --name N [--type T] [--meta k=v]` | `set_concept_meta` (§6.4) | the concept as written; `--meta k=` removes a key, a name not registered is an error |
| `attach-concept <source> <field> <concept>` | `attach_concept` (§6.4) | the brain, source, field and the name it wrote |
| `commands` | `cli.lua`'s own table | every command with its arguments, as a schema |

`--field tags=java,streams` fills `opts.fields`, once per field. `--body -` reads
the body from stdin, so multi-line prose needs no shell quoting; `--body <text>`
takes the text as given. `attach-synapse` takes `--brain` like the rest, since
there is no current buffer to take it from, and its `source` and `target` are
filenames in that brain. `--meta` on `create-concept` splits at the first `=` like
`--field`, but is not comma-split: a meta value is one string. `create-concept` is
adding in the same sense as `attach-synapse` — one entry in one file, touching no
engram — and without it `create-engram --concept` could not be used headless for
a concept nobody had registered in the editor. `check` is `rebuild` without `--fix`: both rewrite the
derived atlas, neither touches an engram.

The command table is a **list**, not a map. `commands` prints it, and a Lua map
has no order — the same reason `field_names` and the brain registry sort. It is
also what `--help` (§11.2) reads, so the two cannot disagree about what exists.

The surface is **reading and adding**. `rename_engram` and `delete_engram`
(§10) are not on it: both rewrite or remove files beyond the one named — a
brain-wide inline-link rewrite, a delete that cascades into every synapse
pointing at it — which is a change for someone to confirm, not for something
running unattended to do unasked.

Every later feature the CLI can carry gets its command in the same change that
adds the feature — `concepts` and `create-concept` came with the registry (§6),
`append` comes with `append_to_engram` (§8.2) — and nothing else changes: the
command table is the one list, and `commands` reads it.

### 11.4 Running beside the editor

The CLI writes to disk, never to a buffer — it has none. An engram open in a
running Neovim is reloaded by `:checktime`/`autoread` when unmodified; with
unsaved changes it gets `W12`, and the user decides which side wins. memoria's
own reads already `:checktime` first (§1.1), so the editor never writes a CLI
change back over itself.

The atlas refreshes on read (§7.1), which is what makes this safe: whichever
side reads next picks up what the other wrote. Two processes writing
`.mia_atlas.json` at once leave the later write, which is fine for a file that
is derived and rebuildable by definition.

---

## 12. Decisions

- **Filename collision** (same prefix + slug already exists): prompt the user to
  edit the title rather than auto-appending a suffix. Keeps naming fully
  user-controlled: the slug is derived from the title, never invented.
- **No wizard for `.mia_dna.json`**: `:MiaBrainConfig` (§2.2) creates the file
  empty and opens it, and the file is hand-edited from there. A guided
  question-per-setting flow would have to be rewritten every time the config
  surface grows, and reads badly for `synapses`, which is a map of tables
  rather than a list of scalars.
- **Synapse block fence markers** (`<!-- SYNAPSES -->` / `<!-- /SYNAPSES -->`):
  fixed plugin constants, not configurable.
- **Engram header is laid out for vertical space** (§5.1): flow-style
  frontmatter lists, synapse fields as a tight markdown list (rendered line
  breaks without hard-break syntax), a `***` separator inside the section, one
  blank line before the prose, written only when there is a header. Kept at the
  top, next to the frontmatter.
- **Concept-prefix filenames**: chosen concept is always also written to the
  engram's tags/concept fields — never purely cosmetic, to avoid a
  searchable/visible mismatch.
- **Tasks stay metadata-free**: no due dates or priority in task lines, to keep
  them standard GitHub-flavored checkboxes, readable anywhere. Which markers get
  *indexed* is configurable (`engrams.task_markers`, §3) so an existing brain's
  convention is not silently ignored; what memoria writes stays GFM.
- **Task states are `not_done`/`done` everywhere** — config keys, atlas buckets,
  index section and stat names — because they are `md-drafting`'s state names
  (`TASK_STATES`, `NOT_DONE_TASK`) and `task_markers` is passed through to
  `parse_checkbox` untranslated (§7.1).
- **The section seam is `get`/`set`, nothing more** (Part 2 §2) — append is
  memoria's composition of the two, first-write placement is memoria's
  `opts.at`, and writing into a loaded buffer is memoria's minimal-span helper
  (§1.1). None of those are asked of `md-drafting`.
- **`:MiaEngramCreate` opens the buffer; `append_to_engram` never does** —
  deliberately asymmetric, matching their different purposes (start writing vs.
  quick capture without interrupting current work). Both functions themselves
  stay headless (§1.3): the asymmetry is in what the commands do with them.
- **`md-drafting.nvim` is a hard dependency**, not optional — memoria's
  link/checkbox handling relies on it directly rather than duplicating syntax
  logic.
- **Navigation history is in-memory only, no persistence, no forward/branching**
  — deliberately simple, matching vimwiki's plain back-navigation rather than a
  full browser-style history.
- **In-buffer motion is `md-drafting`'s, cross-engram navigation is memoria's** —
  memoria writes no next/previous motion and registers no jump target (§9.1). A
  synapse is a link, so `md.jump.next(md.jump.TARGETS.LINK)` already covers it,
  and `md-drafting`'s target list is closed (Part 1 §8).
- **Link providers are global, not brain-scoped** — `md-drafting` has no
  per-buffer registration and passes no buffer in `ctx`, so Engram and Concept
  are offered in every markdown buffer and work out the brain from the current
  file themselves (§9.2).
- **`open_or_create_today` and `open_last_edited` stay separate functions** — "today's
  entry" and "most recently touched engram" can genuinely diverge, so merging
  them into one mode-flagged function would misrepresent what each guarantees.
- **Rename touches inline links (best-effort); delete does not** — a rename is a
  filesystem-identity change and needs its links repaired to stay correct; a
  delete's dangling inline references are left for `rebuild_atlas` to report,
  consistent with inline links never being plugin-materialized elsewhere.
- **Presentation mode is not memoria's** — it lives in `md-drafting.nvim` (Part 1
  §10) and memoria depends on it. Memoria owns no presentation-mode code or
  commands of its own.
- **Outside callers get a CLI, not RPC into a running Neovim** (§11) — it works
  with no editor open, and ties no caller to a session or its buffers. The files
  and the refresh-on-read atlas are the only shared state, and both already
  tolerate writes from outside.
- **The CLI loads the user's config** (§11.1) — an engram written from a shell
  has the same header and template as one written in the editor, or the CLI
  refuses.
- **A registry edit re-derives, a config edit re-parses** (§7.1) — two
  fingerprints, because only one of them changes how an engram is read.
- **Concepts are reported only once something is declared** (§7.2) — an empty
  registry is not a brain full of mistakes.
- **`create_concept` refuses a duplicate; `set_concept_meta` merges** (§6.4) —
  registering and editing stay two verbs, so neither command nor CLI silently
  merges into a concept someone else wrote. The CLI mirrors it: `create-concept`
  refuses a name taken, `edit-concept` refuses one not registered, so a typo
  in either is an error rather than a wrong concept.
- **One meaning per verb** (§1) — `Add` used to mean record, make and relate
  at once; Register, Create and Attach each mean one of them, with an inverse.
  A command is named for what it does to its noun, not for the noun alone.
- **Attach, not Link** — "link" already means a markdown `[text](path)`: the
  link providers and link-or-create (§9.2) insert one. Attach says the relation
  lives on the engram, and has Detach as its inverse.
- **The CLI reads and adds, never renames or deletes** (§11.3) — those two
  reach beyond the file named, and stay behind a person in the editor.
- **The CLI's command table is an ordered list** (§11.3) — `commands` is how an
  caller discovers the surface, and a list is the only way that answer is the
  same twice. The MCP server in Open items generates its tools from the same
  table, so the order is the schema's too.
- **The agenda is a plain buffer, not a `focused_view`** — it's meant to sit
  alongside the notes it points at rather than take over the screen, which is
  the opposite of what the primitive (Part 1 §9.2) is for.
- **`:MiaAgenda` always opens open-only** — not a persisted preference, so the
  default stays the default across sessions; `za` reveals done tasks for that
  buffer only.
