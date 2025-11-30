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
    if not cwd then return end
    local opts = { cmd = { 'lazygit' }, cwd = cwd, auto_close = true }
    local key = vim.inspect(opts)
    local term = _G.mterms[key]
    local is_init = not term or not term.term:is_running()
    if is_init then _G.mterms[key] = mterm.spawn(opts) end
    local send = (function()
      local cword = fn.expand('<cword>'):match('^%x%x%x%x%x%x')
      if cword then
        vim.cmd([[fclose!]])
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
