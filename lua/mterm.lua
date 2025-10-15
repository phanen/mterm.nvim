---@diagnostic disable: duplicate-doc-field, duplicate-set-field, duplicate-doc-alias, unused-local, undefined-field
local fn, api, uv = vim.fn, vim.api, vim.uv
local u = {
  class = {
    lru = require('mterm.lru').new,
    term = require('mterm.term').new,
    win = require('mterm.win').new,
  },
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
M.slots = u.class.lru {}

---@type mterm.Node?
M.curr = nil

---@type win.Win
M.win = u.class.win({ config = { zindex = 100 } })

M.toggle_layout = function() M.win:toggle_layout() end

M.get_key = function()
  M.i = (M.i or 0) + 1
  return M.i
end

M.is_empty = function() return not M.curr end

local update_title = function()
  local size = M.slots.size
  if
    not M.win:is_open() or size == 0 -- last buf bdeleted
  then
    return
  end
  local title = vim
    .iter(M.slots:pairs())
    :enumerate()
    :map(function(id, _key, node)
      local hl = M.curr == node and 'TabLineSel' or 'TabLine'
      return { (' %s '):format(id), hl }
    end)
    :totable()
  pcall(api.nvim_win_set_config, M.win:get_win(), { title = title })
end

---@param node mterm.Node
local switch_to = function(node)
  M.curr = node
  if not M.win:is_open() then return end
  local buf = node.term:get_buf()
  M.win:set_buf(buf)
  update_title() -- why we need it here?
end

---@param node? mterm.Node
M.next = function(node)
  node = node or assert(M.curr)
  local node0 = M.slots:next_of(node)
  if not node0 then node0 = M.slots.head.next end
  if node0 == node then return end
  switch_to(node0)
end

---@param node? mterm.Node
M.prev = function(node)
  node = node or assert(M.curr)
  local node0 = M.slots:prev_of(node)
  if not node0 then node0 = M.slots.head.prev end
  if node0 == M.curr then return end
  switch_to(node0)
end

---@param opts? term.Opts
---@return mterm.Node
M.spawn = function(opts)
  opts = opts or {}
  local node
  local default = {
    width = M.win:get_config().width,
    height = M.win:get_config().height - (M.slots.size > 1 and 1 or 0),
    on_exit = function(...)
      local near_node = M.slots:next_of(node) or M.slots:prev_of(node)
      if opts.on_exit then opts.on_exit(...) end
      M.slots:delete(node)
      if near_node then
        switch_to(near_node)
      else
      end
      M.curr = near_node
      update_title()
    end,
    bo = { ft = 'mterm' },
  }
  node = {
    key = M.get_key(),
    term = u.class.term(u.merge(opts, default)),
  }
  M.slots:insert_after(M.curr or M.slots.head, node)
  if not M.curr then M.curr = node end
  update_title()
  node.term:spawn()
  return node
end

---@param node? mterm.Node
---@param focus? boolean
---@param opts? win.Opts|{}
M.open = function(node, focus, opts)
  ---@type mterm.Node
  node = node or M.curr or M.spawn()
  M.win:update(nil, opts)
  M.win:open(node.term:get_buf(), focus)
  M.curr = node
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
---@param cb function
M.send = function(cmd, node, cb)
  node = node or M.curr or M.spawn()
  vim.defer_fn(function()
    node.term:send(cmd)
    if cb then cb() end
  end, 100)
end

---@param key string
---@param node? mterm.Node
M.send_key = function(key, node)
  node = node or M.curr or M.spawn()
  vim.schedule(function()
    api.nvim_win_call(M.win.win, function() vim.cmd.norm(vim.keycode(key)) end)
    vim.b[node.term:get_buf()].term_pos = api.nvim_win_get_cursor(M.win.win)
  end)
end

local ns = api.nvim_create_namespace('nvim.terminal.prompt')
local myns = api.nvim_create_namespace('my.nvim.terminal.prompt')

---@param count integer
---@param pos? [integer, integer]
---@param node? mterm.Node
---@return [integer, integer]
M.get_prompt = function(count, pos, node)
  node = assert(node or M.curr, 'no terminal instance')
  pos = pos
    or (M.win.win and api.nvim_win_get_cursor(M.win.win))
    or vim.b[node.term:get_buf()].term_pos
    or { 1, 0 }
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
    node.term:get_buf(),
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

M.get_prompt_range = function()
  local prev_prompt = u.mterm.get_prompt(-1)
  local next_prompt = u.mterm.get_prompt(1, prev_prompt)
  if next_prompt[1] == -1 then
    next_prompt = prev_prompt
    prev_prompt = u.mterm.get_prompt(-1, next_prompt)
  end
  return prev_prompt[1], next_prompt[1]
end

---@param line string
---@return table
M.parse_line = function(line)
  local prefix, filename, suffix = line:match('(DEBUGPRINT%[%d+%]:%s*)(%S+:%d+)(.*)')
  return {
    line = line,
    content = line:match('^DEBUGPRINT%[%d+%]:%s*(.*)'),
    filename = filename,
    prefix = prefix,
    suffix = suffix,
  }
end

local mark
local render = function(buf, lnum, ctx)
  pcall(api.nvim_buf_del_extmark, buf, myns, mark)
  local opts = {
    virt_text_pos = 'overlay',
    virt_text = {
      { ctx.prefix, 'DiagnosticVirtualTextHint' },
      { ctx.filename, 'DiagnosticVirtualTextInfo' },
      { ctx.suffix, 'DiagnosticVirtualTextWarn' },
    },
  }
  mark = api.nvim_buf_set_extmark(buf, myns, lnum, 0, opts)
end

M.attach_nav = function(buf)
  api.nvim_create_autocmd('CursorMoved', {
    buffer = buf,
    group = api.nvim_create_augroup('my.mterm', { clear = true }),
    callback = function()
      local line = api.nvim_get_current_line()
      pcall(api.nvim_buf_del_extmark, buf, myns, mark)
      local ctx = M.parse_line(line)
      if ctx.filename then
        local lnum = fn.line('.') - 1
        render(buf, lnum, ctx)
      end
    end,
  })
end

local pp = false and u.pp or function(...) end

M.set_cursor = function(pos)
  api.nvim_win_set_cursor(M.win.win, pos)
  vim.b[M.curr.term:get_buf()].term_pos = pos
end

M.next_dp = function()
  local prev_prompt, next_prompt = M.get_prompt_range()
  local win = assert(M.win.win)
  local buf = M.curr.term:get_buf()
  local lnum = fn.line('.', win) - 1
  assert(
    lnum >= prev_prompt and lnum <= next_prompt,
    'p:' .. prev_prompt .. ' n:' .. next_prompt .. ' l:' .. lnum
  )
  pp(lnum, prev_prompt, next_prompt)
  local ctx, wrapped
  while true do
    lnum = lnum + 1
    if not wrapped and lnum >= next_prompt then
      lnum = prev_prompt
      wrapped = true
    elseif wrapped and lnum >= next_prompt then
      return pp('no matched')
    end
    local ok, lines = pcall(api.nvim_buf_get_lines, buf, lnum, lnum + 1, true)
    if not ok then pp(lnum, prev_prompt, next_prompt) end
    ctx = M.parse_line(lines[1])
    if ctx.filename then break end
  end
  local n, d = ctx.filename:match('(.*):(%d+)')
  vim.cmd.edit('+' .. d .. ' ' .. n)
  pp(lnum, prev_prompt, next_prompt)
  render(buf, lnum, ctx)
  M.set_cursor({ lnum + 1, 0 })
end

M.prev_dp = function()
  local prev_prompt, next_prompt = M.get_prompt_range()
  local win = assert(M.win.win)
  local buf = M.curr.term:get_buf()
  local lnum = fn.line('.', win) - 1
  assert(
    lnum >= prev_prompt and lnum <= next_prompt,
    'p:' .. prev_prompt .. ' n:' .. next_prompt .. ' l:' .. lnum
  )
  pp(lnum, prev_prompt, next_prompt)
  local ctx, wrapped
  while true do
    lnum = lnum - 1
    if not wrapped and lnum < prev_prompt then
      lnum = next_prompt - 1
      wrapped = true
    elseif wrapped and lnum < prev_prompt then
      return pp('no matched')
    end

    local ok, lines = pcall(api.nvim_buf_get_lines, buf, lnum, lnum + 1, true)
    if not ok then pp(lnum, prev_prompt, next_prompt) end
    ctx = M.parse_line(lines[1])
    if ctx.filename then break end
  end
  local n, d = ctx.filename:match('(.*):(%d+)')
  vim.cmd.edit('+' .. d .. ' ' .. n)
  pp(lnum, prev_prompt, next_prompt)
  render(buf, lnum, ctx)
  M.set_cursor({ lnum + 1, 0 })
end

return M
