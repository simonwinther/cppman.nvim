local M = {}

local util = require("cppman.util")

local NBSP = vim.fn.nr2char(160)

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
		{ NBSP .. "search • " .. util.format_ms(load_ms), "Comment" },
		{ " ", "FloatTitle" },
	}
end

return M
