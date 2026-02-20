---START INJECT mterm.lua

local api, fn, fs = vim.api, vim.fn, vim.fs
local M = {}

---@class mterm.Term :lru.Node, term.Term
---@field spawn function
---@field on_exit function
---@field kill function
---@field _exiting? boolean

local with = vim._with or require('mterm.with') ---@type fun(context: vim.context.mods, f: function): any

---@class mterm.Slots :lru.Lru
---@field hash table<lru.key, mterm.Term>
---@field head mterm.Term
local slots = require('mterm.lru').new()

---@type mterm.Term?
local curr

M.curr = function() return curr end

---@type win.Win
M.win = require('mterm.win').new({ config = { zindex = 100 } })

M.size = function() return slots.size end

local uuid = function()
  M.i = (M.i or 0) + 1
  return M.i
end

local build_winbar = function()
  return vim
    .iter(slots:pairs())
    :enumerate()
    :map(function(id, _key, term)
      local hl = curr == term and 'TabLineSel' or 'TabLine'
      return ('%%#%s# %s %%#TabLineFill#'):format(hl, id)
    end)
    :join('')
end

---@return [string, string][]
local build_title = function()
  return vim
    .iter(slots:pairs())
    :enumerate()
    :map(function(id, _key, term)
      local hl = curr == term and 'TabLineSel' or 'TabLine'
      return { (' %s '):format(id), hl }
    end)
    :totable()
end

local update_title = function()
  if M.size() == 0 or not M.win:valid() then return end -- last buf bdeleted
  local win = assert(M.win:get_win())
  if M.size() ~= 1 and M.win.opts.layout ~= 'float' then -- setlocal stl require laststatus~=3
    vim.wo[win].winbar = build_winbar()
  else
    vim.wo[win].winbar = ''
    pcall(api.nvim_win_set_config, win, { title = build_title() }) -- no border+ <11
  end
end

---@param opts term.Opts|{}
---@param key integer|string
---@param fake? boolean
---@return mterm.Term
local Term = function(opts, key, fake)
  if slots:get(key) then error('duplicated key: ' .. key) end
  local term = require('mterm.term').new(opts) ---@type mterm.Term
  function term:on_exit()
    local neighbor = slots:next_of(self) or slots:prev_of(self)
    slots:delete(self)
    M.switch(neighbor)
  end
  term.key = key
  slots:insert_after(curr or slots.head, term)
  if fake then return term end
  term:spawn()
  term:on(
    'CursorMoved',
    function(args) require('mterm.parse').render(args.buf, fn.line('.') - 1) end
  )
  term:on('TermRequest', function(args)
    if not (args.data.sequence or args.data):match('^\027]133;A') then return end
    local ns = api.nvim_create_namespace('linter.debugprint')
    local prev_prompt, next_prompt = term:get_prompt_range()
    local buf = assert(term:get_buf())
    local lines = api.nvim_buf_get_lines(buf, prev_prompt + 1, next_prompt, false)
    local bufdiags = require('mterm.parse').diags(lines)
    for diagbuf, diags in pairs(bufdiags) do
      vim.diagnostic.set(ns, diagbuf, diags)
    end
  end)
  return term
end

---@param buf? integer
---@param key integer|string
---@return mterm.Term
local Faketerm = function(buf, key)
  buf = (not buf or buf == 0) and api.nvim_get_current_buf() or buf
  local term = Term({}, key, true)
  term.buf = buf
  with({ buf = buf }, function() vim.cmd([[runtime! ftplugin/mterm.lua]]) end) -- need window-local map
  function term:spawn() error('wrong', vim.inspect(self)) end
  function term:is_running() return not self._exiting end
  local orig = term.on_exit
  local on_exit = function(self)
    if self._exiting then return end
    self._exiting = true
    orig(self)
  end
  term.kill = on_exit
  term.on_exit = on_exit
  api.nvim_create_autocmd('BufDelete', {
    buffer = term.buf,
    callback = function() on_exit(term) end,
  })
  return term
end

---@param term? mterm.Term
M.switch = function(term)
  if curr == term then return update_title() end
  curr = term
  if not M.win:valid() then return update_title() end -- when `:quit!`, win is not valid
  if not term then return M.close() end -- delete to empty
  M.win:set_buf(term:get_buf())
  update_title()
end

---@param term? mterm.Term
M.next = function(term)
  term = term or curr
  if not term then return end
  M.switch(assert(slots:next_of(term, true)))
end

---@param term? mterm.Term
M.prev = function(term)
  term = term or curr
  if not term then return end
  M.switch(assert(slots:prev_of(term, true)))
end

---@param buf integer
---@param name? string
---@return mterm.Term
M.add = function(buf, name)
  local term = Faketerm(buf, name or uuid())
  curr = curr or term
  update_title()
  return term
end

---@param term? mterm.Term
M.kill = function(term)
  term = term or curr
  if not term then return end
  term:kill()
end

---@param opts? term.Opts|{}
---@return mterm.Term
M.spawn = function(opts)
  local term ---@type mterm.Term
  opts = opts or {}
  local on_exit = opts.on_exit
  local config = M.win:get_config()
  opts = require('mterm._').merge(opts, {
    width = config.width,
    height = config.height and (config.height - (M.size() > 1 and 1 or 0)) or nil,
    on_exit = function(...)
      term:on_exit()
      if on_exit then on_exit(...) end
    end,
    bo = { ft = 'mterm' },
  })
  term = Term(opts, uuid())
  curr = curr or term
  update_title()
  return term
end

---@param term? mterm.Term
---@param focus? boolean
---@param opts? win.Opts|{}
M.open = function(term, focus, opts)
  term = term or curr or M.spawn()
  M.win:update(nil, opts)
  M.win:open(assert(term:get_buf()), focus)
  M.switch(term)
  update_title()
end

M.close = function() M.win:close() end

---@param term? mterm.Term
---@param focus? boolean default true
M.toggle = function(term, focus)
  term = term or curr
  if term == curr and M.win:try_close() then return end
  M.open(term, focus) -- not open/reopen in curtab/term change buf
end

M.toggle_layout = function()
  M.win:toggle_layout()
  update_title()
end

---@param term? mterm.Term
M.toggle_focus = function(term)
  local buf = term and term:get_buf() or nil
  if M.win:focused(buf) then
    local win = fn.win_getid(fn.winnr('#'))
    vim.cmd.wincmd(win ~= 0 and 'p' or 'w')
  else
    M.open(term)
  end
end

---@param term? mterm.Term
M.toggle_or_focus = function(term)
  if M.win.opts.layout ~= 'float' then
    M.toggle_focus(term)
  else
    M.toggle(term)
  end
end

---@param cmd string
---@param term? mterm.Term
M.send = function(cmd, term)
  term = term or curr or M.spawn()
  term:send(cmd)
end

---@param key string
---@param term? mterm.Term
M.send_key = function(key, term)
  term = term or curr or M.spawn()
  local win = M.win:get_win()
  if not win then return end
  with({ win = win, noautocmd = true }, function()
    if api.nvim_get_mode().mode == 't' then
      vim.cmd.stopinsert()
      vim.schedule(function()
        with({ win = win, noautocmd = true }, function() vim.cmd.norm(vim.keycode(key)) end)
      end)
      return
    end
    vim.cmd.norm(vim.keycode(key))
  end)
  term:set_cursor(api.nvim_win_get_cursor(win))
end

---@param term? mterm.Term
M.next_dp = function(term)
  term = term or assert(curr)
  local buf = assert(term:get_buf())
  term:next_dp(function(line, lnum)
    local ctx = require('mterm.parse').from_line(line)
    if not require('mterm.parse').render(buf, lnum - 1, ctx) then return end
    require('mterm.gof').term_edit(ctx)
    return true
  end)
end

---@param term? mterm.Term
M.prev_dp = function(term)
  term = term or assert(curr)
  local buf = assert(term:get_buf())
  term:prev_dp(function(line, lnum)
    local ctx = require('mterm.parse').from_line(line)
    if not require('mterm.parse').render(buf, lnum - 1, ctx) then return end
    require('mterm.gof').term_edit(ctx)
    return true
  end)
end

M.is = function(pat) return curr and table.concat(curr.opts.cmd, ' '):match(pat) end

M.is_opencode = function() return M.is('opencode') end

M.opencode = function()
  ---@mod 'opencode'
  ---@class opencode.provider.Mterm : opencode.Provider
  ---@field opts term.Opts
  ---@field term mterm.Term
  local O = {}
  O.__index = O
  O.name = 'mterm' ---@diagnostic disable
  ---@class opencode.provider.mterm.Opts : term.Opts
  ---@param opts? opencode.provider.mterm.Opts
  ---@return opencode.provider.Mterm
  function O.new(opts) return setmetatable({ opts = opts or {} }, O) end
  function O.health() return true end
  function O:_get()
    local opts =
      require('mterm._').merge(self.opts, { cmd = { 'sh', '-c', self.cmd }, auto_close = true })
    self.term = self.term and self.term:is_running() and self.term or M.spawn(opts)
    return self.term
  end
  function O:toggle() M.toggle_or_focus(self:_get()) end
  function O:start() M.open(self:_get()) end
  function O:stop()
    if not self.term then return end
    self.term:kill()
    self.term = nil
  end ---@diagnostic enable
  return O
end

---@param chan integer
---@return boolean?
M.is_shell = function(chan)
  if vim.bo.ft == 'fzf' then return false end
  local is_running = fn.jobwait({ chan }, 0)[1] == -1
  if not is_running then return true end
  local info = api.nvim_get_chan_info(chan)
  local cmd = info.argv[1]
  local is_shell = cmd:match('%/fish$')
    or cmd:match('%/bash$')
    or cmd:match('%/zsh$')
    or cmd:match('%/sh$')
  if not is_shell then return false end
  local children = api.nvim_get_proc_children(fn.jobpid(chan))
  local dbg = {}
  local only_has_atuin_bg_child = vim.iter(children):all(function(pid)
    local out = vim.system({ 'ps', 'h', '-o', 'command', '-p', pid }):wait().stdout
    out = assert(out):gsub('\n', '')
    local ok = #out > 0 and out:match(vim.pesc('[atuin] <defunct>'))
      or out:match(vim.pesc('atuin history end --exit'))
    if not ok then dbg[#dbg + 1] = out end
    return not not ok
  end)
  if not only_has_atuin_bg_child then pp(dbg) end
  return only_has_atuin_bg_child
end

local LOCK = nil
---@param is_rpc? boolean
M.clear = function(is_rpc)
  api.nvim_buf_clear_namespace(0, api.nvim_create_namespace('nvim.terminal.prompt'), 0, -1)
  if require('mterm._').has_version('v0.12.0-dev-2239+ge254688016') then return end
  if LOCK then return end
  LOCK = true
  local chan = vim.bo.channel
  if not is_rpc and not M.is_shell(chan) then
    LOCK = false
    return api.nvim_chan_send(chan, vim.keycode '<c-l>')
  end
  if vim.bo.ft ~= 'mterm' then
    api.nvim_win_set_buf(0, api.nvim_create_buf(false, true))
    fn.jobstart({ vim.o.shell }, { term = true })
  else
    M.spawn()
    M.next()
  end
  fn.jobstop(chan)
  LOCK = false
end

local git_root = function()
  local bufname = fn.bufname()
  if bufname:match('oil://') then
    local _, dir = require('oil.util').parse_url(bufname)
    if _ then return dir end
  end
  if vim.b.gitsigns_status_dict then return vim.b.gitsigns_status_dict.root end
  if api.nvim_win_get_config(0).relative ~= '' and vim.bo.bt == 'nofile' then
    local altroot = vim.b[fn.bufnr('#')].gitsigns_status_dict
    if altroot then return altroot end
  end
  return fs.root(0, '.git')
end

---@type { [string]: mterm.Term? }
local TERMS = {}
M.lazygit = function(path)
  local cwd = git_root()
  if not cwd then return end
  local opts = {
    cmd = not path and { 'lazygit' } or { 'lazygit', '--filter', path },
    cwd = cwd,
    auto_close = true,
  }
  local key = vim.inspect(opts)
  local term = TERMS[key]
  local is_init = not term or not term:is_running()
  if is_init then TERMS[key] = M.spawn(opts) end
  local send = (function()
    if path then return false end
    local cword = fn.expand('<cword>'):match('^%x%x%x%x%x%x')
    if cword then
      vim.cmd [[fclose!]]
      return '4/' .. cword
    end
    local relpath = fs.relpath(cwd, fn.bufname())
    if not relpath then return end
    if relpath == '.' then relpath = '' end
    return '2/' .. relpath
  end)()
  M.open(TERMS[key])
  if not send then return end
  vim.defer_fn(function() M.send(send, TERMS[key]) end, 100)
end

return M
