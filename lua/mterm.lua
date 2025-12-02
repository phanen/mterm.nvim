local fn, api, uv = vim.fn, vim.api, vim.uv
local u = {
  class = {
    lru = require('mterm.lru').new,
    term = require('mterm.term').new,
    win = require('mterm.win').new,
  },
  parse = require('mterm.parse'),
  merge = function(...)
    return vim.tbl_deep_extend('force', ...) -- nlua: ignore
  end,
}

---START INJECT ./mterm.lua

local M = {}

---@class mterm.Node : lru.Node, {}
---@field term term.Term

---@class mterm.Slots : lru.Lru, {}
---@field hash table<lru.key, mterm.Node>
local slots = u.class.lru {}

---@type mterm.Node?
local curr = nil

---@type win.Win
M.win = u.class.win({ config = { zindex = 100 } })

M.get_key = function()
  M.i = (M.i or 0) + 1
  return M.i
end

M.is_empty = function() return not curr end

local update_title = function()
  local size = slots.size
  if
    not M.win:is_open() or size == 0 -- last buf bdeleted
  then
    return
  end
  local win = M.win:get_win()
  if size > 1 and M.win.opts.layout == 'bot' then -- setlocal stl require laststatus~=3
    vim.wo[win].winbar = vim
      .iter(slots:pairs())
      :enumerate()
      :map(function(id, _key, node)
        local hl = curr == node and 'TabLineSel' or 'TabLine'
        return ('%%#%s# %s %%#TabLineFill#'):format(hl, id)
      end)
      :join('')
    return
  end
  vim.wo[win].winbar = ''
  local title = vim
    .iter(slots:pairs())
    :enumerate()
    :map(function(id, _key, node)
      local hl = curr == node and 'TabLineSel' or 'TabLine'
      return { (' %s '):format(id), hl }
    end)
    :totable()
  if win then pcall(api.nvim_win_set_config, win, { title = title }) end
end

---@param node mterm.Node
local switch_to = function(node)
  curr = node
  if not M.win:is_open() then return end
  local buf = node.term:get_buf()
  M.win:set_buf(buf)
  update_title() -- why we need it here?
end

---@param node? mterm.Node
M.next = function(node)
  node = node or assert(curr)
  local node0 = slots:next_of(node)
  if not node0 then node0 = slots.head.next end
  if node0 == node then return end
  switch_to(node0)
end

---@param node? mterm.Node
M.prev = function(node)
  node = node or assert(curr)
  local node0 = slots:prev_of(node)
  if not node0 then node0 = slots.head.prev end
  if node0 == curr then return end
  switch_to(node0)
end

---@param opts? term.Opts
---@return mterm.Node
M.spawn = function(opts)
  opts = opts or {}
  local node ---@type mterm.Node
  local default = {
    width = M.win:get_config().width,
    height = assert(M.win:get_config().height) - (slots.size > 1 and 1 or 0),
    on_exit = function(...)
      local near_node = slots:next_of(node) or slots:prev_of(node)
      if opts.on_exit then opts.on_exit(...) end
      slots:delete(node)
      if near_node then
        switch_to(near_node)
      else
      end
      curr = near_node
      update_title()
    end,
    bo = { ft = 'mterm' },
  }
  ---@type mterm.Node
  node = {
    key = M.get_key(),
    term = u.class.term(u.merge(opts, default)),
  }
  slots:insert_after(curr or slots.head, node)
  curr = curr or node
  update_title()
  node.term:spawn()
  M._attach_render(node)
  M._attach_linter(node)
  return node
end

---@param node? mterm.Node
---@param focus? boolean
---@param opts? win.Opts|{}
M.open = function(node, focus, opts)
  ---@type mterm.Node
  node = node or curr or M.spawn()
  M.win:update(nil, opts)
  M.win:open(node.term:get_buf(), focus)
  curr = node
  update_title()
end

---@return boolean?
M.close = function()
  if M.win:is_open_in_curtab() then
    M.win:close()
    return true
  end
end

---@param node? mterm.Node
M.toggle = function(node)
  if M.close() then return end
  M.open(node)
end

M.toggle_layout = function()
  M.win:toggle_layout()
  update_title()
end

M.toggle_focus = function()
  if M.win:is_focused() then
    local win = fn.win_getid(fn.winnr('#'))
    vim.cmd.wincmd(win ~= 0 and 'p' or 'w')
  elseif M.win:is_open_in_curtab() then
    M.win:focus()
  else
    M.open()
  end
end

M.smart_toggle = function()
  if M.win.opts.layout ~= 'float' then
    M.toggle_focus()
  else
    M.toggle()
  end
end

---@param cmd string
---@param node? mterm.Node
M.send = function(cmd, node)
  node = node or curr or M.spawn()
  vim.defer_fn(function() node.term:send(cmd) end, 100)
end

---@param key string
---@param node? mterm.Node
M.send_key = function(key, node)
  node = node or curr or M.spawn()
  local win = M.win.win
  if not win then return end
  api.nvim_win_call(win, function() vim.cmd.norm(vim.keycode(key)) end)
  node.term:set_cursor(api.nvim_win_get_cursor(win))
end

local mark ---@type integer?
local myns = api.nvim_create_namespace('my.nvim.terminal.prompt')

---@param buf integer extmark buf
---@param lnum integer extmark lnum
---@param ctx? parse.ParseLineResult
---@return boolean?
local render = function(buf, lnum, ctx)
  ctx = ctx or u.parse.from_line(api.nvim_buf_get_lines(buf, lnum, lnum + 1, false)[1])
  if mark then
    pcall(api.nvim_buf_del_extmark, buf, myns, mark)
    mark = nil
  end
  if not ctx.prefix then return end
  local opts = {
    virt_text_pos = 'overlay',
    virt_text = {
      { ctx.prefix, 'DiagnosticVirtualTextHint' },
      { ctx.filename .. ':' .. ctx.lnum, 'DiagnosticVirtualTextInfo' },
      { ctx.suffix, 'DiagnosticVirtualTextWarn' },
    },
  }
  mark = api.nvim_buf_set_extmark(buf, myns, lnum, 0, opts)
  return true
end

---@param ctx? parse.ParseLineResult
---@param focus? boolean
M.gotofile = function(ctx, focus)
  ctx = ctx or u.parse.from_line()
  local win = vim.bo.filetype ~= 'mterm' and api.nvim_get_current_win()
    or fn.win_getid((fn.winnr('#')))
  if not ctx.filename or win == 0 then return '<c-w>gF' end
  vim.schedule(function()
    local buf = api.nvim_win_get_buf(win)
    local should_focus = focus
    vim._with({ win = win, buf = buf }, function()
      if vim.fs.abspath(fn.bufname()) ~= vim.fs.abspath(ctx.filename) then
        if not pcall(vim.cmd.buffer, ctx.filename) then vim.cmd.edit(ctx.filename) end
        should_focus = false
      end
      if ctx.lnum and fn.line('.', win) ~= tonumber(ctx.lnum) then ---@diagnostic disable-next-line: param-type-mismatch
        fn.cursor(ctx.lnum, tonumber(ctx.col) or 0)
        should_focus = false
      end
      vim.cmd('norm! zz')
    end)
    if should_focus and vim.bo.filetype == 'mterm' then M.smart_toggle() end
  end)
  return '<ignore>'
end

---@param node? mterm.Node
M.next_dp = function(node)
  local term = (node or assert(curr)).term
  local buf = assert(term:get_buf())
  term:next_dp(function(line, lnum)
    local ctx = u.parse.from_line(line)
    if render(buf, lnum - 1, ctx) then
      M.gotofile(ctx)
      return true
    end
  end)
end

---@param node? mterm.Node
M.prev_dp = function(node)
  local term = (node or assert(curr)).term
  local buf = assert(term:get_buf())
  term:prev_dp(function(line, lnum)
    local ctx = u.parse.from_line(line)
    if render(buf, lnum - 1, ctx) then
      M.gotofile(ctx)
      return true
    end
  end)
end

---@param node mterm.Node
M._attach_render = function(node)
  node.term:on('CursorMoved', function(args) render(args.buf, fn.line('.') - 1) end)
end

---@param node mterm.Node
M._attach_linter = function(node)
  local term = node.term
  local buf = assert(term:get_buf())
  local ns = api.nvim_create_namespace('linter.debugprint')
  if fn.exists('##TermRequest') ~= 1 then return end
  term:on('TermRequest', function(args)
    if not (args.data.sequence or args.data):match('^\027]133;A') then return end
    local prev_prompt, next_prompt = term:get_prompt_range()
    local lines = api.nvim_buf_get_lines(buf, prev_prompt + 1, next_prompt, false)
    ---@type table<integer, vim.Diagnostic.Set[]>
    local dmap = {}
    vim.iter(lines):each(function(line)
      local parsed = u.parse.from_line(line)
      local lnum = tonumber(parsed.lnum)
      if not lnum then return end
      local dbuf = parsed.filename and fn.bufadd(parsed.filename) or nil
      if not dbuf then return end
      dmap[dbuf] = dmap[dbuf] or {}
      ---@type vim.Diagnostic.Set
      local diag = {
        lnum = lnum - 1,
        col = tonumber(parsed.col),
        end_col = 2147483647, -- v:maxcol
        message = parsed.suffix or '',
        severity = vim.diagnostic.severity.WARN,
      }
      table.insert(dmap[dbuf], diag)
    end)
    for dbuf, diags in pairs(dmap) do
      vim.diagnostic.set(ns, dbuf, diags)
    end
  end)
end

return M
