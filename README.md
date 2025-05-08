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
    local cwd = (function()
      if vim.b.gitsigns_status_dict then return vim.b.gitsigns_status_dict.root end
      if vim.b.git_dir then return vim.b.git_dir end -- fugitive buffer
      if -- maybe in float gitsigns float buffer (float, no ft)
        api.nvim_win_get_config(0).relative ~= ''
        and vim.bo.bt == 'nofile'
        and vim.b[fn.bufnr('#')].gitsigns_status_dict
      then
        return vim.b[fn.bufnr('#')].gitsigns_status_dict.root
      end
      return vim.fs.root(0, '.git')
    end)()
    local opts = { cmd = { 'lazygit' }, cwd = cwd, auto_close = true }
    local key = vim.inspect(opts)
    local term = _G.mterms[key]
    local is_init = not term or not term.term:is_running()
    if is_init then _G.mterms[key] = require('mterm').spawn(opts) end
    local send = (function()
      local cword = fn.expand('<cword>'):match('^%x%x%x%x%x%x')
      if cword then
        vim.cmd [[fclose!]]
        return '4/' .. cword
      end
      local relpath = fs.relpath(cwd, fn.bufname())
      if relpath == '.' then relpath = '' end
      return '2/' .. relpath
    end)()
    require('mterm').open(_G.mterms[key])
    vim.defer_fn(function() require('mterm').send(send, _G.mterms[key]) end, 100)
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
