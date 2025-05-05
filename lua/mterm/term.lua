---@diagnostic disable: duplicate-doc-field, duplicate-set-field, duplicate-doc-alias, unused-local, undefined-field
local fn, api, uv = vim.fn, vim.api, vim.uv
local u = {
  merge = function(...)
    return vim.tbl_deep_extend('force', ...) -- nlua: ignore
  end,
}

---START INJECT class/term.lua

---@class term.Term
---@field buf? integer
---@field opts term.Opts

---@class term.Opts
---@field cmd? string[]
---@field cwd? string
---@field clear_env? boolean
---@field env? table
---@field on_exit? function
---@field on_stdout? function
---@field on_stderr? function
---@field auto_close? boolean
---@field b? table<string, any> buf variable
---@field bo? vim.bo buf option

---@type term.Opts
local defaults = {
  cmd = {
    _G.is_win and fn.executable('pwsh') == 1 and 'pwsh'
      or (fn.executable('fish') == 1 and 'fish' or vim.o.shell),
  },
  auto_close = false,
  clear_env = false,
}

---@class term.Term
local M = {}

---@param opts? term.Opts
---@return term.Term
M.new = function(opts)
  opts = u.merge(defaults, opts or {})
  return setmetatable({
    opts = opts,
  }, { __index = M })
end

---@diagnostic disable-next-line: deprecated
local jobstart = fn.has('nvim-0.11') == 1 and fn.jobstart or fn.termopen

function M:spawn()
  local opts = self.opts
  self.buf = api.nvim_create_buf(false, true)
  if opts.b then vim.iter(opts.b):each(function(k, v) vim.b[self.buf][k] = v end) end
  if opts.bo then vim.iter(opts.bo):each(function(k, v) vim.bo[self.buf][k] = v end) end
  api.nvim_buf_call(self.buf, function()
    jobstart(opts.cmd, {
      term = true,
      clear_env = opts.clear_env,
      cwd = opts.cwd,
      env = opts.env,
      on_stdout = opts.on_stdout,
      on_stderr = opts.on_stderr,
      on_exit = function(...)
        if opts.on_exit then opts.on_exit(...) end
        if opts.auto_close or vim.deep_equal(opts.cmd, defaults.cmd) then self:destory() end
      end,
    })
  end)
end

function M:destory() -- buf_del will also stop term job...
  if self.buf and api.nvim_buf_is_valid(self.buf) then
    for _, w in ipairs(fn.win_findbuf(self.buf)) do
      if api.nvim_win_is_valid(w) then api.nvim_win_close(w, true) end
    end
    api.nvim_buf_delete(self.buf, { force = true })
    self.buf = nil
  end
end

---@return integer
function M:get_buf() return self.buf end

---@return boolean
function M:is_running()
  return self.buf and fn.jobwait({ vim.bo[self.buf].channel }, 0)[1] == -1 and true or false
end

---@param cmd string
function M:send(cmd) api.nvim_chan_send(vim.bo[self.buf].channel, cmd .. '\r') end

return M
