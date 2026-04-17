# CPPMan.nvim

![in action](cppman.gif)

A NeoVim plugin with a simple interface for the [cppman cli tool](https://github.com/aitjcize/cppman), allowing you to easily search cplusplus.com and cppreference.com without ever leaving neovim.

Plugin inspired by [vim-cppman](https://github.com/gauteh/vim-cppman)

This plugin started as a copy of [madskjeldgaard/cppman.nvim](https://github.com/madskjeldgaard/cppman.nvim), with full credit to Mads for the original work.

That repo had not been updated for around 9 months when I picked this up, so I added sizing options and a few other workflow improvements for my own use.

## Installation

Install using [lazy.nvim](https://github.com/folke/lazy.nvim). Note that [nui.nvim](https://github.com/MunifTanjim/nui.nvim) is a requirement.

```lua
{
	"simonwinther/cppman.nvim",
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

Run `:CPPMan` without any arguments to get a search prompt or with an argument to search for a term: `:CPPMan std::array`

Using `event = "VeryLazy"` is enough here. You do not need a separate `keys` entry in your `lazy.nvim` spec unless you want to manage the mappings yourself.

Default keymaps:

* `<leader>cu` opens CPPMan for the word under the cursor
* `<leader>ck` opens the CPPMan search prompt

You can override the default keymaps in `setup()` if you want:

```lua
{
	"simonwinther/cppman.nvim",
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

The default sizing is:

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
Once the manual has been open it's possible to navigate through the documentation using the same keybindings of the standalone cppman program, in normal mode:
* **K**, **<C-]>** and **<2-LeftMouse>**: allows to follow the word under cursor
* **\<C-T\>** and **\<RightMouse\>**: go back to the previous page
