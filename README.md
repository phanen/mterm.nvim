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
-- simple toggle
vim.keymap.set('n', '<a-;>', function() require('mterm').toggle() end)

-- toggle lazygit dwim
vim.keymap.set('n', 'go', function()
  if vim.v.count > 0 then return 'go' end
  vim.schedule(function()
    ---@type table<string, mterm.Node?>
    _G.mterms = _G.mterms or {}
    local cwd = (function()
      if vim.b.gitsigns_status_dict then return vim.b.gitsigns_status_dict.root end
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

-- scbk=0 an alternative way
vim.keymap.set('n', '<c-l>', function()
  local chan = vim.bo.channel
  local is_running = fn.jobwait({ chan }, 0)[1] == -1
  local can_swallow = function()
    if not is_running then return true end
    local info = api.nvim_get_chan_info(chan)
    local is_shell = info.argv[1]:match('%/fish$')
      or info.argv[1]:match('%/bash$')
      or info.argv[1]:match('%/zsh$')
      or info.argv[1]:match('%/sh$')
    if not is_shell then return false end
    local children = api.nvim_get_proc_children(fn.jobpid(chan))
    local only_has_atuin_bg_child = vim.iter(children):all(function(pid)
      local out = vim.system({ 'ps', 'h', '-o', 'command', '-p', pid }):wait().stdout
      out = assert(out):gsub('\n', '')
      local ok = out:match(vim.pesc('[atuin] <defunct>'))
        or out:match(vim.pesc('atuin history end --exit'))
      return ok
    end)
    return only_has_atuin_bg_child
  end
  if vim.bo.ft == 'fzf' or not can_swallow() then return '<c-l>' end
  if vim.bo.ft ~= 'mterm' then
    local buf = api.nvim_create_buf(false, true)
    vim.schedule(function()
      api.nvim_win_set_buf(0, buf)
      fn.jobstart({ vim.env.SHELL }, { term = true })
      fn.jobstop(chan)
    end)
    return '<ignore>'
  end
  vim.schedule(function()
    require('mterm').spawn()
    require('mterm').next()
    fn.jobstop(chan)
  end)
  return '<ignore>'
end, { expr = true, buffer = terminal_buf })

-- `ftplugin/mterm.lua` or `au FileType mterm`
vim.keymap.set('n', '<cr>', '<c-w>gF', { buffer = true })
vim.keymap.set('t', '<a-;>', function() require('mterm').toggle() end, { buffer = true })
vim.keymap.set('<a-j>', function() require('mterm').next() end, { buffer = true })
vim.keymap.set('<a-k>', function() require('mterm').prev() end, { buffer = true })
vim.keymap.set('<a-l>', function()
  require('mterm').spawn()
  require('mterm').next()
end, { buffer = true })
```

## todo
* task management... spawn a new task by `:send`
  * (wait... why cannot I use `:tab term {cmd}`)
* tmux session (will nvim has a better `sessionoptions` for terminal)?

## credit
* https://github.com/numToStr/FTerm.nvim
