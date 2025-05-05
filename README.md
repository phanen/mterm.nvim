A group of term buf in a toggle-able floatwin.

## api
```lua
require('mterm').toggle()
require('mterm').next()
require('mterm').prev()
require('mterm').spawn()
require('mterm').send()
```

> [!NOTE]
> If you find painful to work with mode/cursor: https://github.com/phanen/termmode.nvim.

## example

```lua
vim.keymap.set('n', '<a-;>', function() require('mterm').toggle() end)
vim.keymap.set('n', 'go', function()
  if vim.v.count > 0 then return 'go' end
  vim.schedule(function()
    ---@type table<string, mterm.Node?>
    _G.mterms = _G.mterms or {}
    local cwd = vim.b.gitsigns_status_dict and vim.b.gitsigns_status_dict.root
      or vim.fs.root(0, '.git')
    local opts = { cmd = { 'lazygit' }, cwd = cwd, auto_close = true }
    local key = vim.inspect(opts)
    local term = _G.mterms[key]
    if not term or not term.term:is_running() then _G.mterms[key] = require('mterm').spawn(opts) end
    local relpath = fs.relpath(cwd, fn.bufname())
    require('mterm').open(_G.mterms[key])
    vim.defer_fn(function() require('mterm').send('2/' .. relpath, _G.mterms[key]) end, 100)
  end)
  return '<ignore>'
end)

-- `ftplugin/mterm.lua` or `au FileType mterm`
vim.keymap.set('n', '<cr>', '<c-w>gF', { buffer = true })
vim.keymap.set('t', '<a-;>', function() require('mterm').toggle() end, { buffer = true })
vim.keymap.set('<a-j>', function() require('mterm').next() end, { buffer = true })
vim.keymap.set('<a-k>', function() require('mterm').prev() end, { buffer = true })
vim.keymap.set('<a-l>', function()
  require('mterm').spawn()
  require('mterm').next()
end)
```

## todo
* task management... spawn a new task by `:send`
  * (wait... why cannot I use `:tab term {cmd}`)
* tmux session (will nvim has a better `sessionoptions` for terminal)?

## credit
* https://github.com/numToStr/FTerm.nvim
