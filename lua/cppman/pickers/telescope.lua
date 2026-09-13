local M = {}

local common = require("cppman.pickers.common")
local util = require("cppman.util")

function M.is_available()
	local ok = pcall(require, "telescope")
	if not ok then
		return false, "telescope.nvim not found"
	end
	local ok_plenary = pcall(require, "plenary")
	if not ok_plenary then
		return false, "plenary.nvim not found (required by telescope.nvim)"
	end
	local ok_pickers = pcall(require, "telescope.pickers")
	if not ok_pickers then
		return false, "telescope.nvim found but pickers module unavailable"
	end
	return true
end

-- Builds an entry_maker for telescope's finder. When the search spans both
-- sources we append a dimmed source badge for parity with the other backends;
-- the badge is display-only and is not part of the ordinal used for matching.
local function make_entry_maker(source)
	if source ~= "both" then
		return function(item)
			return {
				value = item,
				display = item.text,
				ordinal = item.text,
			}
		end
	end

	local entry_display = require("telescope.pickers.entry_display")
	local displayer = entry_display.create({
		separator = "",
		items = {
			{ remaining = true },
			{ remaining = true },
		},
	})

	return function(item)
		return {
			value = item,
			ordinal = item.text,
			display = function()
				return displayer({
					{ item.text, "Normal" },
					{ common.source_badge(item.source), "Comment" },
				})
			end,
		}
	end
end

function M.open(opts)
	opts = opts or {}
	local on_select = opts.on_select
	local on_back = opts.on_back
	local pattern = opts.search or ""

	local available, err = M.is_available()
	if not available then
		vim.notify("[cppman] picker provider telescope.nvim unavailable: " .. err, vim.log.levels.ERROR)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_set = require("telescope.actions.set")
	local action_state = require("telescope.actions.state")

	local config = require("cppman.config")
	local picker_opts = config.options.picker or {}
	local source = opts.source or config.options.source or "both"

	local prompt_title = "keyword search • " .. util.format_ms(opts.load_ms or 0)

	-- Caller-supplied telescope overrides win over our defaults (layout, theme,
	-- sorter, etc.), mirroring how the snacks/fzf-lua backends pass through
	-- picker_opts.snacks / picker_opts.fzf_lua.
	local base_opts = {
		previewer = false,
		results_title = on_back and "<C-t> back" or nil,
		layout_config = {
			width = picker_opts.width or 0.4,
			height = picker_opts.height or 0.4,
		},
	}
	local telescope_opts = vim.tbl_deep_extend("force", base_opts, vim.deepcopy(picker_opts.telescope or {}))

	pickers
		.new(telescope_opts, {
			prompt_title = prompt_title,
			default_text = pattern,
			finder = finders.new_table({
				results = opts.items or {},
				entry_maker = make_entry_maker(source),
			}),
			sorter = conf.generic_sorter(telescope_opts),
			attach_mappings = function(prompt_bufnr, map)
				action_set.select:replace(function()
					local entry = action_state.get_current_picker(prompt_bufnr):get_selection()
					-- Capture the live prompt input before closing so the viewer
					-- can record it in history, matching snacks/fzf-lua behavior.
					local used_pattern = action_state.get_current_line()
					actions.close(prompt_bufnr)
					if entry and entry.value and on_select then
						on_select(entry.value, used_pattern)
					end
				end)

				if on_back then
					local function go_back()
						actions.close(prompt_bufnr)
						vim.schedule(on_back)
					end
					-- Overrides telescope's default <C-t> (select_tab) for this picker.
					map("i", "<C-t>", go_back)
					map("n", "<C-t>", go_back)
				end

				return true
			end,
		})
		:find()
end

return M
