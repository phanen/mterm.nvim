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

M.toggle_layout = function() M.win:toggle_layout() end

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
  local title = vim
    .iter(slots:pairs())
    :enumerate()
    :map(function(id, _key, node)
      local hl = curr == node and 'TabLineSel' or 'TabLine'
      return { (' %s '):format(id), hl }
    end)
    :totable()
  local win = M.win:get_win()
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

M.toggle_focus = function()
  if M.win:is_focused() then
    vim.cmd.wincmd('p')
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
---@param cb? function
M.send = function(cmd, node, cb)
  node = node or curr or M.spawn()
  vim.defer_fn(function()
    node.term:send(cmd)
    if cb then cb() end
  end, 100)
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

---@param buf integer
---@param lnum integer
---@param ctx? parse.ParseLineResult
---@return boolean?
local render = function(buf, lnum, ctx)
  ctx = ctx or u.parse.from_line()
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
M.gotofile = function(ctx)
  ctx = ctx or u.parse.from_line()
  local altwin = fn.win_getid((fn.winnr('#')))
  if not ctx.filename or altwin == -1 then return '<c-w>gF' end
  vim.schedule(function()
    local buf = api.nvim_win_get_buf(altwin)
    vim._with({ win = altwin, buf = buf }, function()
      if fn.bufname() ~= ctx.filename then
        if not pcall(vim.cmd.buffer, ctx.filename) then vim.cmd.edit(ctx.filename) end
      end
      if ctx.lnum and fn.line('.', altwin) ~= ctx.lnum then fn.cursor(ctx.lnum, 0) end
      vim.cmd('norm! zz')
    end)
    M.smart_toggle()
  end)
  return '<ignore>'
end

---@param node? mterm.Node
M.next_dp = function(node)
  local term = (node or assert(curr)).term
  local buf = assert(term:get_buf())
  term:next_dp(function(line, lnum)
    local ctx = u.parse.from_line(line)
    if render(buf, lnum, ctx) then
      M.gotofile(ctx)
      term:set_cursor({ lnum, select(2, unpack(term:get_cursor())) })
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
    if render(buf, lnum, ctx) then
      M.gotofile(ctx)
      term:set_cursor({ lnum, select(2, unpack(term:get_cursor())) })
      return true
    end
  end)
end

M._attach_render = function(node)
  local buf = node.term:get_buf()
  api.nvim_create_autocmd('CursorMoved', {
    buffer = buf,
    group = api.nvim_create_augroup('my.mterm', { clear = true }),
    callback = function() render(buf, fn.line('.') - 1) end,
  })
end

return M
