-- Typed navigation stack.
-- Entries: { type = "page", name = "..." } | { type = "search", pattern = "..." }
-- The current page is NOT stored here — viewer.lua tracks that separately.
local M = {}

local stack = {}

function M.push(entry)
	stack[#stack + 1] = entry
end

function M.pop()
	return table.remove(stack)
end

function M.peek()
	return stack[#stack]
end

function M.size()
	return #stack
end

function M.reset()
	stack = {}
end

return M
