local M = {}

local uv = vim.uv or vim.loop
local SOURCE_PRIORITY = { "cppreference.com", "cplusplus.com" }
local VALID_SOURCES = { ["cppreference.com"] = true, ["cplusplus.com"] = true, ["both"] = true }

local _cache = {}
local _exact_map = {}
local _db_path = nil

M.last_load_ms = nil

local function now_ms()
	return uv.hrtime() / 1e6
end

local function validate_source(source)
	if not VALID_SOURCES[source] then
		error(
			"[cppman] invalid source: "
				.. tostring(source)
				.. " (expected one of: cppreference.com, cplusplus.com, both)"
		)
	end
	return source
end

local function get_source_mode(source)
	if source ~= nil then
		return validate_source(source)
	end
	local config = require("cppman.config")
	return validate_source(config.options.source or SOURCE_PRIORITY[1])
end

function M.get_sources(source)
	source = get_source_mode(source)
	if source == "both" then
		return SOURCE_PRIORITY
	end
	return { source }
end

local function add_exact_item(map, item)
	local bucket = map[item.text_lower]
	if bucket then
		bucket[#bucket + 1] = item
	else
		map[item.text_lower] = { item }
	end
end

local function copy_exact_items(items)
	if not items then
		return {}
	end
	local copied = {}
	for i = 1, #items do
		copied[i] = items[i]
	end
	return copied
end

-- Spawn sqlite3 directly without a shell. Returns (lines, err).
local function run_sqlite(db_path, query)
	local res = vim.system({ "sqlite3", db_path, query }, { text = true }):wait()
	if res.code ~= 0 then
		return nil, (res.stderr ~= "" and res.stderr) or "sqlite3 exited " .. res.code
	end
	local out = res.stdout or ""
	if out == "" then
		return {}, nil
	end
	local lines = vim.split(out, "\n", { plain = true })
	if lines[#lines] == "" then
		lines[#lines] = nil
	end
	return lines, nil
end

local function validate_db(db_path, source)
	local rows, err = run_sqlite(db_path, string.format('SELECT COUNT(*) FROM "%s"', source))
	if err or not rows or #rows == 0 then
		return false
	end
	return (tonumber(rows[1]) or 0) > 0
end

local _cppman_base_dir = nil
local _cppman_base_dir_resolved = false
local function cppman_base_dir()
	if _cppman_base_dir_resolved then
		return _cppman_base_dir
	end
	_cppman_base_dir_resolved = true
	local res = vim.system(
		{ "python3", "-c", "import cppman, os; print(os.path.dirname(cppman.__file__))" },
		{ text = true }
	)
		:wait()
	if res.code == 0 then
		local base = vim.trim(res.stdout or "")
		if base ~= "" then
			_cppman_base_dir = base
		end
	end
	return _cppman_base_dir
end

-- Returns { db = path|nil, pager = path|nil } resolved from one python introspection.
local _cppman_paths = nil
function M.cppman_paths()
	if _cppman_paths then
		return _cppman_paths
	end
	local base = cppman_base_dir()
	local db, pager
	if base then
		for _, candidate in ipairs({ base .. "/lib/index.db", base .. "/index.db" }) do
			if vim.fn.filereadable(candidate) == 1 then
				db = candidate
				break
			end
		end
		for _, candidate in ipairs({ base .. "/lib/pager.sh", base .. "/pager.sh" }) do
			if vim.fn.filereadable(candidate) == 1 then
				pager = candidate
				break
			end
		end
	end
	_cppman_paths = { db = db, pager = pager }
	return _cppman_paths
end

local function find_packaged_db()
	local paths = M.cppman_paths()
	if paths.db then
		return paths.db
	end
	local fallbacks = {
		"/usr/lib/cppman/lib/index.db",
		"/usr/lib/cppman/index.db",
		"/usr/local/lib/cppman/lib/index.db",
		"/usr/local/lib/cppman/index.db",
		"/usr/share/cppman/index.db",
	}
	for _, path in ipairs(fallbacks) do
		if vim.fn.filereadable(path) == 1 then
			return path
		end
	end
	return nil
end

function M.resolve_db(source)
	if _db_path then
		return _db_path
	end

	source = M.get_sources(source)[1]

	local config = require("cppman.config")
	local opts = config.options.index or {}

	if opts.db_path then
		if vim.fn.filereadable(opts.db_path) == 1 then
			_db_path = opts.db_path
			return _db_path
		end
		vim.notify("[cppman] configured index.db_path not readable: " .. opts.db_path, vim.log.levels.WARN)
	end

	local local_db = vim.fn.expand("~/.cache/cppman/index.db")
	if vim.fn.filereadable(local_db) == 1 then
		if validate_db(local_db, source) then
			_db_path = local_db
			return _db_path
		end
		vim.notify(
			"[cppman] local ~/.cache/cppman/index.db is empty or invalid, using packaged DB",
			vim.log.levels.INFO
		)
	end

	local packaged = find_packaged_db()
	if packaged then
		_db_path = packaged
		return _db_path
	end

	return nil
end

local function load_single_source(source)
	if _cache[source] then
		return _cache[source]
	end

	local db = M.resolve_db(source)
	if not db then
		vim.notify("[cppman] no valid index.db found — check cppman installation", vim.log.levels.ERROR)
		return {}
	end

	local rows, err = run_sqlite(db, string.format('SELECT title FROM "%s"', source))
	if err then
		vim.notify("[cppman] index query failed: " .. err, vim.log.levels.ERROR)
		return {}
	end

	local items = {}
	local seen = {}
	local exact_map = {}

	for i = 1, #(rows or {}) do
		local title = vim.trim(rows[i])
		if title ~= "" and not seen[title] then
			seen[title] = true
			local lower = title:lower()
			local item = { text = title, text_lower = lower, name = title, source = source }
			items[#items + 1] = item
			add_exact_item(exact_map, item)
		end
	end

	-- Keyword aliases (alternate search terms linked to titles). CHAR(1) (ASCII SOH)
	-- is safe as a column separator — C++ names never contain control chars.
	local sep = string.char(1)
	local kw_rows = run_sqlite(
		db,
		string.format(
			'SELECT k.keyword || CHAR(1) || m.title FROM "%s_keywords" k JOIN "%s" m ON k.id = m.id',
			source,
			source
		)
	)
	if kw_rows then
		for i = 1, #kw_rows do
			local keyword, title = kw_rows[i]:match("^(.-)" .. sep .. "(.+)$")
			if keyword and title then
				keyword = vim.trim(keyword)
				title = vim.trim(title)
				if keyword ~= "" and not seen[keyword] then
					seen[keyword] = true
					local lower = keyword:lower()
					local item = { text = keyword, text_lower = lower, name = title, source = source }
					items[#items + 1] = item
					add_exact_item(exact_map, item)
				end
			end
		end
	end

	_cache[source] = items
	_exact_map[source] = exact_map
	return items
end

function M.load(source)
	source = get_source_mode(source)

	if _cache[source] then
		M.last_load_ms = nil
		return _cache[source]
	end

	local t0 = now_ms()
	if source == "both" then
		local items = {}
		local exact_map = {}
		local seen = {}
		for _, source_name in ipairs(M.get_sources(source)) do
			for _, item in ipairs(load_single_source(source_name)) do
				local dedupe_key = item.text_lower .. "\0" .. item.name:lower()
				if not seen[dedupe_key] then
					seen[dedupe_key] = true
					local merged = {
						text = item.text,
						text_lower = item.text_lower,
						name = item.name,
						source = item.source,
					}
					items[#items + 1] = merged
					add_exact_item(exact_map, merged)
				end
			end
		end
		_cache[source] = items
		_exact_map[source] = exact_map
	else
		load_single_source(source)
	end

	M.last_load_ms = now_ms() - t0
	return _cache[source] or {}
end

function M.find_exact_matches(name, source)
	source = get_source_mode(source)
	if not _exact_map[source] then
		M.load(source)
	end
	local map = _exact_map[source]
	return map and copy_exact_items(map[name:lower()]) or {}
end

function M.find_exact(name, source)
	local matches = M.find_exact_matches(name, source)
	return matches[1]
end

function M.reset()
	_cache = {}
	_exact_map = {}
	_db_path = nil
	_cppman_paths = nil
	_cppman_base_dir = nil
	_cppman_base_dir_resolved = false
	M.last_load_ms = nil
end

return M
