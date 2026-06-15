vim.opt.runtimepath:append(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.getcwd() .. "/.tests/deps/snacks.nvim")
vim.opt.runtimepath:append(vim.fn.getcwd() .. "/.tests/deps/fzf-lua")

local ok, cppman = pcall(require, "cppman")
assert(ok, "failed to require cppman: " .. tostring(cppman))

local requested_provider = vim.env.CPPMAN_PICKER_PROVIDER
local setup_opts = {}
if requested_provider and requested_provider ~= "" then
	setup_opts.picker = { provider = requested_provider }
end

local setup_ok, setup_err = pcall(cppman.setup, setup_opts)
assert(setup_ok, "setup failed: " .. tostring(setup_err))

assert(vim.fn.exists(":CPPMan") == 2, "CPPMan command was not created")

-- Verify submodules load correctly
local config_ok, config = pcall(require, "cppman.config")
assert(config_ok, "failed to require cppman.config: " .. tostring(config))
assert(config.options ~= nil, "config.options is nil after setup")

local history_ok, history = pcall(require, "cppman.history")
assert(history_ok, "failed to require cppman.history: " .. tostring(history))

local index_ok, index = pcall(require, "cppman.index")
assert(index_ok, "failed to require cppman.index")

for _, mod in ipairs({
	"cppman.render",
	"cppman.sections",
	"cppman.viewer",
	"cppman.picker",
	"cppman.pickers.common",
	"cppman.pickers.snacks",
	"cppman.pickers.fzf_lua",
	"cppman.health",
}) do
	local rok, rerr = pcall(require, mod)
	assert(rok, "failed to require " .. mod .. ": " .. tostring(rerr))
end

local picker = require("cppman.picker")
assert(picker.normalize_provider("fzf_lua") == "fzf-lua", "fzf_lua provider alias should normalize")
assert(picker.normalize_provider("snacks.nvim") == "snacks", "snacks.nvim provider alias should normalize")

local bad_provider = picker.provider_status("unknown")
assert(not bad_provider.available, "unknown picker provider should not be available")

if requested_provider and requested_provider ~= "" then
	local normalized = picker.normalize_provider(requested_provider)
	local resolved, resolve_err = picker.resolve_provider(requested_provider)
	if normalized == "auto" then
		assert(resolved ~= nil, "auto picker provider did not resolve: " .. tostring(resolve_err))
	else
		assert(resolved == normalized, "requested picker provider did not resolve: " .. tostring(resolve_err))
	end
end

do
	local loaded_fzf_lua = package.loaded["fzf-lua"]
	local preload_fzf_lua = package.preload["fzf-lua"]
	local captured
	package.loaded["fzf-lua"] = {
		fzf_exec = function(entries, opts)
			captured = { entries = entries, opts = opts }
		end,
		get_last_query = function()
			return "vec"
		end,
	}
	package.preload["fzf-lua"] = nil

	local selected
	require("cppman.pickers.fzf_lua").open({
		source = "both",
		items = {
			{
				text = "std::vector",
				page = "std::vector",
				query = "std::vector",
				source = "cppreference.com",
			},
		},
		on_select = function(item, pattern)
			selected = { item = item, pattern = pattern }
		end,
	})

	assert(captured, "fzf-lua backend did not call fzf_exec")
	assert(captured.opts.fzf_opts["--nth"] == nil, "fzf-lua backend must not restrict matching with --nth")
	assert(captured.opts.fzf_opts["--delimiter"] == nil, "fzf-lua backend must not set a custom delimiter")
	assert(captured.opts.fzf_opts["--with-nth"] == "2..", "fzf-lua backend should hide the internal id column")
	captured.opts.actions.default({ captured.entries[1] })
	assert(selected and selected.item.text == "std::vector", "fzf-lua selection did not map back to the index item")
	assert(selected.pattern == "vec", "fzf-lua selection did not preserve the last query")

	package.loaded["fzf-lua"] = loaded_fzf_lua
	package.preload["fzf-lua"] = preload_fzf_lua
end

-- Source whitelist guards against arbitrary input.
local bad_ok, bad_err = pcall(index.load, "evil; DROP TABLE x")
assert(not bad_ok, "expected source whitelist to reject bad input")
assert(tostring(bad_err):find("invalid source", 1, true), "expected 'invalid source' in error: " .. tostring(bad_err))

-- Re-setup is idempotent and clears caches.
assert(pcall(cppman.setup, {}), "re-setup failed")
assert(pcall(cppman.setup, { source = "cppreference.com" }), "re-setup with source override failed")

-- viewer.border is configurable (issue #16) and survives the merge.
assert(pcall(cppman.setup, { viewer = { border = "rounded" } }), "re-setup with viewer.border override failed")
assert(config.options.viewer.border == "rounded", "viewer.border override did not take effect")

local sections = require("cppman.sections")
local sample = { "NAME", "      vector", "", "DESCRIPTION", "      ...", "  1) thing", "", "EXAMPLE" }
local idx = sections.build(sample)
assert(idx.ordered ~= nil, "sections.build did not return ordered list")

local db_path = index.resolve_db("cppreference.com")
if db_path then
	local cppreference_items = index.load("cppreference.com")
	local both_items = index.load("both")
	assert(#cppreference_items > 0, "cppreference index is empty")
	assert(#both_items >= #cppreference_items, "combined index should not be smaller than cppreference index")

	local ids = {}
	for _, item in ipairs(both_items) do
		assert(type(item.id) == "string" and item.id ~= "", "index item is missing a stable id")
		assert(not ids[item.id], "combined index contains duplicate item id: " .. item.id)
		ids[item.id] = true
	end

	local by_text = {}
	for _, item in ipairs(both_items) do
		local existing = by_text[item.text]
		if existing then
			assert(existing.id ~= item.id, "same-text entries should keep distinct picker ids: " .. item.text)
		else
			by_text[item.text] = item
		end
	end

	local vector_matches = index.find_exact_matches("std::vector", "both")
	assert(#vector_matches >= 1, "expected exact matches for std::vector in combined index")
	assert(vector_matches[1].id ~= nil and vector_matches[1].id ~= "", "combined exact match is missing stable id")
	assert(vector_matches[1].source ~= nil, "combined exact match is missing source metadata")
	assert(vector_matches[1].page ~= nil, "combined exact match is missing page metadata")
	assert(vector_matches[1].query ~= nil, "combined exact match is missing query metadata")

	-- Render pipeline: actually exercise cppman + cache.
	local render = require("cppman.render")
	local vector_item = vector_matches[1]
	local lines, timing = render.render_page(vector_item.page, vector_item.query, 80, vector_item.source)
	if lines then
		assert(#lines > 10, "render produced too few lines: " .. #lines)
		assert(timing ~= nil, "first render must report timing")
		local _, t2 = render.render_page(vector_item.page, vector_item.query, 80, vector_item.source)
		assert(t2 == nil, "second render at same width must be a cache hit")
	else
		print("Skipping render test (cppman could not render std::vector).")
	end

	local header = index.find_exact("<cmath> (math.h)", "cplusplus.com")
	if header then
		assert(header.page == "<cmath> (math.h)", "cplusplus header page identity changed unexpectedly")
		assert(header.query ~= nil and header.query ~= "", "cplusplus header is missing query metadata")
		assert(header.query ~= header.page, "cplusplus header should resolve through an attached query")
		local header_lines = render.render_page(header.page, header.query, 80, header.source)
		assert(header_lines and #header_lines > 10, "cplusplus header render failed through stored query")
	end

	local int32 = index.find_exact("int32_t", "cppreference.com")
	assert(int32 ~= nil, "synthetic alias lookup for int32_t failed")
	assert(
		int32.page == "Fixed width integer types (since C++11)",
		"int32_t should map to fixed width integer types page"
	)
	assert(int32.query ~= "int32_t", "int32_t should reuse the page query, not the alias text")

	local std_int32 = index.find_exact("std::int32_t", "cppreference.com")
	assert(std_int32 ~= nil, "synthetic alias lookup for std::int32_t failed")
	assert(std_int32.page == int32.page, "std::int32_t should map to the same page as int32_t")

	local prid32 = index.find_exact("PRId32", "cppreference.com")
	assert(prid32 ~= nil, "synthetic alias lookup for PRId32 failed")
	assert(prid32.page == int32.page, "PRId32 should map to fixed width integer types page")

	local intptr_min = index.find_exact("INTPTR_MIN", "cppreference.com")
	assert(intptr_min ~= nil, "synthetic alias lookup for INTPTR_MIN failed")
	assert(intptr_min.page == int32.page, "INTPTR_MIN should map to fixed width integer types page")

	local prixptr = index.find_exact("PRIxPTR", "cppreference.com")
	assert(prixptr ~= nil, "synthetic alias lookup for PRIxPTR failed")
	assert(prixptr.page == int32.page, "PRIxPTR should map to fixed width integer types page")

	local scnxptr = index.find_exact("SCNxPTR", "cppreference.com")
	assert(scnxptr ~= nil, "synthetic alias lookup for SCNxPTR failed")
	assert(scnxptr.page == int32.page, "SCNxPTR should map to fixed width integer types page")

	local scnxptr_matches = index.find_exact_matches("SCNXPTR", "cppreference.com")
	assert(
		#scnxptr_matches == 1 and scnxptr_matches[1].text == "SCNxPTR",
		"SCNXPTR should only resolve to the canonical SCNxPTR alias"
	)
else
	print("Skipping index data tests because no valid index.db was found.")
end

vim.cmd("qa")
