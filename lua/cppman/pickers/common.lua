local M = {}

local NBSP = vim.fn.nr2char(160)

function M.format_timing(elapsed)
	if elapsed < 10 then
		return string.format("%.1fms", elapsed)
	end
	return string.format("%dms", math.floor(elapsed + 0.5))
end

function M.source_badge(source)
	if source == "cppreference.com" then
		return " [ref]"
	end
	if source == "cplusplus.com" then
		return " [c++]"
	end
	return ""
end

function M.item_label(item, source)
	if source == "both" then
		return item.text .. M.source_badge(item.source)
	end
	return item.text
end

function M.search_title(load_ms)
	return {
		{ "keyword", "Title" },
		{ NBSP .. "search • " .. M.format_timing(load_ms), "Comment" },
		{ " ", "FloatTitle" },
	}
end

return M
