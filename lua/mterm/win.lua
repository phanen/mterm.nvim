---@diagnostic disable: duplicate-doc-field, duplicate-set-field, duplicate-doc-alias, unused-local, undefined-field
local fn, api, uv = vim.fn, vim.api, vim.uv
local u = {
  merge = function(...)
    return vim.tbl_deep_extend('force', ...) -- nlua: ignore
  end,
}

---START INJECT class/win.lua

---@class win.Opts
---@field config vim.api.keyset.win_config
---@field w? table<string, any> win variable
---@field wo? vim.wo|{} win option

---@class win.Win
---@field win? integer
---@field ns_id? integer
---@field opts win.Opts
local M = {}

---@type win.Opts
local default = {
  config = {
    height = 0.95,
    width = 0.95,
    col = 0.5,
    row = 0.5,
    border = _G.border or 'single',
    relative = 'editor',
    style = 'minimal',
    zindex = 50,
  },
  ---@diagnostic disable-next-line: missing-fields
  wo = {
    winfixbuf = true,
    winhl = 'Normal:Normal',
  },
}

---@param opts vim.api.keyset.win_config
---@return vim.api.keyset.win_config
local normalize_opts = function(opts)
  local _col, _row = vim.o.columns, vim.o.lines
  local width = opts.width < 1 and math.ceil(_col * opts.width) or opts.width
  local height = opts.height < 1 and math.ceil(_row * opts.height - 4) or opts.height -- maybe tabline/statusline
  local col = opts.col < 1 and math.ceil((_col - width) * opts.col) or opts.col
  local row = opts.row < 1 and math.ceil((_row - height) * opts.row - 1) or opts.row
  return u.merge(opts, { width = width, height = height, col = col, row = row })
end

---@param win integer
---@param buf integer
local set_buf = function(win, buf)
  if fn.exists('&winfixbuf') == 1 and vim.wo[win].winfixbuf then
    vim.wo[win].winfixbuf = false
    api.nvim_win_set_buf(win, buf)
    vim.wo[win].winfixbuf = true
  else
    api.nvim_win_set_buf(win, buf)
  end
end

---@param opts? win.Opts
---@return win.Win
M.new = function(opts)
  return setmetatable({
    opts = u.merge(default, opts or {}),
  }, { __index = M })
end

function M:is_open() return self.win and api.nvim_win_is_valid(self.win) end

function M:is_open_in_curtab()
  return self:is_open() and api.nvim_get_current_tabpage() == api.nvim_win_get_tabpage(self.win)
end

---@param buf? integer
---@param opts? win.Opts
function M:update(buf, opts)
  if opts then self.opts = u.merge(self.opts, opts) end
  if not self:is_open() then return end
  if buf then set_buf(self.win, buf) end
  api.nvim_win_set_config(self.win, normalize_opts(self.opts.config))
end

function M:set_buf(buf) set_buf(self.win, buf) end

function M:get_buf() return api.nvim_win_get_buf(self.win) end

function M:get_win() return self.win end

---@return vim.api.keyset.win_config
function M:get_config() return normalize_opts(self.opts.config) end

---@param buf? integer
---@param opts? win.Opts
function M:open(buf, opts)
  opts = u.merge(self.opts, opts or {})
  if self:is_open_in_curtab() then
    self:update(buf, opts)
    return
  end

  if self:is_open() then self:close() end

  ---@cast buf integer
  self.win = api.nvim_open_win(buf, true, normalize_opts(opts.config))
  if opts.w then vim.iter(opts.w):each(function(k, v) vim.w[self.win][k] = v end) end
  if opts.wo then
    vim.iter(opts.wo):each(function(k, v)
      if fn.exists('&' .. k) == 1 then vim.wo[self.win][k] = v end
    end)
  end
  self.ns_id = api.nvim_create_augroup('u.win._' .. self.win, { clear = true })
  api.nvim_create_autocmd('VimResized', {
    group = self.ns_id,
    callback = function()
      if not self:is_open() then return true end
      api.nvim_win_set_config(self.win, normalize_opts(opts.config))
    end,
  })
end

function M:close()
  if self:is_open() then api.nvim_win_close(self.win, true) end
  if self.ns_id then api.nvim_del_augroup_by_id(self.ns_id) end
  self.win = nil
  self.ns_id = nil
end

return M
