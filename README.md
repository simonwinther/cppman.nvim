# CPPMan.nvim

<p align="center">
  <img src="assets/demo.gif" alt="CPPMan.nvim demo" width="800">
  <br>
  <em>(Demo recorded in version v0.0.4)</em>
</p>

A Neovim plugin for the [cppman CLI](https://github.com/aitjcize/cppman), so you can search cplusplus.com and cppreference.com without leaving Neovim.

## Requirements

- Neovim 0.10+ (uses `vim.keycode`, `vim.system`, `vim.uv`)
- [cppman](https://github.com/aitjcize/cppman) - for rendering documentation pages
- `sqlite3` CLI - for querying the keyword index (`apt install sqlite3`, `brew install sqlite`)
- [folke/snacks.nvim](https://github.com/folke/snacks.nvim) - for the fuzzy picker UI

## Installation

Install with [lazy.nvim](https://github.com/folke/lazy.nvim).

Use `version = "*"` to follow the latest stable release.

```lua
{
  "simonwinther/cppman.nvim",
  version = "*",
  event = "VeryLazy",
  dependencies = {
    "folke/snacks.nvim",
  },
  opts = {},
}
```

## Usage

Run `:CPPMan` to open the keyword search picker, or pass a term directly: `:CPPMan std::array`

The default keymaps are:
* `<leader>cu` - open CPPMan for the word under the cursor
* `<leader>ck` - open the CPPMan search picker

## Configuration

All options with their defaults:

```lua
require("cppman").setup({
  keymaps = {
    open_under_cursor = "<leader>cu",
    search = "<leader>ck",
  },
  -- Documentation source: "both", "cppreference.com", or "cplusplus.com"
  source = "both",
  index = {
    -- Explicit path to cppman's index.db (optional override)
    -- If nil, the plugin auto-discovers a valid DB
    db_path = nil,
  },
  picker = {
    width = 0.4,   -- fraction of editor width
    height = 0.4,  -- fraction of editor height
  },
  viewer = {
    width = 0.8,   -- fraction of editor width
    height = 0.6,  -- fraction of editor height
  },
})
```

### Overriding keymaps

```lua
{
  "simonwinther/cppman.nvim",
  version = "*",
  event = "VeryLazy",
  dependencies = { "folke/snacks.nvim" },
  opts = {
    keymaps = {
      open_under_cursor = "<leader>mu",
      search = "<leader>mk",
    },
  },
}
```

## How it works

Search is powered by a local SQLite index that ships with cppman. The plugin queries it once per session via `sqlite3` and passes the keyword list to `snacks.picker` for fast in-memory fuzzy matching. The `cppman` CLI is only used to render documentation pages, not to search.

If `source = "both"`, the plugin merges cppreference and cplusplus results into one in-memory picker list. Exact identical matches are deduplicated, and the picker shows a small source badge so you can see which site a result will open from.

If you prefer one site only, set `source = "cppreference.com"` or `source = "cplusplus.com"`.

If the user's local `~/.cache/cppman/index.db` is empty or corrupt (which can happen when `cppman -r` fails due to missing Python dependencies), the plugin falls back to the packaged index.db bundled with the cppman Python package.

## Performance

Search is fast because the plugin loads cppman's SQLite index once and keeps the results in memory for picker matching. In `source = "both"` mode, the merged cross-source list is also built once per session and then reused.

Documentation rendering is optimized for cached pages. If a man page already exists in cppman's `.3.gz` cache, the plugin renders that file directly through cppman's pager script instead of starting the full `cppman` CLI search path again. That avoids most of the Python startup and lookup overhead while keeping the same rendered output. If the page is not cached yet, the plugin falls back to normal `cppman` behavior.

Rendered pages are also cached in memory for the current Neovim session, so reopening the same page at the same width is effectively instant.

## Navigation

In normal mode, the docs viewer uses the same navigation as standalone `cppman`:

* **K**, **\<C-]\>**, **\<2-LeftMouse\>** - follow the word under the cursor (when the cursor is on a TOC entry, jumps to that section instead)
* **\<C-T\>**, **\<RightMouse\>** - go back to the previous page (cursor position is restored)
* **\<Tab\>** - go forward (undo a back navigation; cursor position is restored)
* **q** - close the viewer

In visual mode inside the viewer:

* **K**, **\<C-]\>** - follow the selected text

## Health check

Run `:checkhealth cppman` to verify that `cppman`, `sqlite3`, `snacks.nvim`, and a valid `index.db` are all present.
