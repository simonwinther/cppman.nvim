-- Typed navigation stacks (back + forward; Vim jump-list semantics).
-- Entries: { type = "page",   page, query, source, cursor = { row, col } }
--       or { type = "search", pattern, source }
-- `cursor` is optional and only meaningful for "page" entries — it's the cursor
-- position the user was at on that page just before navigating away.
-- The current page is NOT stored here — viewer.lua tracks that separately.
local M = {}

local back = {}
local forward = {}

function M.push(entry)
	back[#back + 1] = entry
end

function M.pop()
	return table.remove(back)
end

function M.peek()
	return back[#back]
end

function M.size()
	return #back
end

function M.forward_push(entry)
	forward[#forward + 1] = entry
end

function M.forward_pop()
	return table.remove(forward)
end

function M.forward_size()
	return #forward
end

-- Branching the navigation truncates forward, like Vim's jump list.
function M.forward_clear()
	forward = {}
end

function M.reset()
	back = {}
	forward = {}
end

return M
