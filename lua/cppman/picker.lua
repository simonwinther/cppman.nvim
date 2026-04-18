local M = {}

local uv = vim.uv or vim.loop
local NBSP = vim.fn.nr2char(160)

M.last_pattern = ""

local function now_ms()
	return uv.hrtime() / 1e6
end

local function format_timing(elapsed)
	if elapsed < 10 then
		return string.format("%.1fms", elapsed)
	end
	return string.format("%dms", math.floor(elapsed + 0.5))
end

local function source_badge(source)
	if source == "cppreference.com" then
		return " [ref]"
	end
	if source == "cplusplus.com" then
		return " [c++]"
	end
	return ""
end

function M.open(opts)
	opts = opts or {}
	local on_select = opts.on_select
	local on_back = opts.on_back
	local pattern = opts.search or ""

	local config = require("cppman.config")
	local source = opts.source or config.options.source or "both"

	local index = require("cppman.index")
	local t0 = now_ms()
	local items = index.load(source)
	local load_ms = now_ms() - t0
	if #items == 0 then
		vim.notify("[cppman] no items loaded — check cppman and sqlite3 installation", vim.log.levels.ERROR)
		return
	end

	local ok, Snacks = pcall(require, "snacks")
	if not ok or not Snacks.picker then
		vim.notify("[cppman] snacks.nvim with picker support is required", vim.log.levels.ERROR)
		return
	end

	-- snacks.picker.Text is {[1]: string, [2]: string?} — positional, not named fields
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

	local title = {
		{ "keyword", "Title" },
		{ NBSP .. "search • " .. format_timing(load_ms), "Comment" },
		{ " ", "FloatTitle" },
	}
	local footer = {
		{ " enter ", "SpecialChar" },
		{ "to search ", "Comment" },
	}
	if on_back then
		footer[#footer + 1] = { " C-T ", "SpecialChar" }
		footer[#footer + 1] = { "back ", "Comment" }
	end

	Snacks.picker.pick({
		source = "cppman",
		items = items,
		format = function(item)
			if source == "both" then
				return {
					{ item.text, "Normal" },
					{ source_badge(item.source), "Comment" },
				}
			end
			return { { item.text, "Normal" } }
		end,
		confirm = function(picker, item)
			if item then
				M.last_pattern = (picker.input and picker.input.filter and picker.input.filter.pattern) or pattern
			end
			picker:close()
			if item and on_select then
				local used_pattern = M.last_pattern
				on_select(item, used_pattern)
			end
		end,
		actions = actions,
		win = extra_keys,
		pattern = pattern,
		layout = {
			layout = {
				box = "vertical",
				backdrop = false,
				border = "rounded",
				title = title,
				title_pos = "center",
				footer = footer,
				footer_pos = "right",
				width = config.options.picker.width or 0.4,
				min_width = 40,
				height = config.options.picker.height or 0.4,
				min_height = 10,
				{ win = "input", height = 1, border = "none" },
				{ win = "list", border = "none" },
			},
		},
	})
end

return M
