local M = {}

local common = require("cppman.pickers.common")

function M.is_available()
	local ok, Snacks = pcall(require, "snacks")
	if not ok then
		return false, "snacks.nvim not found"
	end
	if not Snacks.picker then
		return false, "snacks.nvim found but picker module unavailable"
	end
	return true
end

function M.open(opts)
	opts = opts or {}
	local on_select = opts.on_select
	local on_back = opts.on_back
	local pattern = opts.search or ""

	local ok, Snacks = pcall(require, "snacks")
	if not ok or not Snacks.picker then
		vim.notify("[cppman] snacks.nvim with picker support is required", vim.log.levels.ERROR)
		return
	end

	local config = require("cppman.config")
	local picker_opts = config.options.picker or {}
	local source = opts.source or config.options.source or "both"

	local actions = {}
	local extra_keys = {}
	if on_back then
		actions.cppman_go_back = function(picker)
			picker:close()
			vim.schedule(on_back)
		end
		extra_keys = {
			input = { keys = { ["<C-T>"] = { "cppman_go_back", mode = { "i", "n" } } } },
			list = { keys = { ["<C-T>"] = { "cppman_go_back", mode = { "n" } } } },
		}
	end

	local footer = {
		{ " enter ", "SpecialChar" },
		{ "to search ", "Comment" },
	}
	if on_back then
		footer[#footer + 1] = { " C-T ", "SpecialChar" }
		footer[#footer + 1] = { "back ", "Comment" }
	end

	local call_opts = vim.tbl_deep_extend("force", vim.deepcopy(picker_opts.snacks or {}), {
		source = "cppman",
		items = opts.items,
		format = function(item)
			if source == "both" then
				return {
					{ item.text, "Normal" },
					{ common.source_badge(item.source), "Comment" },
				}
			end
			return { { item.text, "Normal" } }
		end,
		confirm = function(picker, item)
			if item then
				local ok_pattern, current = pcall(function()
					return picker.input.filter.pattern
				end)
				local used_pattern = (ok_pattern and current) or pattern
				picker:close()
				if on_select then
					on_select(item, used_pattern)
				end
				return
			end
			picker:close()
		end,
		actions = actions,
		win = extra_keys,
		pattern = pattern,
		layout = {
			layout = {
				box = "vertical",
				backdrop = false,
				border = "rounded",
				title = common.search_title(opts.load_ms or 0),
				title_pos = "center",
				footer = footer,
				footer_pos = "right",
				width = picker_opts.width or 0.4,
				min_width = 40,
				height = picker_opts.height or 0.4,
				min_height = 10,
				{ win = "input", height = 1, border = "none" },
				{ win = "list", border = "none" },
			},
		},
	})

	Snacks.picker.pick(call_opts)
end

return M
