# TUI ideas

Notes from a discussion, nothing decided. To be picked up later.

## The problem

While reading notes in memoria-viewer, the user sees something to edit and
wants to get to that engram in an editor quickly.

A Claude Code plugin cannot do this itself: its processes (`$.process.run`,
`$.process.spawn`) get pipes and no terminal, so a terminal `$EDITOR` cannot
take over the screen. A GUI editor would work; reaching a running Neovim
would need `$NVIM`, a known socket or tmux, none of which should be required.

What the viewer does today: `y` in the engram view copies the engram's path.

## The goal

View engrams in a simple view, like the one memoria-viewer has, without
having to open Neovim or Claude Code. Lives in this repo, since the CLI and
everything it needs are here. Running inside Neovim's `:terminal` does not
matter: inside Neovim, Neovim itself is the tool.

## Options

### A. Go TUI over `bin/mia`

bubbletea + glamour + lipgloss; a binary that calls `mia` and reads its JSON.

- Rendered markdown from glamour, close to the pane's look.
- `e` suspends, runs `$EDITOR <path>`, resumes.
- Own keys, row scrolling included.
- No Lua changes: the CLI's JSON is the whole interface, as for the viewer
  (ARCHITECTURE §11.5).
- Cost: a whole new app (pickers, views, the summary), a third language in
  the repo, and an install story — `build = "make tui"` (needs Go) or
  release binaries.
- One `mia` process per read: check the latency early. A long-lived
  `mia serve` (see the MCP server open item) would solve it.

### B. Lua TUI library

`lcurses`/`luaposix`, `ltui`, `lua-term`/`plterm`, termbox bindings.

- All the capable ones are C modules: luarocks and a compiler, and nothing
  `nvim -l` loads without a build step. The helpers that are pure Lua have
  no layout or input model.
- None renders markdown.
- Not worth it: the reason to pick Lua was having no toolchain.

### C. The viewer inside Neovim (`:MiaView`, `mia view`)

Neovim draws the view; a `mia view [brain] [engram]` launcher starts `nvim`
straight into it and `q` quits the process, so it feels like its own tool.
One implementation behind both the command and the shell.

| The pane has | In Neovim | |
|---|---|---|
| Rounded, colored boxes | Floating windows, `border = "rounded"`, a `FloatBorder` highlight per box | Same look |
| Colors | Highlight groups and extmarks | Same; the colorscheme's or own `Memoria*` groups |
| Hotkey buttons | Buffer-local keymaps, hints as virtual text | Same, drawn by hand |
| Dividers, wrapping rows | Lines written into a scratch buffer | Width math by hand |
| Rendered markdown | Treesitter with `conceallevel=2`; `render-markdown.nvim` or `markview.nvim` when installed | Decent alone; with a render plugin, as good or better |
| Scrolling | Native: `j`/`k`, search, `gg`/`G` | Better |

A possible layout:

```
tab
├─ float: navigation   (← → brain engram summary reload close, synapses)
├─ float: frontmatter and tasks
└─ window: the engram's buffer, rendered
```

- The body can be the engram's real buffer, so editing is pressing `i` —
  the problem above disappears.
- The model is in-process: no `mia` processes, no JSON, no port of the
  viewer's `summary.ts`.
- The pickers in `ui/` already exist.
- No new language or toolchain.
- Cost: no layout engine — floats are placed by hand, and resizing
  (`VimResized`) is own code; rich markdown leans on an optional third-party
  plugin; it is still a Neovim process.

### D. Go TUI inside a Neovim float

A's binary run in a `:terminal` float, `e` opening the file in the host
Neovim through `$NVIM`. Both renderings, both codebases. Only mentioned.

## Leaning

C over A: it solves editing outright and reuses what is here. A if the
rendered look and a tool truly apart from Neovim weigh more.

## Related

- **Chain summary in the CLI.** A `mia chain <file>` answering what
  `summary.ts` computes today (the engrams reachable by synapses, their
  dates, tasks and concept fields), so no client computes it. Worth doing
  for the viewer alone; needed by A, unnecessary for C.
- **memoria-viewer's scope.** Its own strength is reading beside a
  conversation: `show_engram`, the changed-engram hint, the summary next to
  the chat. Browsing and editing by hand is where it meets the engine's
  limits.

## Open questions

1. C, and drop the Go idea? Or A?
2. Markdown in C: an optional `render-markdown.nvim` integration with a
   treesitter fallback? Does `md-drafting.nvim` already render something to
   reuse?
3. The body in C: the real file (editable, `i` works) or a read-only copy
   with `e` to open the real one?
4. For A: scope of a first version (pickers, engram view, `e`; summary and
   concept click later?), and `make tui` or release binaries?
5. Rewrite the "Standalone TUI" open item in `MEMORIA_PLAN.md` once this is
   settled.
