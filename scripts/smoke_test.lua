vim.opt.runtimepath:append(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.getcwd() .. "/.tests/deps/nui.nvim")

local ok, cppman = pcall(require, "cppman")
assert(ok, "failed to require cppman")

local setup_ok, setup_err = pcall(cppman.setup, {})
assert(setup_ok, setup_err)

assert(vim.fn.exists(":CPPMan") == 2, "CPPMan command was not created")

vim.cmd("qa")
