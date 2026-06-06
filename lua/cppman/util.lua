-- Small shared helpers with no plugin state.
local M = {}

local uv = vim.uv or vim.loop

function M.now_ms()
	return uv.hrtime() / 1e6
end

-- Format an elapsed-milliseconds value for display.
-- nil means "no measurement" (e.g. an in-memory cache hit).
function M.format_ms(elapsed)
	if elapsed == nil then
		return "cached"
	end
	if elapsed < 10 then
		return string.format("%.1fms", elapsed)
	end
	return string.format("%dms", math.floor(elapsed + 0.5))
end

return M
