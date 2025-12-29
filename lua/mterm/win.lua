local u = {
  with = require('mterm.with'),
  merge = function(...)
    return vim.tbl_deep_extend('force', ...) -- nlua: ignore
  end,
}

---START INJECT class/win.lua

local api, fn = vim.api, vim.fn

---@class win.Cfg: vim.api.keyset.win_config|{}
---@field height? number
---@field width? number
---@field col? number
---@field row? number

---@class win.Opts
---@field config win.Cfg
---@field w table<string, any> win variable
---@field wo vim.wo|{} win option
---@field layout win.layout

---@alias win.layout "float"|"bot"|"top"|"left"|"right"

---@class win.Win
---@field win? integer
---@field ns_id? integer
---@field config win.Cfg last applied config
---@field opts win.Opts
local M = {}
M.__index = M

local asinteger = tonumber ---@type fun(x: any): integer

---@type { [win.layout]: win.Cfg }
local layouts = {
  float = {
    height = 0.95,
    width = 0.95,
    col = 0.5,
    row = 0.5,
    border = _G.border or 'single',
    relative = 'editor',
    style = 'minimal',
    zindex = 50,
  },
  bot = {
    height = 0.3,
    split = 'below',
    style = 'minimal',
    win = -1,
  },
  top = {
    height = 0.5,
    split = 'above',
    style = 'minimal',
    win = -1,
  },
  left = {
    width = 0.4,
    split = 'left',
    style = 'minimal',
    win = -1,
  },
  right = {
    width = 0.4,
    split = 'right',
    style = 'minimal',
    win = -1,
  },
}

local pref = true and 'right' or 'left'
M.pref = pref

local with = vim._with or u.with ---@type fun(context: vim.context.mods, f: function): any

local minimal_wo = {
  number = true,
  relativenumber = true,
  cursorline = true,
  cursorcolumn = true,
  spell = true,
  list = true,
  signcolumn = true,
  foldcolumn = true,
  colorcolumn = true,
  winhl = true,
}

local get_wo = function(win)
  local ret = {}
  for name, _ in pairs(minimal_wo) do
    ret[name] = vim.wo[win or 0][name]
  end
  return ret
end

---@type win.Opts|{}
local default = {
  config = {},
  wo = {
    winfixbuf = true,
    winhl = 'Normal:Normal',
  },
  layout = 'float',
}

---@param opts win.Cfg
---@return vim.api.keyset.win_config
local normalize_opts = function(opts)
  local _col, _row = vim.o.columns, vim.o.lines
  local height, width = opts.height, opts.width
  width = width and width < 1 and math.ceil(_col * width) or asinteger(width)
  height = height and height < 1 and math.ceil(_row * height - 4) or asinteger(height) -- maybe tabline/statusline
  local col = opts.col and opts.col < 1 and math.ceil((_col - width) * opts.col) or opts.col
  local row = opts.row and opts.row < 1 and math.ceil((_row - height) * opts.row - 1) or opts.row
  ---@diagnostic disable-next-line: return-type-mismatch
  return u.merge(opts, { width = width, height = height, col = col, row = row })
end

---@param opts win.Cfg|{}
---@param layout win.layout
---@return win.Cfg
local normalize_layout = function(opts, layout)
  opts = u.merge(layouts[layout], opts)
  if layout ~= 'float' then
    opts.row = nil
    opts.col = nil
    opts.border = nil
    opts.relative = nil
    opts.zindex = nil
  else
    opts.split = nil
  end
  return opts
end

---@param win integer
---@param buf integer
local set_buf = function(win, buf)
  local wo = get_wo(win)
  if fn.exists('&winfixbuf') == 1 and vim.wo[win].winfixbuf then wo.winfixbuf = false end
  with({ win = win, wo = wo }, function() api.nvim_win_set_buf(win, buf) end)
end

---@param opts? win.Opts|{}
---@return win.Win
M.new = function(opts)
  opts = u.merge(default, opts or {}) ---@type win.Opts
  return setmetatable({
    opts = opts,
    config = normalize_layout(opts.config, opts.layout),
    layout = opts.layout,
  }, { __index = M })
end

---@return integer?
function M:valid() return self.win and api.nvim_win_is_valid(self.win) and self.win or nil end

---@return integer
function M:assert_win() return assert(self:valid()) end

---@param buf? integer
function M:focused(buf)
  return self.win == api.nvim_get_current_win() and (not buf or self:get_buf() == buf)
end

---@return_cast self.buf integer
function M:in_tabpage()
  local win = self:valid()
  return win and api.nvim_get_current_tabpage() == api.nvim_win_get_tabpage(win) or false
end

function M:focus() return self.win and api.nvim_set_current_win(self.win) or nil end

local win_set_config = function(win, config)
  if api.nvim_win_get_config(win).relative == '' then config.win = nil end
  api.nvim_win_set_config(win, config)
end

---@param buf? integer
---@param opts? win.Opts|{}
function M:update(buf, opts)
  if opts then self.opts = u.merge(self.opts, opts) end
  self.config = normalize_layout(self.opts.config, self.opts.layout)
  local win = self:valid()
  if not win then return end
  if buf then self:set_buf(buf) end
  win_set_config(win, normalize_opts(self.config))
end

function M:set_buf(buf) set_buf(self:assert_win(), buf) end

function M:get_buf() return api.nvim_win_get_buf(self:assert_win()) end

function M:get_win() return self.win end

---@return vim.api.keyset.win_config
function M:get_config() return normalize_opts(self.config) end

---@param buf integer
---@param focus? boolean
function M:open(buf, focus)
  focus = focus == nil or focus
  if self:in_tabpage() then
    self:update(buf)
    if focus then self:focus() end
    return
  elseif self:valid() then -- open in other tabpage
    self:close()
  end

  if self.opts.layout ~= 'float' then vim.cmd('ccl|lcl') end
  self.win = api.nvim_open_win(buf, focus, normalize_opts(self.config))
  vim.iter(self.opts.w or {}):each(function(k, v) vim.w[self.win][k] = v end)
  vim.iter(self.opts.wo or {}):each(function(k, v) --don't use vim.wo[k][0] for compat
    if fn.exists('&' .. k) == 1 then vim.wo[self.win][k] = v end
  end)
  self._win = self._win or self.win
  self.ns_id = api.nvim_create_augroup('u.win._' .. self._win, { clear = true })
  api.nvim_create_autocmd('BufReadPost', {
    pattern = 'quickfix',
    group = self.ns_id,
    callback = function()
      if not self:valid() then return true end
      if self:focused() or not self:in_tabpage() then return end
      self:close()
      return true
    end,
  })
  api.nvim_create_autocmd('WinEnter', {
    group = self.ns_id,
    callback = function()
      if not self:valid() then return true end
      if self.opts.layout == 'float' and not self:focused() and self:in_tabpage() then
        self:close()
        return true
      end
    end,
  })
  api.nvim_create_autocmd('VimResized', {
    group = self.ns_id,
    callback = function()
      if not self:valid() then return true end
      api.nvim_win_set_config(self.win, normalize_opts(self.config))
    end,
  })
end

function M:toggle_layout()
  local layout = self.opts.layout == 'float' and pref or 'float'
  if layout ~= 'float' then vim.cmd('ccl|lcl') end
  self:update(nil, { layout = layout })
end

function M:close()
  local win = self:valid()
  if win then api.nvim_win_close(win, true) end
  if self.ns_id then api.nvim_del_augroup_by_id(self.ns_id) end
  self.win = nil
  self.ns_id = nil
end

---@return boolean
function M:try_close()
  local in_tab = self:in_tabpage()
  self:close()
  return in_tab
end

function M:toggle(buf, focus)
  if self:close() then return end
  self:open(buf, focus)
end

return M
