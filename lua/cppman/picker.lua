local M = {}

local util = require("cppman.util")

local AUTO_ORDER = { "snacks", "fzf-lua" }
local PROVIDERS = {
	snacks = {
		label = "snacks.nvim",
		module = "cppman.pickers.snacks",
	},
	["fzf-lua"] = {
		label = "fzf-lua",
		module = "cppman.pickers.fzf_lua",
	},
}

local function picker_options()
	local config = require("cppman.config")
	return config.options.picker or {}
end

local function load_backend(provider)
	local spec = PROVIDERS[provider]
	if not spec then
		return nil, "unknown picker provider: " .. tostring(provider)
	end

	local ok, backend = pcall(require, spec.module)
	if not ok then
		return nil, backend
	end
	return backend
end

function M.normalize_provider(provider)
	provider = provider or "auto"
	if provider == "fzf_lua" then
		return "fzf-lua"
	end
	if provider == "snacks.nvim" then
		return "snacks"
	end
	return provider
end

function M.provider_status(provider)
	provider = M.normalize_provider(provider)
	local spec = PROVIDERS[provider]
	if not spec then
		return {
			name = provider,
			label = tostring(provider),
			available = false,
			error = "expected one of: auto, snacks, fzf-lua",
		}
	end

	local backend, load_err = load_backend(provider)
	if not backend then
		return {
			name = provider,
			label = spec.label,
			available = false,
			error = tostring(load_err),
		}
	end

	local ok, available, err = pcall(backend.is_available)
	if not ok then
		return {
			name = provider,
			label = spec.label,
			available = false,
			error = tostring(available),
		}
	end

	return {
		name = provider,
		label = spec.label,
		available = available == true,
		error = err,
	}
end

function M.provider_statuses()
	local statuses = {}
	for _, provider in ipairs(AUTO_ORDER) do
		statuses[provider] = M.provider_status(provider)
	end
	return statuses
end

function M.resolve_provider(provider)
	provider = M.normalize_provider(provider or picker_options().provider or "auto")

	if provider == "auto" then
		for _, candidate in ipairs(AUTO_ORDER) do
			local status = M.provider_status(candidate)
			if status.available then
				return candidate
			end
		end
		return nil, "[cppman] no picker backend found (install folke/snacks.nvim or ibhagwan/fzf-lua)"
	end

	if not PROVIDERS[provider] then
		return nil,
			"[cppman] invalid picker provider: " .. tostring(provider) .. " (expected one of: auto, snacks, fzf-lua)"
	end

	local status = M.provider_status(provider)
	if status.available then
		return provider
	end

	return nil,
		"[cppman] picker provider " .. status.label .. " unavailable: " .. (status.error or "missing dependency")
end

function M.open(opts)
	opts = opts or {}

	local provider, provider_err = M.resolve_provider()
	if not provider then
		vim.notify(provider_err, vim.log.levels.ERROR)
		return
	end

	local config = require("cppman.config")
	local source = opts.source or config.options.source or "both"

	local index = require("cppman.index")
	local t0 = util.now_ms()
	local items = index.load(source)
	local load_ms = util.now_ms() - t0
	if #items == 0 then
		vim.notify("[cppman] no items loaded - check cppman and sqlite3 installation", vim.log.levels.ERROR)
		return
	end

	local backend = assert(load_backend(provider))
	backend.open(vim.tbl_extend("force", opts, {
		provider = provider,
		source = source,
		items = items,
		load_ms = load_ms,
	}))
end

return M
