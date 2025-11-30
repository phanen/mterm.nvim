vim.keymap.set(
  'n',
  '<cr>',
  function() return u.mterm.gotofile() end,
  { expr = true, buffer = terminal_buf }
)
