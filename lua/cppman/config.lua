local M = {}

M.defaults = {
	keymaps = {
		open_under_cursor = "<leader>cu",
		search = "<leader>ck",
	},
	source = "both",
	index = {
		db_path = nil,
	},
	picker = {
		width = 0.4,
		height = 0.4,
	},
	viewer = {
		width = 0.8,
		height = 0.6,
	},
}

M.options = vim.deepcopy(M.defaults)

local _setup_called = false

function M.setup(opts)
	opts = opts or {}
	M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts)

	-- Re-setup invalidates per-session caches that depend on options (db path, source).
	if _setup_called then
		local ok_index, index = pcall(require, "cppman.index")
		if ok_index and index.reset then
			index.reset()
		end
		local ok_viewer, viewer = pcall(require, "cppman.viewer")
		if ok_viewer and viewer.reset then
			viewer.reset()
		end
	end
	_setup_called = true
end

return M
