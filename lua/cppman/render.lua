-- Render pipeline: turns a cppman page name + width into rendered text lines.
-- Caches both successful renders and failures so re-renders / English-prose K presses
-- never re-spawn cppman. Owns no window state — viewer.lua handles UI.
local M = {}

local uv = vim.uv or vim.loop
local index = require("cppman.index")

local plugin_cache_dir = vim.fn.stdpath("cache") .. "/cppman_plugin"
local user_cache_home = vim.env.XDG_CACHE_HOME or (vim.fn.expand("~") .. "/.cache")
local _plugin_cache_dir_ready = false

local PAGE_CACHE_MAX = 64
local RESOLVE_CACHE_MAX = 256

-- LRU cache: { entries = { key = value }, order = { key1, key2, ... } }
-- Newest at the end. Evicts oldest when over max.
local function new_lru()
	return { entries = {}, order = {}, max = 0 }
end

local function lru_get(cache, key)
	return cache.entries[key]
end

local function lru_set(cache, key, value)
	if cache.entries[key] == nil then
		cache.order[#cache.order + 1] = key
		if #cache.order > cache.max then
			local oldest = table.remove(cache.order, 1)
			cache.entries[oldest] = nil
		end
	end
	cache.entries[key] = value
end

local page_cache = new_lru()
page_cache.max = PAGE_CACHE_MAX
local resolve_cache = new_lru()
resolve_cache.max = RESOLVE_CACHE_MAX
local _pager_script = nil

local function now_ms()
	return uv.hrtime() / 1e6
end

local function get_source(source)
	return index.get_sources(source)[1]
end

local function ensure_plugin_cache_dir()
	if not _plugin_cache_dir_ready then
		vim.fn.mkdir(plugin_cache_dir, "p")
		_plugin_cache_dir_ready = true
	end
end

local function get_config_dir(source)
	ensure_plugin_cache_dir()
	local dir = plugin_cache_dir .. "/config_" .. source
	local cppman_dir = dir .. "/cppman"
	if vim.fn.isdirectory(cppman_dir) == 0 then
		vim.fn.mkdir(cppman_dir, "p")
		local cfg_path = cppman_dir .. "/cppman.cfg"
		local cfg_content = "[Settings]\nSource = " .. source .. "\nUpdateManPath = false\nPager = vim\n"
		local f, err = io.open(cfg_path, "w")
		if f then
			f:write(cfg_content)
			f:close()
		else
			vim.notify("[cppman] failed to write " .. cfg_path .. ": " .. tostring(err), vim.log.levels.WARN)
		end
	end
	return dir
end

local function cppman_args(extra)
	local args = { "cppman" }
	for i = 1, #extra do
		args[#args + 1] = extra[i]
	end
	return args
end

local function run_cppman(source, args, stdin)
	return vim.system(args, {
		env = {
			XDG_CACHE_HOME = plugin_cache_dir,
			XDG_CONFIG_HOME = get_config_dir(get_source(source)),
		},
		stdin = stdin,
		text = true,
	}):wait()
end

local function normalize_page_name(name)
	return name:gsub("/", "_")
end

local function get_cached_page_path(name, source)
	source = get_source(source)
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
	local pager = index.cppman_paths().pager
	if pager then
		_pager_script = pager
		return _pager_script
	end
	for _, candidate in ipairs({
		"/usr/lib/cppman/lib/pager.sh",
		"/usr/local/lib/cppman/lib/pager.sh",
		"/usr/share/cppman/pager.sh",
	}) do
		if vim.fn.filereadable(candidate) == 1 then
			_pager_script = candidate
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

-- Single-pass: drop "Source set to" banner + leading blank lines.
local function strip_cppman_banner(lines)
	if not (lines[1] and lines[1]:find("Source set to", 1, true) == 1) then
		return lines
	end
	local first = 2
	while lines[first] == "" do
		first = first + 1
	end
	if first == 1 then
		return lines
	end
	local out = {}
	for i = first, #lines do
		out[i - first + 1] = lines[i]
	end
	return out
end

-- Single-pass: strip disambiguation menu header ("Please enter the selection: [1]").
local function strip_disambiguation(lines)
	for i = 1, #lines do
		if lines[i]:find("Please enter the selection:", 1, true) then
			local out = {}
			for j = i + 1, #lines do
				out[j - i] = lines[j]
			end
			return out
		end
	end
	return lines
end

-- Render a cppman page. Cached pages use cppman's pager.sh directly when
-- available; uncached pages fall back to the cppman CLI. Caches hits AND misses.
-- Returns (lines|nil, timing|nil). timing is nil on in-memory cache hits.
function M.render_page(name, width, source)
	source = get_source(source)
	local key = source .. "\0" .. name .. "\0" .. width
	local cached = lru_get(page_cache, key)
	if cached ~= nil then
		return cached or nil, nil
	end

	local t0 = now_ms()
	local external_t0 = now_ms()

	local stdout = nil
	local page_path = get_cached_page_path(name, source)
	if page_path then
		stdout = render_cached_page(page_path, width, name)
	end

	if not stdout then
		local res = run_cppman(source, cppman_args({ "--force-columns", tostring(width), name }), "1\n")
		if res.code ~= 0 or not res.stdout or res.stdout == "" then
			lru_set(page_cache, key, false)
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
	lines = strip_cppman_banner(lines)
	lines = strip_disambiguation(lines)

	if #lines == 0 then
		lru_set(page_cache, key, false)
		return nil, {
			cppman_ms = cppman_ms,
			our_ms = now_ms() - internal_t0,
			total_ms = now_ms() - t0,
		}
	end

	local our_ms = now_ms() - internal_t0
	lru_set(page_cache, key, lines)
	return lines, {
		cppman_ms = cppman_ms,
		our_ms = our_ms,
		total_ms = now_ms() - t0,
	}
end

function M.resolve_page(name, preferred, source)
	source = get_source(source)
	local key = source .. "\0" .. name .. "\0" .. (preferred or "")
	local cached = lru_get(resolve_cache, key)
	if cached ~= nil then
		return cached or nil
	end

	local res = run_cppman(source, cppman_args({ "-f", name }))
	if res.code ~= 0 then
		lru_set(resolve_cache, key, false)
		return nil
	end

	local preferred_lower = preferred and preferred:lower() or nil
	local page = nil

	for _, line in ipairs(vim.split(res.stdout or "", "\n", { plain = true })) do
		line = vim.trim(line)
		if line ~= "" and line:find("Source set to", 1, true) ~= 1 then
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
		lru_set(resolve_cache, key, false)
		return nil
	end

	lru_set(resolve_cache, key, page)
	return page
end

function M.reset()
	page_cache = new_lru()
	page_cache.max = PAGE_CACHE_MAX
	resolve_cache = new_lru()
	resolve_cache.max = RESOLVE_CACHE_MAX
	_pager_script = nil
end

return M
