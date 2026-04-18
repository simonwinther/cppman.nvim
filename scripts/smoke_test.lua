vim.opt.runtimepath:append(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.getcwd() .. "/.tests/deps/snacks.nvim")

local ok, cppman = pcall(require, "cppman")
assert(ok, "failed to require cppman: " .. tostring(cppman))

local setup_ok, setup_err = pcall(cppman.setup, {})
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

for _, mod in ipairs({ "cppman.render", "cppman.sections", "cppman.viewer", "cppman.picker", "cppman.health" }) do
	local rok, rerr = pcall(require, mod)
	assert(rok, "failed to require " .. mod .. ": " .. tostring(rerr))
end

-- Source whitelist guards against arbitrary input.
local bad_ok, bad_err = pcall(index.load, "evil; DROP TABLE x")
assert(not bad_ok, "expected source whitelist to reject bad input")
assert(tostring(bad_err):find("invalid source", 1, true), "expected 'invalid source' in error: " .. tostring(bad_err))

-- Re-setup is idempotent and clears caches.
assert(pcall(cppman.setup, {}), "re-setup failed")
assert(pcall(cppman.setup, { source = "cppreference.com" }), "re-setup with source override failed")

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

	local vector_matches = index.find_exact_matches("std::vector", "both")
	assert(#vector_matches >= 1, "expected exact matches for std::vector in combined index")
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
