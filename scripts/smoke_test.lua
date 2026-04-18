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

local db_path = index.resolve_db("cppreference.com")
if db_path then
	local cppreference_items = index.load("cppreference.com")
	local both_items = index.load("both")
	assert(#cppreference_items > 0, "cppreference index is empty")
	assert(#both_items >= #cppreference_items, "combined index should not be smaller than cppreference index")

	local vector_matches = index.find_exact_matches("std::vector", "both")
	assert(#vector_matches >= 1, "expected exact matches for std::vector in combined index")
	assert(vector_matches[1].source ~= nil, "combined exact match is missing source metadata")
else
	print("Skipping index data tests because no valid index.db was found.")
end

vim.cmd("qa")
