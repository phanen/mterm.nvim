Multiplex single win for a group of term buf.

## highlight
* Togglable layout.
* Debugprint extmarks.
* Navigation in debugprint lines.

```sh
nvim --clean --cmd 'set rtp^=.'
```

> [!NOTE]
> Enhancement of terminal mode/cursor: https://github.com/phanen/termmode.nvim.


<details>
<summary>example: toggle dwim</summary>

```lua
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
    if is_init then _G.mterms[key] = mterm.spawn(opts) end
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
    mterm.open(_G.mterms[key])
    vim.defer_fn(function() mterm.send(send, _G.mterms[key]) end, 100)
  end)
  return '<ignore>'
end)
```
</details>

<details>
<summary>example: goto file</summary>

```lua
-- vim.keymap.set('n', '<cr>', '<c-w>gF', { buffer = true })
vim.keymap.set('n', '<cr>', function()
  local ctx = mterm.parse_line(api.nvim_get_current_line())
  if not ctx.filename then return '<c-w>gF' end
  local name, lnum = ctx.filename:match('(.*):(%d+)')
  local alt_win = fn.win_getid((fn.winnr('#')))
  vim.schedule(function()
    api.nvim_win_call(alt_win, function() vim.cmd.edit('+' .. lnum .. ' ' .. name) end)
  end)
  return '<ignore>'
end, { expr = true, buffer = terminal_buf })
```
</details>

<details>
<summary>example: scbk=0 an alternative way</summary>

```lua
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
    mterm.spawn()
    mterm.next()
    fn.jobstop(chan)
  end)
  return '<ignore>'
end, { expr = true, buffer = terminal_buf })
```
</details>

<details>
<summary>example: task runner</summary>

```lua
local runners = { javascript = 'node {file}', rust = 'cargo run {file}' }
Task.termrun = function()
  -- fetch project-local config
  local cmd = u.project(uv.cwd()).runner or runners[vim.bo.ft]
  if not cmd then return end
  cmd = cmd:gsub('%{file%}', api.nvim_buf_get_name(0))
  if mt.is_empty() then
    mt.open(nil, false, { layout = 'bot' })
  else
    mt.open()
  end
  mt.send_key('G')
  mt.send(cmd, nil, function() mt.attach_nav(mt.curr.term:get_buf()) end)
end
```
</details>

## todo
* persistent session (will nvim has a better `sessionoptions` for terminal)?
* make 'efm' work with term buffer via osc133, term should work like qf

## credit
* https://github.com/numToStr/FTerm.nvim
* https://github.com/andrewferrier/debugprint.nvim
