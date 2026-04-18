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

local index_ok, _ = pcall(require, "cppman.index")
assert(index_ok, "failed to require cppman.index")

vim.cmd("qa")
