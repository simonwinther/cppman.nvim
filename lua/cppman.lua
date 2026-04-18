local Input = require("nui.input")
local Text = require("nui.text")
local event = require("nui.utils.autocmd").event
local Popup = require("nui.popup")

local M = {}

local defaults = {
	input_width = 20,
	popup_width = "80%",
	popup_height = "60%",
	keymaps = {
		open_under_cursor = "<leader>cu",
		search = "<leader>ck",
	},
}

local config = vim.tbl_deep_extend("force", {}, defaults)

local function tablelength(T)
	local count = 0
	for _ in pairs(T) do
		count = count + 1
	end
	return count
end

local stack = {}
local current_page = nil

local function normalize_search_term(text)
	return vim.trim(text:gsub("%s+", " "))
end

local function reload(manwidth, word_to_search)
	vim.bo.ro = false
	vim.bo.ma = true

	vim.api.nvim_buf_set_lines(0, 0, -1, true, {})

	-- always select the first result
	local cmd = string.format([[ 0r! echo 1 | cppman --force-columns %s '%s' ]], manwidth, word_to_search)
	vim.cmd(cmd) -- Set buffer with cppman contents

	vim.cmd("silent! 0,/Please enter the selection:/-1d|s/Please enter the selection: //e") -- Remove search results
	vim.cmd("0") -- Go to top of document

	vim.bo.ro = true
	vim.bo.ma = false
	vim.bo.mod = false

	vim.bo.keywordprg = "cppman"
	vim.bo.buftype = "nofile"
	vim.bo.filetype = "cppman"
end

local function followPage(word_to_search)
	word_to_search = normalize_search_term(word_to_search or "")
	if word_to_search == "" then
		return
	end

	if current_page ~= nil then
		table.insert(stack, current_page)
	end

	current_page = word_to_search

	local wininfo = vim.fn.getwininfo(vim.fn.win_getid())[1]
	local manwidth = wininfo.width - 4

	reload(manwidth, current_page)
end

local function loadNewPage()
	followPage(vim.fn.expand("<cWORD>"))
end

local function loadVisualSelection()
	local mode = vim.fn.mode()
	local start_pos
	local end_pos

	if mode == "v" or mode == "V" or mode == "\22" then
		start_pos = vim.fn.getpos("v")
		end_pos = vim.fn.getpos(".")
	else
		mode = vim.fn.visualmode()
		start_pos = vim.fn.getpos("'<")
		end_pos = vim.fn.getpos("'>")
	end

	local start_row = start_pos[2]
	local start_col = start_pos[3]
	local end_row = end_pos[2]
	local end_col = end_pos[3]

	if start_row > end_row or (start_row == end_row and start_col > end_col) then
		start_row, end_row = end_row, start_row
		start_col, end_col = end_col, start_col
	end

	local selection
	if mode == "V" then
		selection = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)
	else
		selection = vim.api.nvim_buf_get_text(0, start_row - 1, start_col - 1, end_row - 1, end_col, {})
	end

	local search_term = table.concat(selection, " ")
	vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
	vim.schedule(function()
		followPage(search_term)
	end)
end

local function backToPrevPage()
	if table.getn(stack) == 0 then
		return
	end

	current_page = table.remove(stack)

	local wininfo = vim.fn.getwininfo(vim.fn.win_getid())[1]
	local manwidth = wininfo.width - 4

	reload(manwidth, current_page)
end

M.setup = function(opts)
	config = vim.tbl_deep_extend("force", {}, defaults, opts or {})

	vim.api.nvim_create_user_command("CPPMan", function(args)
		if args.args ~= nil then
			if string.len(args.args) > 1 then
				M.open_cppman_for(args.args)
			else
				M.input()
			end
		else
			M.input()
		end
	end, { nargs = "?" })

	vim.keymap.set("n", config.keymaps.open_under_cursor, function()
		M.open_cppman_for(vim.fn.expand("<cword>"))
	end, { silent = true, desc = "[u]nder cursor" })

	vim.keymap.set("n", config.keymaps.search, function()
		M.input()
	end, { silent = true, desc = "[k]eyword search" })
end

M.input = function()
	local input = Input({
		position = "50%",
		zindex = 60,
		size = {
			width = config.input_width,
		},
		border = {
			padding = {
				left = 2,
				right = 2,
			},
			style = "rounded",
			text = {
				top = {
					{ " keyword ", "FloatBorder" },
					{ "search ", "Title" },
				},
				top_align = "center",
				bottom = {
					{ " enter ", "SpecialChar" },
					{ "to search ", "Comment" },
				},
				bottom_align = "right",
			},
		},
		win_options = {
			winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder",
		},
	}, {
		prompt = Text("> ", "Keyword"),
		default_value = "",
		on_close = function() end,
		on_submit = function(value)
			M.open_cppman_for(value)
		end,
	})

	-- mount/open the component
	input:mount()

	-- unmount component when cursor leaves buffer
	input:on(event.BufLeave, function()
		input:unmount()
	end)

	vim.keymap.set("n", "q", ":q!<cr>", { silent = true, buffer = true })
	vim.keymap.set("n", "<ESC>", ":q!<cr>", { silent = true, buffer = true })
end

-- Pops up a window containing the results of the search
M.open_cppman_for = function(word_to_search)
	local popup = Popup({
		enter = true,
		focusable = true,
		border = {
			style = "double",
			text = {
				top = "[cppman]",
				top_align = "center",
			},
		},
		position = "50%",
		size = {
			width = config.popup_width,
			height = config.popup_height,
		},
	})

	-- mount/open the component
	popup:mount()

	-- unmount component when cursor leaves buffer
	popup:on(event.BufLeave, function()
		popup:unmount()

		current_page = nil
		for i = 0, #stack do
			stack[i] = nil
		end
	end)

	-- Set content
	local wininfo = vim.fn.getwininfo(popup.winid)[1]
	local manwidth = wininfo.width - 4

	reload(manwidth, word_to_search)

	current_page = word_to_search

	vim.keymap.set("n", "q", ":q!<cr>", { silent = true, buffer = true })

	vim.keymap.set("n", "K", loadNewPage, { silent = true, buffer = true })
	vim.keymap.set("x", "K", loadVisualSelection, { silent = true, buffer = true })
	vim.keymap.set("n", "<C-]>", loadNewPage, { silent = true, buffer = true })
	vim.keymap.set("x", "<C-]>", loadVisualSelection, { silent = true, buffer = true })
	vim.keymap.set("n", "<2-LeftMouse>", loadNewPage, { silent = true, buffer = true })

	vim.keymap.set("n", "<C-T>", backToPrevPage, { silent = true, buffer = true })
	vim.keymap.set("n", "<RightMouse>", backToPrevPage, { silent = true, buffer = true })
end

return M
