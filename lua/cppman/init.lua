local M = {}

function M.setup(opts)
	local config = require("cppman.config")
	config.setup(opts)

	vim.api.nvim_create_user_command("CPPMan", function(args)
		local term = vim.trim(args.args or "")
		if term == "" then
			M.search()
		else
			M.open_for(term)
		end
	end, { nargs = "?" })

	local keymaps = config.options.keymaps

	if keymaps.open_under_cursor then
		vim.keymap.set("n", keymaps.open_under_cursor, function()
			M.open_for(vim.fn.expand("<cword>"))
		end, { silent = true, desc = "[C++] open under cursor" })
	end

	if keymaps.search then
		vim.keymap.set("n", keymaps.search, M.search, { silent = true, desc = "[C++] keyword search" })
	end
end

function M.search(opts)
	local config = require("cppman.config")
	local source = (opts and opts.source) or config.options.source
	local picker = require("cppman.picker")
	local viewer = require("cppman.viewer")
	picker.open(vim.tbl_extend("force", opts or {}, {
		on_select = function(item, used_pattern)
			viewer.open({
				name = item.name,
				from_search = used_pattern,
				source = item.source,
				search_source = source,
			})
		end,
	}))
end

function M.open_for(word)
	word = vim.trim((word or ""):gsub("%s+", " "))
	if word == "" then
		M.search()
		return
	end

	local config = require("cppman.config")
	local index = require("cppman.index")
	local viewer = require("cppman.viewer")
	local source = config.options.source

	local matches = index.find_exact_matches(word, source)
	if #matches == 1 then
		viewer.open({ name = matches[1].name, source = matches[1].source })
	else
		M.search({ search = word, source = source })
	end
end

return M
