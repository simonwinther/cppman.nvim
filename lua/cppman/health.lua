local M = {}

function M.check()
	local h = vim.health

	h.start("cppman.nvim")

	if vim.fn.has("nvim-0.10") == 1 then
		h.ok("Neovim 0.10+ detected")
	else
		h.error("Neovim 0.10+ required (uses vim.keycode, vim.system, vim.uv)")
	end

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

	local config = require("cppman.config")
	local picker = require("cppman.picker")
	local picker_opts = config.options.picker or {}
	local provider = picker.normalize_provider(picker_opts.provider or "auto")
	local statuses = picker.provider_statuses()

	if provider == "auto" then
		local active = picker.resolve_provider(provider)
		if active then
			h.ok("picker provider resolved to " .. statuses[active].label)
		else
			h.error("no picker backend found", { "Install folke/snacks.nvim or ibhagwan/fzf-lua" })
		end
		for _, status in pairs(statuses) do
			if status.available then
				h.info(status.label .. " available")
			else
				h.info(status.label .. " unavailable: " .. (status.error or "missing dependency"))
			end
		end
	else
		local status = picker.provider_status(provider)
		if status.available then
			h.ok("picker provider found: " .. status.label)
		else
			h.error(
				"picker provider unavailable: " .. status.label,
				{ status.error or "Install the configured picker backend" }
			)
		end
	end

	local fzf_status = statuses["fzf-lua"]
	if
		fzf_status
		and fzf_status.available
		and vim.fn.executable("fzf") == 0
		and not (picker_opts.fzf_lua or {}).fzf_bin
	then
		h.warn("fzf executable not found", { "Install fzf, or configure fzf-lua to use another fzf-compatible binary" })
	end

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
