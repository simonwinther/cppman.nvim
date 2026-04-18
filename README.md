# CPPMan.nvim

![CPPMan.nvim demo](assets/demo.gif)

A Neovim plugin for the [cppman CLI](https://github.com/aitjcize/cppman), so you can search cplusplus.com and cppreference.com without leaving Neovim.

This plugin started as a copy of [madskjeldgaard/cppman.nvim](https://github.com/madskjeldgaard/cppman.nvim), with full credit to Mads for the original work.

I built this version from his repo because it had not been updated for nine months, some parts were a bit outdated, and I wanted it to work well with [lazy.nvim](https://github.com/folke/lazy.nvim), so I decided to remake it based on his plugin.

## Installation

Install with [lazy.nvim](https://github.com/folke/lazy.nvim). [nui.nvim](https://github.com/MunifTanjim/nui.nvim) is required.

Use `version = "*"` to follow the latest stable release.

```lua
{
	"simonwinther/cppman.nvim",
	version = "*",
	event = "VeryLazy",
	dependencies = {
		"MunifTanjim/nui.nvim",
	},
	opts = {
		input_width = 30,
		popup_width = "90%",
		popup_height = "80%",
	},
}
```

## Usage

Run `:CPPMan` to open the search prompt, or pass a term directly: `:CPPMan std::array`

The default keymaps are the following:
* `<leader>cu` opens CPPMan for the word under the cursor
* `<leader>ck` opens the CPPMan search prompt

If you want to override the default keymaps in `opts`, you can do it like this:

```lua
{
	"simonwinther/cppman.nvim",
	version = "*",
	event = "VeryLazy",
	dependencies = {
		"MunifTanjim/nui.nvim",
	},
	opts = {
		keymaps = {
			open_under_cursor = "<leader>mu",
			search = "<leader>mk",
		},
	},
}
```
And if you want to set up the plugin manually, you can do it like this:

```lua
require("cppman").setup({
	input_width = 20,
	popup_width = "80%",
	popup_height = "60%",
	keymaps = {
		open_under_cursor = "<leader>cu",
		search = "<leader>ck",
	},
})
```

## Navigation
In normal mode, the manual uses the same navigation as standalone `cppman`:

* **K**, **<C-]>**, and **<2-LeftMouse>** follow the word under the cursor
* **\<C-T\>** and **\<RightMouse\>** go back to the previous page

In visual mode inside the popup:

* **K** and **<C-]>** follow the selected text
