local M = {}

local uv = vim.uv or vim.loop

local _config, _history, _index, _render
local function config()
	_config = _config or require("cppman.config")
	return _config
end
local function history()
	_history = _history or require("cppman.history")
	return _history
end
local function index()
	_index = _index or require("cppman.index")
	return _index
end
local function render()
	_render = _render or require("cppman.render")
	return _render
end

local state = { win = nil, buf = nil }
local _current_page_name = nil
local _current_page_query = nil
local _current_page_source = nil
local _current_page_label = nil
local _current_timing_text = nil
local _current_sections = nil

-- Forward declarations — go_back/go_forward and open_picker_for_back reference each other.
local go_back
local go_forward
local open_picker_for_back

local function now_ms()
	return uv.hrtime() / 1e6
end

local function is_valid()
	return state.win and vim.api.nvim_win_is_valid(state.win) and state.buf and vim.api.nvim_buf_is_valid(state.buf)
end

-- Snapshot of the current page suitable for pushing onto a history stack.
-- Returns nil when no page is loaded or the window is gone.
local function snapshot_current_page()
	if not _current_page_name or not is_valid() then
		return nil
	end
	local ok, pos = pcall(vim.api.nvim_win_get_cursor, state.win)
	local cursor = ok and pos or { 1, 0 }
	return {
		type = "page",
		page = _current_page_name,
		query = _current_page_query,
		source = _current_page_source,
		cursor = cursor,
	}
end

local function get_source(source)
	return index().get_sources(source)[1]
end

local function current_source()
	return _current_page_source or get_source()
end

local function make_page_item(item, source)
	if not item then
		return nil
	end
	local page = item.page or item.name or item.text or item.query
	if not page or page == "" then
		return nil
	end
	return {
		text = item.text or page,
		page = page,
		query = item.query or page,
		source = get_source(item.source or source),
	}
end

local function raw_lookup_item(name, source)
	return make_page_item({ text = name, page = name, query = name, source = source }, source)
end

-- Precomputed lowercase haystack for fast substring existence checks against
-- the index. Rebuilds only when index().load() returns a different table (reset).
local _haystack = { items = nil, blob = "" }
local function has_substring_match(needle_lower, source)
	local items = index().load(source)
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

-- Update the float's footer. Format: " <page label> ═══════ <timing> ".
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

	local limit = max_width - 3
	local chars = vim.fn.strchars(text)
	local accum = 0
	local last_end = 0
	for i = 0, chars - 1 do
		local char = vim.fn.strcharpart(text, i, 1)
		local w = vim.fn.strdisplaywidth(char)
		if accum + w > limit then
			break
		end
		accum = accum + w
		last_end = i + 1
	end
	return vim.fn.strcharpart(text, 0, last_end) .. "..."
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

local sections_mod = require("cppman.sections")

local function get_toc_target_line()
	if not is_valid() or not _current_sections or not _current_sections.toc_start then
		return nil
	end

	local row = vim.api.nvim_win_get_cursor(state.win)[1]
	if row < _current_sections.toc_start or row > _current_sections.toc_end then
		return nil
	end

	local word = sections_mod.normalize_key(vim.fn.expand("<cword>"))
	if word == "" then
		return nil
	end

	if word:match("^%d+$") then
		local entry = _current_sections.ordered[tonumber(word)]
		return entry and entry.line or nil
	end

	local matches = {}
	local pattern = "%f[%a]" .. vim.pesc(word) .. "%f[^%a]"
	for _, section in ipairs(_current_sections.ordered) do
		if section.key:find(pattern) then
			matches[#matches + 1] = section.line
		end
	end

	if #matches == 1 then
		return matches[1]
	end

	return nil
end

local function jump_to_toc_section()
	local line = get_toc_target_line()
	if not line then
		return false
	end

	vim.api.nvim_win_set_cursor(state.win, { line, 0 })
	vim.cmd("normal! zz")
	return true
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

local function load_page(item, lines, timing, cursor)
	if not is_valid() then
		return false
	end
	item = make_page_item(item)
	if not item then
		return false
	end

	if not lines then
		local width = vim.api.nvim_win_get_width(state.win) - 4
		lines, timing = render().render_page(item.page, item.query, width, item.source)
		if not lines then
			vim.notify("[cppman] failed to render page for: " .. item.page, vim.log.levels.ERROR)
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

	local target = { 1, 0 }
	if cursor and cursor[1] then
		local line_count = vim.api.nvim_buf_line_count(buf)
		local row = math.max(1, math.min(cursor[1], line_count))
		target = { row, cursor[2] or 0 }
	end
	pcall(vim.api.nvim_win_set_cursor, state.win, target)
	_current_page_name = item.page
	_current_page_query = item.query
	_current_page_source = item.source
	_current_page_label = extract_page_label(item.page, lines)
	_current_sections = sections_mod.build(lines)
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

local function try_open_page(item)
	if not is_valid() then
		return false
	end
	item = make_page_item(item)
	if not item then
		return false
	end

	local width = vim.api.nvim_win_get_width(state.win) - 4
	local lines, timing = render().render_page(item.page, item.query, width, item.source)
	if not lines then
		return false
	end

	local snap = snapshot_current_page()
	if snap then
		history().push(snap)
		history().forward_clear()
	end
	return load_page(item, lines, timing)
end

local function refocus_viewer()
	vim.schedule(function()
		if is_valid() then
			vim.api.nvim_set_current_win(state.win)
		end
	end)
end

go_back = function()
	local entry = history().pop()
	if not entry then
		return
	end
	local snap = snapshot_current_page()
	if snap then
		history().forward_push(snap)
	end
	if entry.type == "page" then
		load_page(entry, nil, nil, entry.cursor)
		refocus_viewer()
	else
		open_picker_for_back(entry.pattern, entry.source)
	end
end

go_forward = function()
	local entry = history().forward_pop()
	if not entry then
		return
	end
	local snap = snapshot_current_page()
	if snap then
		history().push(snap)
	end
	if entry.type == "page" then
		load_page(entry, nil, nil, entry.cursor)
		refocus_viewer()
	else
		open_picker_for_back(entry.pattern, entry.source)
	end
end

open_picker_for_back = function(pattern, source)
	require("cppman.picker").open({
		search = pattern,
		source = source,
		on_back = go_back,
		on_select = function(item, used_pattern)
			history().push({ type = "search", pattern = used_pattern, source = source })
			history().forward_clear()
			load_page(item)
			refocus_viewer()
		end,
	})
end

local function follow_word(word, fallback_word)
	local source = current_source()
	word = normalize_lookup_text(word)
	if word == "" then
		return
	end

	fallback_word = normalize_lookup_text(fallback_word)
	if fallback_word == word then
		fallback_word = ""
	end

	local exact = index().find_exact(word, source)
	if exact and try_open_page(exact) then
		return
	end

	-- Ask cppman directly first. This keeps canonical man-page names on the fast path.
	if try_open_page(raw_lookup_item(word, source)) then
		return
	end

	local word_lower = word:lower()
	if not has_substring_match(word_lower, source) then
		return
	end

	-- If the visible text is just a partial reference like "literals", ask cppman
	-- to resolve it to its best matching page before falling back to the picker.
	local resolved = render().resolve_page(word, nil, source)
	if resolved and (resolved.page ~= word or resolved.query ~= word) and try_open_page(resolved) then
		return
	end

	if fallback_word ~= "" then
		local fallback_resolved = render().resolve_page(fallback_word, word_lower, source)
		if fallback_resolved and try_open_page(fallback_resolved) then
			return
		end

		local fallback_exact = index().find_exact(fallback_word, source)
		if fallback_exact and try_open_page(fallback_exact) then
			return
		end

		if try_open_page(raw_lookup_item(fallback_word, source)) then
			return
		end

		fallback_resolved = render().resolve_page(fallback_word, nil, source)
		if
			fallback_resolved
			and (fallback_resolved.page ~= fallback_word or fallback_resolved.query ~= fallback_word)
			and try_open_page(fallback_resolved)
		then
			return
		end
	end

	local snap = snapshot_current_page()
	if snap then
		history().push(snap)
		history().forward_clear()
	end
	require("cppman.picker").open({
		search = word,
		source = source,
		on_back = go_back,
		on_select = function(item, used_pattern)
			history().push({ type = "search", pattern = used_pattern, source = source })
			history().forward_clear()
			load_page(item)
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

-- Just close the window; the WinClosed autocmd in M.open owns all state cleanup.
local function close()
	if is_valid() then
		vim.api.nvim_win_close(state.win, true)
	end
end

local function setup_keymaps(buf)
	local function map(mode, lhs, rhs)
		vim.keymap.set(mode, lhs, rhs, { silent = true, buffer = buf })
	end

	map("n", "q", close)
	map("n", "K", function()
		if jump_to_toc_section() then
			return
		end
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
	map("n", "<Tab>", go_forward)
end

function M.reset()
	render().reset()
	_haystack = { items = nil, blob = "" }
	_current_page_name = nil
	_current_page_query = nil
	_current_page_source = nil
	_current_page_label = nil
	_current_timing_text = nil
	_current_sections = nil
end

function M.open(opts)
	opts = opts or {}
	local item = make_page_item(opts.item, opts.source)
	local from_search = opts.from_search
	local search_source = opts.search_source

	if not item then
		local name = normalize_lookup_text(opts.name)
		if name == "" then
			return
		end
		local source = get_source(opts.source)
		item = make_page_item(index().find_exact(name, source), source) or raw_lookup_item(name, source)
	end
	local source = item.source
	search_source = search_source or source

	if is_valid() then
		close()
	end

	history().reset()
	if from_search and from_search ~= "" then
		history().push({ type = "search", pattern = from_search, source = search_source })
	end
	_current_page_name = nil
	_current_page_query = nil
	_current_page_source = nil
	_current_page_label = nil
	_current_timing_text = nil
	_current_sections = nil

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"

	local ui = vim.api.nvim_list_uis()[1]

	local w = config().options.viewer.width or 0.8
	local h = config().options.viewer.height or 0.6
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
			history().reset()
			_current_page_name = nil
			_current_page_query = nil
			_current_page_source = nil
			_current_page_label = nil
			_current_timing_text = nil
			_current_sections = nil
			state.win = nil
			state.buf = nil
		end,
	})

	load_page(item)
end

return M
