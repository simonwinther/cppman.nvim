-- Section/TOC parsing for rendered cppman pages. Pure: input is page lines, output
-- is a section index that the viewer uses for K-jump navigation.
local M = {}

function M.normalize_key(text)
	text = vim.trim((text or ""):lower())
	text = text:gsub("^%d+[%s%)]+", "")
	text = text:gsub("[%-‐]%s+", "")
	text = text:gsub("%s+", " ")
	return text
end

local function is_heading(line)
	return line ~= "" and line == line:upper() and line:find("%u") ~= nil
end
M.is_heading = is_heading

function M.build(lines)
	local sections = { ordered = {}, toc_start = nil, toc_end = nil }
	local description_line = nil
	local first_section_after_description = nil

	for i = 1, #lines do
		local line = lines[i]
		if is_heading(line) then
			local key = M.normalize_key(line)
			if key == "description" then
				description_line = i
			elseif key ~= "name" then
				sections.ordered[#sections.ordered + 1] = { key = key, line = i }
				if description_line and not first_section_after_description then
					first_section_after_description = i
				end
			end
		end
	end

	if description_line and first_section_after_description then
		for i = description_line + 1, first_section_after_description - 1 do
			if lines[i]:find("^%s*1[%s%)]") then
				sections.toc_start = i
				sections.toc_end = first_section_after_description - 1
				while sections.toc_end >= sections.toc_start and vim.trim(lines[sections.toc_end]) == "" do
					sections.toc_end = sections.toc_end - 1
				end
				break
			end
		end
	end

	return sections
end

return M
