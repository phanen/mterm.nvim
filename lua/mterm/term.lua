---START INJECT class/term.lua

---@diagnostic disable: duplicate-type
---@class term.Term
---@field buf? integer
---@field opts term.Opts

---@class term.Opts
---@field cmd string[]
---@field cwd? string
---@field clear_env? boolean
---@field env? table
---@field on_exit? function
---@field on_stdout? function
---@field on_stderr? function
---@field auto_close? boolean
---@field height? integer
---@field width? integer
---@field b? { [string]: any } buf variable
---@field bo? vim.bo|{} buf option

local api, fn, uv = vim.api, vim.fn, vim.uv

---@type term.Opts|{}
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
M.__index = M

---@param opts? term.Opts|{}
---@return term.Term
M.new = function(opts)
  opts = require('mterm._').merge(defaults, opts or {})
  return setmetatable({ opts = opts }, { __index = M })
end

---@diagnostic disable-next-line: deprecated
local jobstart = fn.has('nvim-0.12') == 1 and fn.jobstart or fn.termopen

function M:spawn()
  local opts = self.opts
  self.buf = api.nvim_create_buf(false, true)
  if opts.b then vim.iter(opts.b):each(function(k, v) vim.b[self.buf][k] = v end) end
  if opts.bo then vim.iter(opts.bo):each(function(k, v) vim.bo[self.buf][k] = v end) end
  api.nvim_buf_call(self.buf, function()
    jobstart(opts.cmd, {
      term = fn.has('nvim-0.12') == 1 and true or nil,
      clear_env = opts.clear_env,
      cwd = opts.cwd,
      env = opts.env,
      on_stdout = opts.on_stdout,
      on_stderr = opts.on_stderr,
      height = opts.height,
      width = opts.width,
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
      if api.nvim_win_is_valid(w) then
        local ok, err = pcall(api.nvim_win_close, w, true)
        if not ok and err and not err:match('E444') then error(err) end
      end
    end
    api.nvim_buf_delete(self.buf, { force = true })
    pcall(api.nvim_del_augroup_by_name, 'my.term.' .. self.buf)
    self.buf = nil
  end
end

---@return integer?
function M:get_buf() return self.buf end

---@return integer?
function M:get_win()
  local win = fn.bufwinid(self.buf)
  if win ~= -1 then return win end
end

---@param buf integer
---@return [integer, integer]
local get_pos = function(buf)
  local view = vim.b[buf].term_view
  if not view then return { math.max(1, fn.prevnonblank(api.nvim_buf_line_count(buf))), 0 } end
  return { view.lnum, view.col }
end

---@return [integer, integer]
function M:get_cursor()
  local win = self:get_win()
  return win and api.nvim_win_get_cursor(win) or get_pos(assert(self.buf))
end

---@param pos [integer, integer]
function M:set_cursor(pos)
  local win = self:get_win()
  if win then api.nvim_win_set_cursor(win, pos) end
  vim.b[self.buf].term_view =
    vim.tbl_extend('force', vim.b[self.buf].term_view or {}, { lnum = pos[1], col = pos[2] })
end

---@param event vim.api.keyset.events|vim.api.keyset.events[]
---@param cb function
function M:on(event, cb)
  event = type(event) == 'string' and { event } or event ---@type vim.api.keyset.events[]
  event = vim.tbl_filter(function(e) return fn.exists('##' .. e) == 1 end, event)
  if #event == 0 then return end
  return api.nvim_create_autocmd(event, {
    buffer = self.buf,
    group = api.nvim_create_augroup('my.term.' .. self.buf, { clear = false }),
    callback = cb,
  })
end

---@return boolean
function M:is_running()
  return self.buf and fn.jobwait({ vim.bo[self.buf].channel }, 0)[1] == -1 and true or false
end

function M:redraw()
  if not self:is_running() then return end
  local pid = fn.jobpid(vim.bo[self.buf].channel)
  uv.kill(pid, uv.constants.SIGWINCH)
end

function M:kill()
  if not self:is_running() then return end
  fn.jobstop(vim.bo[self.buf].channel)
end

---@param cmd string
function M:send(cmd)
  if not self:is_running() then return end
  api.nvim_chan_send(vim.bo[self.buf].channel, cmd .. '\r')
end

local ns = api.nvim_create_namespace('nvim.terminal.prompt')

---@param count integer
---@param pos? [integer, integer]
---@return [integer, integer]
function M:get_prompt(count, pos)
  local buf = assert(self.buf)
  pos = pos or self:get_cursor() or { 1, 0 }
  local row, col = unpack(pos)
  local start = -1
  local end_ ---@type 0|-1
  if count > 0 then
    start = row
    end_ = -1
  elseif count < 0 then
    start = row - 2
    end_ = 0
  else
    error('wrong count')
  end

  if start < 0 then return { end_, 0 } end

  local extmarks = api.nvim_buf_get_extmarks(
    buf,
    ns,
    { start, col },
    end_,
    { limit = math.abs(count) }
  )
  if #extmarks > 0 then
    local extmark = assert(extmarks[math.min(#extmarks, math.abs(count))])
    return { extmark[2] + 1, extmark[3] }
  end

  return { end_, 0 }
end

function M:get_prompt_range()
  local prev_prompt = self:get_prompt(-1)
  local next_prompt = self:get_prompt(1, prev_prompt)
  if next_prompt[1] == -1 then
    next_prompt = prev_prompt
    prev_prompt = self:get_prompt(-1, next_prompt)
  end
  return prev_prompt[1], next_prompt[1]
end

---@param cb fun(line?: string, lnum: integer): boolean?
---@param wrap boolean?
---@param direction integer
function M:_dp_impl(cb, wrap, direction)
  local prev_prompt, next_prompt = self:get_prompt_range()
  local buf = assert(self:get_buf())
  local lnum = (unpack(self:get_cursor()))
  lnum = math.min((math.max(lnum, prev_prompt)), next_prompt)
  wrap = wrap ~= false
  local total_lines = next_prompt - prev_prompt + 1
  local searched = 0
  while searched < total_lines do
    lnum = lnum + direction
    if lnum > next_prompt then
      if not wrap then break end
      lnum = prev_prompt
    elseif lnum < prev_prompt then
      if not wrap then break end
      lnum = next_prompt
    end
    local line = api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
    if cb(line, lnum) then
      self:set_cursor({ lnum, select(2, unpack(self:get_cursor())) })
      return
    end
    searched = searched + 1
  end
end

---@param cb fun(line?: string, lnum: integer): boolean?
---@param wrap boolean?
function M:next_dp(cb, wrap) self:_dp_impl(cb, wrap, 1) end

---@param cb fun(line?: string, lnum: integer): boolean?
---@param wrap boolean?
function M:prev_dp(cb, wrap) self:_dp_impl(cb, wrap, -1) end

return M
