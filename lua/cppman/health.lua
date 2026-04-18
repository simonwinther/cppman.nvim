local M = {}

function M.check()
	local h = vim.health

	h.start("cppman.nvim")

	if vim.fn.executable("cppman") == 1 then
		h.ok("cppman executable found")
	else
		h.error("cppman not found", { "Install cppman: https://github.com/aitjcize/cppman" })
	end

	if vim.fn.executable("sqlite3") == 1 then
		h.ok("sqlite3 executable found")
	else
		h.error("sqlite3 not found", { "Install sqlite3 (e.g. apt install sqlite3, brew install sqlite)" })
	end

	local snacks_ok, Snacks = pcall(require, "snacks")
	if snacks_ok and Snacks.picker then
		h.ok("snacks.nvim with picker found")
	elseif snacks_ok then
		h.error(
			"snacks.nvim found but picker module unavailable",
			{ "Upgrade snacks.nvim to a version with picker support" }
		)
	else
		h.error("snacks.nvim not found", { "Add folke/snacks.nvim as a dependency" })
	end

	local config = require("cppman.config")
	local index = require("cppman.index")
	local source = config.options.source or "both"
	local db = index.resolve_db(index.get_sources(source)[1])
	if db then
		h.ok("index.db resolved for " .. source .. ": " .. db)
	else
		h.error(
			"no valid index.db found",
			{ "Ensure cppman is properly installed and its Python package is importable" }
		)
	end
end

return M
