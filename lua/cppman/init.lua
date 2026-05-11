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
end

function M.search(opts)
	local config = require("cppman.config")
	local source = (opts and opts.source) or config.options.source
	local picker = require("cppman.picker")
	local viewer = require("cppman.viewer")
	picker.open(vim.tbl_extend("force", opts or {}, {
		on_select = function(item, used_pattern)
			viewer.open({
				item = item,
				from_search = used_pattern,
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

	local match = index.find_exact(word, source)
	if match then
		viewer.open({ item = match })
	else
		M.search({ search = word, source = source })
	end
end

return M
