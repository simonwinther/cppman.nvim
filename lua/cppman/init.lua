local M = {}

function M.setup(opts)
  local config = require("cppman.config")
  config.setup(opts)

  vim.api.nvim_create_user_command("CPPMan", function(args)
    local term = args.args and vim.trim(args.args) or ""
    if #term > 1 then
      M.open_for(term)
    else
      M.search()
    end
  end, { nargs = "?" })

  local keymaps = config.options.keymaps

  if keymaps.open_under_cursor then
    vim.keymap.set("n", keymaps.open_under_cursor, function()
      M.open_for(vim.fn.expand("<cword>"))
    end, { silent = true, desc = "[C++] open under cursor" })
  end

  if keymaps.search then
    vim.keymap.set("n", keymaps.search, M.search, { silent = true, desc = "[C++] keyword search" })
  end
end

function M.search(opts)
  local picker = require("cppman.picker")
  local viewer = require("cppman.viewer")
  picker.open(vim.tbl_extend("force", opts or {}, {
    on_select = function(item, used_pattern)
      viewer.open(item.name, used_pattern)
    end,
  }))
end

function M.open_for(word)
  word = vim.trim((word or ""):gsub("%s+", " "))
  if word == "" then
    M.search()
    return
  end

  local config = require("cppman.config")
  local index = require("cppman.index")
  local viewer = require("cppman.viewer")

  local exact = index.find_exact(word, config.options.source)
  if exact then
    viewer.open(exact.name)
  else
    M.search({ search = word })
  end
end

-- Legacy aliases for any callers using the old API
M.input = M.search
M.open_cppman_for = M.open_for

return M
