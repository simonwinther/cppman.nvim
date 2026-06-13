# CPPMan.nvim

> [!CAUTION]
> This README documents the current development version on `main`.
> For the latest stable release, see the [latest release](../../releases/latest).

<p align="center">
  <img src="assets/demo.gif" alt="CPPMan.nvim demo" width="800">
  <br>
  <em>(Demo recorded in version v0.0.4)</em>
</p>

A small Neovim plugin for the [cppman CLI](https://github.com/aitjcize/cppman).

It lets you search C++ docs from inside Neovim and opens the result in a
floating viewer. Search reads cppman's local SQLite index, so the picker does
not need to call the `cppman` command for every query.

## Requirements

* Neovim 0.10+
* [cppman](https://github.com/aitjcize/cppman)
* `sqlite3`
* One picker backend:

  * [ibhagwan/fzf-lua](https://github.com/ibhagwan/fzf-lua) and the `fzf` binary
  * [folke/snacks.nvim](https://github.com/folke/snacks.nvim)

Install the external tools however you normally do:

```sh
brew install cppman sqlite fzf
# or
sudo apt install cppman sqlite3 fzf
```

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim), using `fzf-lua`:

```lua
return {
  "simonwinther/cppman.nvim",
  version = "*",
  cmd = "CPPMan",
  dependencies = {
    "ibhagwan/fzf-lua",
  },
  opts = {
    picker = {
      provider = "fzf-lua",
    },
  },
  -- Buffer-local maps in C/C++ files only, so they don't show up in other
  -- filetypes. The require() calls load the plugin on first use.
  init = function()
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "cpp", "c" },
      callback = function(args)
        vim.keymap.set("n", "<leader>cu", function()
          require("cppman").open_for(vim.fn.expand("<cword>"))
        end, { buffer = args.buf, desc = "[C++] open under cursor" })

        vim.keymap.set("n", "<leader>ck", function()
          require("cppman").search()
        end, { buffer = args.buf, desc = "[C++] keyword search" })
      end,
    })
  end,
}
```

If you already use `snacks.nvim`, use that instead:

```lua
return {
  "simonwinther/cppman.nvim",
  version = "*",
  cmd = "CPPMan",
  dependencies = {
    "folke/snacks.nvim",
  },
  opts = {
    picker = {
      provider = "snacks",
    },
  },
}
```

You can also leave the provider as `"auto"`. It tries `snacks.nvim` first, then
`fzf-lua`.

## Usage

Open the search picker:

```vim
:CPPMan
```

Open a page directly:

```vim
:CPPMan std::vector
```

From Lua:

```lua
require("cppman").search()
require("cppman").open_for(vim.fn.expand("<cword>"))
```

## Moving Around

The docs viewer is just a normal Neovim buffer in a float. Regular movement
still works: `j`, `k`, `<C-d>`, `<C-u>`, `/`, `n`, and so on.

cppman.nvim adds a few mappings on top:

* `K`, `<C-]>`, or double-click: follow the word under the cursor
* `K` on a table-of-contents entry: jump to that section
* `<C-T>` or right-click: go back to the previous cppman page/search
* `<Tab>`: go forward again after going back
* `<M-m>`: toggle between the configured size and a maximized view
* `q`: close the viewer

Visual mode works too:

* Select text, then press `K` or `<C-]>` to open docs for the selection

## Configuration

Defaults:

```lua
require("cppman").setup({
  -- "both", "cppreference.com", or "cplusplus.com"
  source = "both",

  index = {
    -- Set this if cppman's index.db is somewhere unusual.
    -- If nil, cppman.nvim tries to find a usable one.
    db_path = nil,
  },

  picker = {
    -- "auto", "fzf-lua", or "snacks"
    provider = "auto",

    width = 0.4,
    height = 0.4,

    -- Passed through to the picker backend.
    snacks = {},
    fzf_lua = {},
  },

  viewer = {
    width = 0.8,
    height = 0.6,
  },
})
```

Example with a slightly larger `fzf-lua` picker:

```lua
require("cppman").setup({
  picker = {
    provider = "fzf-lua",
    width = 0.5,
    height = 0.5,
  },
})
```

If you only want one docs source:

```lua
require("cppman").setup({
  source = "cppreference.com",
})
```

## How Search Works

`cppman.nvim` reads cppman's local `index.db` with `sqlite3` and keeps the
keyword list in memory for the current Neovim session.

The `cppman` command itself is only used when opening a documentation page.

When `source = "both"`, results from cppreference and cplusplus are merged.
Duplicate exact matches are removed where possible, and the picker shows a small
source label so you know where the page will open from.

If your local `~/.cache/cppman/index.db` is empty or broken, the plugin tries to
use the packaged `index.db` from the cppman Python package instead.

## Page Rendering

If cppman already has the `.3.gz` page cached, `cppman.nvim` renders that file
through cppman's pager script. If not, it falls back to normal cppman behavior.

Rendered pages are also cached in memory for the current Neovim session.

## Health Check

Run:

```vim
:checkhealth cppman
```

It checks Neovim, `cppman`, `sqlite3`, your picker backend, and the resolved
`index.db`.

## Repo Analytics

![Alt](https://repobeats.axiom.co/api/embed/5df93c3d0004a00ff8f890d50b098386ed326e26.svg "Repobeats analytics image")
