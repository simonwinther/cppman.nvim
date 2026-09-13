vim.opt.runtimepath:append(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.getcwd() .. "/.tests/deps/plenary.nvim")
vim.opt.runtimepath:append(vim.fn.getcwd() .. "/.tests/deps/telescope.nvim")
vim.o.columns = 120
vim.o.lines = 40
vim.cmd("runtime plugin/telescope.lua")

require("telescope").setup({ defaults = { cache_picker = false } })

local cppman = require("cppman")
local backend = require("cppman.pickers.telescope")
local picker = require("cppman.picker")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local items = {
	{ text = "std::vector", page = "std::vector", query = "vector", source = "cppreference.com" },
	{ text = "std::vector", page = "std::vector", query = "vector", source = "cplusplus.com" },
}

local function wait_for_results(count)
	local prompt_bufnr = vim.api.nvim_get_current_buf()
	local current = action_state.get_current_picker(prompt_bufnr)
	local completed = false
	current:register_completion_callback(function()
		completed = true
	end)
	assert(
		vim.wait(3000, function()
			return completed and current.manager:num_results() == count
		end, 10),
		"Telescope did not finish finding results"
	)
	return prompt_bufnr, current
end

local function mapped_action(prompt_bufnr, mode, key)
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(prompt_bufnr, mode)) do
		if mapping.lhs == key then
			assert(type(mapping.callback) == "function", "expected a callback for " .. key)
			return mapping.callback
		end
	end
	error("missing mapping: " .. mode .. " " .. key)
end

cppman.setup({ picker = { provider = "telescope" } })
assert(picker.resolve_provider("auto") == "telescope", "auto should resolve to the installed Telescope backend")
assert(picker.resolve_provider("telescope.nvim") == "telescope", "Telescope alias did not resolve")

for _, source in ipairs({ "both", "cppreference.com" }) do
	for _, selection_action in ipairs({ "select_default", "select_horizontal", "select_vertical", "select_tab" }) do
		local selected
		backend.open({
			source = source,
			items = items,
			search = "vec",
			on_select = function(item, pattern)
				selected = { item = item, pattern = pattern }
			end,
		})
		local prompt_bufnr, current = wait_for_results(2)
		for i, item in ipairs(items) do
			local entry = current.manager:get_entry(i)
			assert(entry.value == item, "same-name results must keep their source identity")
			assert(entry.ordinal == item.text, "source badges must not affect matching")
			local display = type(entry.display) == "function" and entry.display() or entry.display
			local badge = source == "both" and (i == 1 and " [ref]" or " [c++]") or ""
			assert(display == item.text .. badge, "incorrect source badge")
		end
		current:set_selection(current:get_row(2))
		local search_updated = false
		current:register_completion_callback(function()
			search_updated = true
		end)
		current:set_prompt("vector")
		assert(
			vim.wait(3000, function()
				return search_updated and action_state.get_current_line() == "vector"
			end, 10),
			"Telescope did not update the search"
		)
		local expected_item = action_state.get_selected_entry().value
		actions[selection_action](prompt_bufnr)
		assert(
			selected and selected.item == expected_item,
			selection_action .. " did not select the documentation entry"
		)
		assert(selected.pattern == "vector", "selection must preserve the edited search")
		assert(not vim.api.nvim_buf_is_valid(prompt_bufnr), "selection did not close the picker")
	end
end

for _, mode in ipairs({ "i", "n" }) do
	local went_back = false
	backend.open({
		items = items,
		on_back = function()
			went_back = true
		end,
		on_select = function()
			error("back must not select a result")
		end,
	})
	local prompt_bufnr = wait_for_results(2)
	mapped_action(prompt_bufnr, mode, "<C-T>")()
	assert(
		vim.wait(1000, function()
			return went_back
		end, 10),
		"back mapping did not run in " .. mode .. " mode"
	)
	assert(not vim.api.nvim_buf_is_valid(prompt_bufnr), "back did not close the picker")
end

local custom_mapping_called = false
local attached = false
cppman.setup({
	picker = {
		provider = "telescope",
		telescope = require("telescope.themes").get_dropdown({
			prompt_title = "C++ docs",
			layout_config = { width = 70, height = 15 },
			attach_mappings = function(_, map)
				attached = true
				map("n", "<C-Y>", function()
					custom_mapping_called = true
				end)
				return true
			end,
		}),
	},
})
local selected_with_overrides = false
backend.open({
	items = items,
	on_select = function()
		selected_with_overrides = true
	end,
})
local prompt_bufnr, current = wait_for_results(2)
assert(current.prompt_title == "C++ docs", "prompt title override was ignored")
assert(current.layout_strategy == "center", "dropdown theme was ignored")
assert(current.layout_config.width == 70 and current.layout_config.height == 15, "layout overrides were ignored")
assert(attached, "custom attach_mappings did not run")
mapped_action(prompt_bufnr, "n", "<C-Y>")()
assert(custom_mapping_called, "custom mapping did not run")
actions.select_default(prompt_bufnr)
assert(selected_with_overrides, "custom mappings broke documentation selection")

cppman.setup({ picker = { provider = "telescope" } })
for _, search in ipairs({ "vec", "no_matching_documentation" }) do
	backend.open({
		items = items,
		search = search,
		on_select = function()
			error("empty results must not select a page")
		end,
	})
	if search == "vec" then
		local _, active_picker = wait_for_results(2)
		active_picker:set_prompt("no_matching_documentation")
	end
	prompt_bufnr = wait_for_results(0)
	actions.select_default(prompt_bufnr)
	assert(not vim.api.nvim_buf_is_valid(prompt_bufnr), "empty selection did not close the picker")
end

local loaded_plenary = package.loaded.plenary
local preload_plenary = package.preload.plenary
package.loaded.plenary = nil
package.preload.plenary = function()
	error("plenary is not installed")
end
local available, dependency_error = backend.is_available()
assert(not available and dependency_error:find("plenary.nvim", 1, true), "missing Plenary was not reported")
local notification
local notify = vim.notify
vim.notify = function(message)
	notification = message
end
backend.open({ items = items })
assert(
	notification and notification:find("plenary.nvim", 1, true),
	"opening without Plenary must report the dependency"
)
vim.notify = notify
package.loaded.plenary = loaded_plenary
package.preload.plenary = preload_plenary

print("Telescope picker tests passed")
vim.cmd("qa!")
