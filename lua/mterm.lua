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
M.open = function(node)
  ---@type mterm.Node
  node = node or M.curr or M.spawn()
  M.win:open(node.term:get_buf())
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
  if M.win.layout then
    M.toggle_focus()
  else
    M.toggle()
  end
end

---@param cmd string
---@param node mterm.Node
M.send = function(cmd, node)
  node = node or M.curr or M.spawn()
  vim.wait(100) -- hack: wait e.g. slow fish prompt?...
  node.term:send(cmd)
end

return M
