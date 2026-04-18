local M = {}

M.defaults = {
  keymaps = {
    open_under_cursor = "<leader>cu",
    search = "<leader>ck",
  },
  source = "cppreference.com",
  index = {
    db_path = nil,
  },
  viewer = {
    width = 0.8,
    height = 0.6,
  },
}

M.options = vim.deepcopy(M.defaults)

local function pct_to_frac(v)
  if type(v) == "string" then
    local n = v:match("^(%d+)%%$")
    return n and (tonumber(n) / 100) or nil
  end
  return type(v) == "number" and v or nil
end

function M.setup(opts)
  opts = opts or {}
  -- Backwards compat: map old popup_width/popup_height string opts to viewer fractions
  if opts.popup_width and not (opts.viewer and opts.viewer.width) then
    opts.viewer = opts.viewer or {}
    opts.viewer.width = pct_to_frac(opts.popup_width) or M.defaults.viewer.width
  end
  if opts.popup_height and not (opts.viewer and opts.viewer.height) then
    opts.viewer = opts.viewer or {}
    opts.viewer.height = pct_to_frac(opts.popup_height) or M.defaults.viewer.height
  end
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts)
end

return M
