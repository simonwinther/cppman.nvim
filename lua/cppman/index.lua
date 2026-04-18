local M = {}

local uv = vim.uv or vim.loop

local _cache = {}
local _lower_map = {}
local _db_path = nil

M.last_load_ms = nil

local function now_ms()
	return uv.hrtime() / 1e6
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

local function find_packaged_db()
	local res = vim.system(
		{ "python3", "-c", "import cppman, os; print(os.path.dirname(cppman.__file__))" },
		{ text = true }
	)
		:wait()
	if res.code == 0 then
		local base = vim.trim(res.stdout or "")
		if base ~= "" then
			for _, candidate in ipairs({ base .. "/lib/index.db", base .. "/index.db" }) do
				if vim.fn.filereadable(candidate) == 1 then
					return candidate
				end
			end
		end
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

function M.load(source)
	local config = require("cppman.config")
	source = source or config.options.source or "cppreference.com"

	if _cache[source] then
		M.last_load_ms = nil
		return _cache[source]
	end

	local t0 = now_ms()

	local db = M.resolve_db(source)
	if not db then
		M.last_load_ms = nil
		vim.notify("[cppman] no valid index.db found — check cppman installation", vim.log.levels.ERROR)
		return {}
	end

	local rows, err = run_sqlite(db, string.format('SELECT title FROM "%s"', source))
	if err then
		M.last_load_ms = nil
		vim.notify("[cppman] index query failed: " .. err, vim.log.levels.ERROR)
		return {}
	end

	local items = {}
	local seen = {}
	local lower_map = {}

	for i = 1, #(rows or {}) do
		local title = vim.trim(rows[i])
		if title ~= "" and not seen[title] then
			seen[title] = true
			local lower = title:lower()
			local item = { text = title, text_lower = lower, name = title, source = source }
			items[#items + 1] = item
			lower_map[lower] = item
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
					lower_map[lower] = item
				end
			end
		end
	end

	_cache[source] = items
	_lower_map[source] = lower_map
	M.last_load_ms = now_ms() - t0
	return items
end

function M.find_exact(name, source)
	local config = require("cppman.config")
	source = source or config.options.source or "cppreference.com"
	if not _lower_map[source] then
		M.load(source)
	end
	local map = _lower_map[source]
	return map and map[name:lower()] or nil
end

function M.reset()
	_cache = {}
	_lower_map = {}
	_db_path = nil
	M.last_load_ms = nil
end

return M
