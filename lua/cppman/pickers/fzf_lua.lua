local M = {}

local common = require("cppman.pickers.common")

function M.is_available()
	local ok, FzfLua = pcall(require, "fzf-lua")
	if not ok then
		return false, "fzf-lua not found"
	end
	if type(FzfLua.fzf_exec) ~= "function" then
		return false, "fzf-lua found but fzf_exec is unavailable"
	end
	return true
end

local function make_entries(items, source)
	local entries = {}
	local by_id = {}

	for i, item in ipairs(items) do
		entries[i] = tostring(i) .. "\t" .. common.item_label(item, source)
		by_id[i] = item
	end

	return entries, by_id
end

local function selected_item(selected, by_id)
	local line = selected and selected[1]
	if not line then
		return nil
	end

	local id = tonumber(line:match("^(%d+)\t"))
	return id and by_id[id] or nil
end

local function last_query(FzfLua, fallback)
	local ok, query = pcall(FzfLua.get_last_query)
	if ok and type(query) == "string" then
		return query
	end
	return fallback or ""
end

function M.open(opts)
	opts = opts or {}
	local on_select = opts.on_select
	local on_back = opts.on_back
	local pattern = opts.search or ""

	local ok, FzfLua = pcall(require, "fzf-lua")
	if not ok or type(FzfLua.fzf_exec) ~= "function" then
		vim.notify("[cppman] fzf-lua is required for picker.provider = 'fzf-lua'", vim.log.levels.ERROR)
		return
	end

	local config = require("cppman.config")
	local picker_opts = config.options.picker or {}
	local source = opts.source or config.options.source or "both"
	local entries, by_id = make_entries(opts.items or {}, source)

	local actions = {
		default = function(selected)
			local item = selected_item(selected, by_id)
			if not item then
				return
			end

			local used_pattern = last_query(FzfLua, pattern)
			if on_select then
				on_select(item, used_pattern)
			end
		end,
	}

	if on_back then
		actions["ctrl-t"] = function()
			vim.schedule(on_back)
		end
	end

	local header = "enter: search"
	if on_back then
		header = header .. " | ctrl-t: back"
	end

	local call_opts = vim.tbl_deep_extend("force", {
		prompt = "keyword> ",
		query = pattern,
		previewer = false,
		header = header,
		fzf_opts = {
			["--with-nth"] = "2..",
		},
		winopts = {
			backdrop = 100,
			border = "rounded",
			title = " keyword search - " .. common.format_timing(opts.load_ms or 0) .. " ",
			title_pos = "center",
			width = picker_opts.width or 0.4,
			height = picker_opts.height or 0.4,
			preview = {
				hidden = true,
			},
		},
	}, vim.deepcopy(picker_opts.fzf_lua or {}))
	call_opts.actions = vim.tbl_deep_extend("force", call_opts.actions or {}, actions)

	FzfLua.fzf_exec(entries, call_opts)
end

return M
