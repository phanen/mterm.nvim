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
