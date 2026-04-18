local M = {}

local uv = vim.uv or vim.loop
local config = require("cppman.config")
local history = require("cppman.history")
local index = require("cppman.index")

local plugin_cache_dir = vim.fn.stdpath("cache") .. "/cppman_plugin"
local user_cache_home = vim.env.XDG_CACHE_HOME or (vim.fn.expand("~") .. "/.cache")
vim.fn.mkdir(plugin_cache_dir, "p") -- once at module load; cppman spawn assumes it exists

local page_cache = {}
local resolve_cache = {}
local _pager_script = nil

local state = { win = nil, buf = nil }
local _current_page_name = nil
local _current_page_label = nil
local _current_timing_text = nil

-- Forward declarations — go_back and open_picker_for_back reference each other.
local go_back
local open_picker_for_back

local function now_ms()
	return uv.hrtime() / 1e6
end

local function is_valid()
	return state.win and vim.api.nvim_win_is_valid(state.win) and state.buf and vim.api.nvim_buf_is_valid(state.buf)
end

local function cppman_args(extra)
	local args = { "cppman" }
	for i = 1, #extra do
		args[#args + 1] = extra[i]
	end
	return args
end

local function run_cppman(args, stdin)
	return vim.system(args, {
		env = { XDG_CACHE_HOME = plugin_cache_dir },
		stdin = stdin,
		text = true,
	}):wait()
end

local function normalize_page_name(name)
	return name:gsub("/", "_")
end

local function get_cached_page_path(name)
	local source = config.options.source or "cppreference.com"
	local filename = normalize_page_name(name) .. ".3.gz"
	local candidates = {
		plugin_cache_dir .. "/cppman/" .. source .. "/" .. filename,
		user_cache_home .. "/cppman/" .. source .. "/" .. filename,
	}

	for i = 1, #candidates do
		if vim.fn.filereadable(candidates[i]) == 1 then
			return candidates[i]
		end
	end
	return nil
end

local function get_pager_script()
	if _pager_script ~= nil then
		return _pager_script or nil
	end

	local source = config.options.source or "cppreference.com"
	local candidates = {}
	local db_path = index.resolve_db(source)
	if db_path then
		local db_dir = db_path:match("^(.*)/[^/]+$")
		if db_dir then
			candidates[#candidates + 1] = db_dir .. "/pager.sh"
			local base_dir = db_dir:gsub("/lib$", "")
			candidates[#candidates + 1] = base_dir .. "/lib/pager.sh"
		end
	end

	candidates[#candidates + 1] = "/usr/lib/cppman/lib/pager.sh"
	candidates[#candidates + 1] = "/usr/local/lib/cppman/lib/pager.sh"
	candidates[#candidates + 1] = "/usr/share/cppman/pager.sh"

	for i = 1, #candidates do
		if vim.fn.filereadable(candidates[i]) == 1 then
			_pager_script = candidates[i]
			return _pager_script
		end
	end

	local res = vim.system(
		{
			"python3",
			"-c",
			"import cppman, os; print(os.path.join(os.path.dirname(cppman.__file__), 'lib', 'pager.sh'))",
		},
		{ text = true }
	):wait()
	if res.code == 0 then
		local path = vim.trim(res.stdout or "")
		if path ~= "" and vim.fn.filereadable(path) == 1 then
			_pager_script = path
			return _pager_script
		end
	end

	_pager_script = false
	return nil
end

local function render_cached_page(page_path, width, name)
	local pager_script = get_pager_script()
	if not pager_script then
		return nil
	end

	local res = vim.system({ pager_script, "pipe", page_path, tostring(width), "", name }, { text = true }):wait()
	if res.code ~= 0 or not res.stdout or res.stdout == "" then
		return nil
	end
	return res.stdout
end

-- Render a cppman page. Cached pages use cppman's pager.sh directly when
-- available, while uncached pages fall back to the cppman CLI. Caches hits AND
-- misses so re-renders and English-prose K presses never re-spawn the process.
-- Returns (lines|nil, timing|nil). timing is nil on in-memory cache hits.
local function render_page(name, width)
	local source = config.options.source or "cppreference.com"
	local key = source .. "\0" .. name .. "\0" .. width
	local cached = page_cache[key]
	if cached ~= nil then
		return cached or nil, nil
	end

	local t0 = now_ms()
	local external_t0 = now_ms()

	-- Fast path for already-cached pages: render the gzipped manpage directly.
	-- Fall back to cppman when the page is not cached yet or direct rendering fails.
	local stdout = nil
	local page_path = get_cached_page_path(name)
	if page_path then
		stdout = render_cached_page(page_path, width, name)
	end

	if not stdout then
		-- XDG_CACHE_HOME override keeps cppman from using a possibly-broken local cache.
		-- vim.system merges env by default (extends parent env).
		local res = run_cppman(cppman_args({ "--force-columns", tostring(width), name }), "1\n")
		if res.code ~= 0 or not res.stdout or res.stdout == "" then
			page_cache[key] = false
			return nil, {
				cppman_ms = now_ms() - external_t0,
				our_ms = 0,
				total_ms = now_ms() - t0,
			}
		end
		stdout = res.stdout
	end

	local cppman_ms = now_ms() - external_t0
	local internal_t0 = now_ms()

	local lines = vim.split(stdout, "\n", { plain = true })
	if lines[#lines] == "" then
		lines[#lines] = nil
	end

	-- Strip disambiguation menu header ("Please enter the selection: [1]") in-place.
	local content_start = 1
	for i = 1, #lines do
		if lines[i]:find("Please enter the selection:", 1, true) then
			content_start = i + 1
			break
		end
	end
	if content_start > 1 then
		local n = #lines
		for i = content_start, n do
			lines[i - content_start + 1] = lines[i]
		end
		for i = n - content_start + 2, n do
			lines[i] = nil
		end
	end

	if #lines == 0 then
		page_cache[key] = false
		return nil, {
			cppman_ms = cppman_ms,
			our_ms = now_ms() - internal_t0,
			total_ms = now_ms() - t0,
		}
	end

	local our_ms = now_ms() - internal_t0
	page_cache[key] = lines
	return lines, {
		cppman_ms = cppman_ms,
		our_ms = our_ms,
		total_ms = now_ms() - t0,
	}
end

-- Precomputed lowercase haystack for fast substring existence checks against
-- the index. Uses item.text_lower (set by index.lua) — no per-check :lower() calls.
-- Rebuilds only when index.load() returns a different table (reset).
local _haystack = { items = nil, blob = "" }
local function has_substring_match(needle_lower)
	local items = index.load()
	if _haystack.items ~= items then
		local parts = {}
		for i = 1, #items do
			parts[i] = items[i].text_lower
		end
		_haystack.items = items
		_haystack.blob = "\n" .. table.concat(parts, "\n") .. "\n"
	end
	return _haystack.blob:find(needle_lower, 1, true) ~= nil
end

local function resolve_page(name, preferred)
	local source = config.options.source or "cppreference.com"
	local key = source .. "\0" .. name .. "\0" .. (preferred or "")
	local cached = resolve_cache[key]
	if cached ~= nil then
		return cached or nil
	end

	local res = run_cppman(cppman_args({ "-f", name }))
	if res.code ~= 0 then
		resolve_cache[key] = false
		return nil
	end

	local preferred_lower = preferred and preferred:lower() or nil
	local page = nil

	for _, line in ipairs(vim.split(res.stdout or "", "\n", { plain = true })) do
		line = vim.trim(line)
		if line ~= "" then
			local alias, canonical = line:match("^(.-) %- (.+)$")
			local render_name = vim.trim(alias or canonical or line)
			if render_name ~= "" then
				if not page then
					page = render_name
				end
				if preferred_lower and render_name:lower():find(preferred_lower, 1, true) then
					page = render_name
					break
				end
			end
		end
	end

	if not page or page == "" then
		resolve_cache[key] = false
		return nil
	end

	resolve_cache[key] = page
	return page
end

-- Update the float's footer with timing info ("87ms" or "cached").
local function truncate_footer_text(text, max_width)
	if not text or text == "" or max_width <= 0 then
		return ""
	end
	if vim.fn.strdisplaywidth(text) <= max_width then
		return text
	end
	if max_width <= 3 then
		return string.rep(".", max_width)
	end

	local truncated = ""
	local limit = max_width - 3
	local chars = vim.fn.strchars(text)
	for i = 0, chars - 1 do
		local char = vim.fn.strcharpart(text, i, 1)
		if vim.fn.strdisplaywidth(truncated .. char) > limit then
			break
		end
		truncated = truncated .. char
	end
	return truncated .. "..."
end

local function set_footer(page_label, timing_text)
	if not is_valid() then
		return
	end
	local ok, cfg = pcall(vim.api.nvim_win_get_config, state.win)
	if not ok then
		return
	end

	local win_width = vim.api.nvim_win_get_width(state.win)
	local right = " " .. (timing_text or "") .. " "
	local right_width = vim.fn.strdisplaywidth(right)
	local max_label_width = math.max(0, win_width - right_width - 3)
	local left_label = truncate_footer_text(page_label or "", max_label_width)
	local left = left_label ~= "" and (" " .. left_label .. " ") or ""
	local gap_width = math.max(1, win_width - vim.fn.strdisplaywidth(left) - right_width)
	local gap = string.rep("═", gap_width)

	cfg.footer = {
		{ left, "Title" },
		{ gap, "FloatBorder" },
		{ right, "MoreMsg" },
	}
	cfg.footer_pos = "left"
	pcall(vim.api.nvim_win_set_config, state.win, cfg)
end

local function extract_page_label(name, lines)
	for i = 1, #lines - 1 do
		if lines[i] == "NAME" then
			local combined = ""
			for j = i + 1, #lines do
				local line = lines[j]
				if line ~= "" then
					combined = vim.trim((combined .. " " .. line:gsub("%s+", " ")))
					local label = combined:match("^(.-)%s+%-%s+")
					if label and label ~= "" then
						return vim.trim(label)
					end
				elseif combined ~= "" then
					break
				end
			end
			break
		end
	end
	return name
end

local function format_timing_value(elapsed)
	if elapsed == nil then
		return "cached"
	end
	if elapsed < 10 then
		return string.format("%.1fms", elapsed)
	end
	return string.format("%dms", math.floor(elapsed + 0.5))
end

local function format_timing_breakdown(timing)
	if timing == nil then
		return "cached"
	end
	return string.format(
		"cppman: %s | our: %s | total: %s",
		format_timing_value(timing.cppman_ms),
		format_timing_value(timing.our_ms),
		format_timing_value(timing.total_ms)
	)
end

local function load_page(name, lines, timing)
	if not is_valid() then
		return false
	end

	if not lines then
		local width = vim.api.nvim_win_get_width(state.win) - 4
		lines, timing = render_page(name, width)
		if not lines then
			vim.notify("[cppman] failed to render page for: " .. name, vim.log.levels.ERROR)
			return false
		end
	end

	local ui_t0 = now_ms()
	local buf = state.buf
	vim.bo[buf].ro = false
	vim.bo[buf].ma = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].ro = true
	vim.bo[buf].ma = false
	vim.bo[buf].mod = false
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].filetype = "cppman"
	vim.bo[buf].keywordprg = "cppman"

	vim.api.nvim_win_set_cursor(state.win, { 1, 0 })
	_current_page_name = name
	_current_page_label = extract_page_label(name, lines)
	if timing then
		local ui_ms = now_ms() - ui_t0
		timing.our_ms = timing.our_ms + ui_ms
		timing.total_ms = timing.total_ms + ui_ms
	end
	_current_timing_text = format_timing_breakdown(timing)
	set_footer(_current_page_label, _current_timing_text)
	return true
end

local function normalize_lookup_text(word)
	word = vim.trim((word or ""):gsub("%s+", " "))
	if word == "" then
		return ""
	end

	word = vim.trim(word:gsub("%s+%[[^%]]+%]$", ""))
	word = vim.trim(word:gsub("%s*%(%d+[a-zA-Z]*%)$", ""))
	return word
end

local function get_cursor_lookup_text()
	local fallback = vim.fn.expand("<cWORD>")
	local line = vim.trim(vim.api.nvim_get_current_line())
	local ref = line:match("^(.-)%s*%(%d+[a-zA-Z]*%)%s*%b[]%s*$") or line:match("^(.-)%s*%(%d+[a-zA-Z]*%)%s*$")

	if ref then
		ref = vim.trim(ref)
		if ref ~= "" then
			return ref, fallback
		end
	end

	return fallback, nil
end

local function try_open_page(name)
	if not is_valid() then
		return false
	end

	local width = vim.api.nvim_win_get_width(state.win) - 4
	local lines, timing = render_page(name, width)
	if not lines then
		return false
	end

	if _current_page_name then
		history.push({ type = "page", name = _current_page_name })
	end
	return load_page(name, lines, timing)
end

local function refocus_viewer()
	vim.schedule(function()
		if is_valid() then
			vim.api.nvim_set_current_win(state.win)
		end
	end)
end

go_back = function()
	local entry = history.pop()
	if not entry then
		return
	end
	if entry.type == "page" then
		load_page(entry.name)
		refocus_viewer()
	else
		open_picker_for_back(entry.pattern)
	end
end

open_picker_for_back = function(pattern)
	require("cppman.picker").open({
		search = pattern,
		on_back = go_back,
		on_select = function(item, used_pattern)
			history.push({ type = "search", pattern = used_pattern })
			load_page(item.name)
			refocus_viewer()
		end,
	})
end

local function follow_word(word, fallback_word)
	word = normalize_lookup_text(word)
	if word == "" then
		return
	end

	fallback_word = normalize_lookup_text(fallback_word)
	if fallback_word == word then
		fallback_word = ""
	end

	local exact = index.find_exact(word)
	if exact and try_open_page(exact.name) then
		return
	end

	-- Ask cppman directly first. This keeps canonical man-page names on the fast path.
	if try_open_page(word) then
		return
	end

	local word_lower = word:lower()
	if not has_substring_match(word_lower) then
		return
	end

	-- If the visible text is just a partial reference like "literals", ask cppman
	-- to resolve it to its best matching page before falling back to the picker.
	local resolved = resolve_page(word)
	if resolved and resolved ~= word and try_open_page(resolved) then
		return
	end

	if fallback_word ~= "" then
		local fallback_resolved = resolve_page(fallback_word, word_lower)
		if fallback_resolved and try_open_page(fallback_resolved) then
			return
		end

		local fallback_exact = index.find_exact(fallback_word)
		if fallback_exact and try_open_page(fallback_exact.name) then
			return
		end

		if try_open_page(fallback_word) then
			return
		end

		fallback_resolved = resolve_page(fallback_word)
		if fallback_resolved and fallback_resolved ~= fallback_word and try_open_page(fallback_resolved) then
			return
		end
	end

	if _current_page_name then
		history.push({ type = "page", name = _current_page_name })
	end
	require("cppman.picker").open({
		search = word,
		on_back = go_back,
		on_select = function(item, used_pattern)
			history.push({ type = "search", pattern = used_pattern })
			load_page(item.name)
			refocus_viewer()
		end,
	})
end

local function get_visual_selection()
	local mode = vim.fn.mode()
	local start_pos, end_pos

	if mode == "v" or mode == "V" or mode == "\22" then
		start_pos = vim.fn.getpos("v")
		end_pos = vim.fn.getpos(".")
	else
		mode = vim.fn.visualmode()
		start_pos = vim.fn.getpos("'<")
		end_pos = vim.fn.getpos("'>")
	end

	local sr, sc = start_pos[2], start_pos[3]
	local er, ec = end_pos[2], end_pos[3]

	if sr > er or (sr == er and sc > ec) then
		sr, er = er, sr
		sc, ec = ec, sc
	end

	local selection
	if mode == "V" then
		selection = vim.api.nvim_buf_get_lines(0, sr - 1, er, false)
	else
		selection = vim.api.nvim_buf_get_text(0, sr - 1, sc - 1, er - 1, ec, {})
	end

	return table.concat(selection, " ")
end

local function close()
	if is_valid() then
		vim.api.nvim_win_close(state.win, true)
	end
	history.reset()
	_current_page_name = nil
	_current_page_label = nil
	_current_timing_text = nil
	state.win = nil
	state.buf = nil
end

local function setup_keymaps(buf)
	local function map(mode, lhs, rhs)
		vim.keymap.set(mode, lhs, rhs, { silent = true, buffer = buf })
	end

	map("n", "q", close)
	map("n", "K", function()
		local word, fallback = get_cursor_lookup_text()
		follow_word(word, fallback)
	end)
	map("n", "<C-]>", function()
		local word, fallback = get_cursor_lookup_text()
		follow_word(word, fallback)
	end)
	map("n", "<2-LeftMouse>", function()
		local word, fallback = get_cursor_lookup_text()
		follow_word(word, fallback)
	end)
	map("x", "K", function()
		local sel = get_visual_selection()
		vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
		vim.schedule(function()
			follow_word(sel)
		end)
	end)
	map("x", "<C-]>", function()
		local sel = get_visual_selection()
		vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
		vim.schedule(function()
			follow_word(sel)
		end)
	end)
	map("n", "<C-T>", go_back)
	map("n", "<RightMouse>", go_back)
end

function M.open(name, from_search)
	name = normalize_lookup_text(name)
	if name == "" then
		return
	end

	if is_valid() then
		close()
	end

	history.reset()
	if from_search and from_search ~= "" then
		history.push({ type = "search", pattern = from_search })
	end
	_current_page_name = nil
	_current_page_label = nil
	_current_timing_text = nil

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"

	local ui = vim.api.nvim_list_uis()[1]

	local w = config.options.viewer.width or 0.8
	local h = config.options.viewer.height or 0.6
	local win_w = math.floor(ui.width * w)
	local win_h = math.floor(ui.height * h)
	local row = math.floor((ui.height - win_h) / 2)
	local col = math.floor((ui.width - win_w) / 2)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = win_w,
		height = win_h,
		row = row,
		col = col,
		style = "minimal",
		border = "double",
		title = " [cppman] ",
		title_pos = "center",
		zindex = 50,
	})

	vim.wo[win].wrap = false
	vim.wo[win].cursorline = true
	vim.wo[win].number = false
	vim.wo[win].signcolumn = "no"

	state.win = win
	state.buf = buf

	setup_keymaps(buf)

	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			history.reset()
			_current_page_name = nil
			_current_page_label = nil
			_current_timing_text = nil
			state.win = nil
			state.buf = nil
		end,
	})

	load_page(name)
end

return M
