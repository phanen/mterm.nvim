nvim "$@" --clean --cmd 'set rtp^=. nu rnu' \
  +'lua require("mterm").toggle_or_focus()' \
  +'nnoremap <a-;> <cmd>lua require("mterm").toggle_or_focus()<cr>' \
  +'tnoremap <a-;> <cmd>lua require("mterm").toggle_or_focus()<cr>' \
  +'tnoremap <a-l> <cmd>lua require("mterm").spawn()<cr>' \
  +'tnoremap <a-j> <cmd>lua require("mterm").next()<cr>' \
  +'tnoremap <a-k> <cmd>lua require("mterm").prev()<cr>' \
  +'tnoremap <a-h> <cmd>lua require("mterm").toggle_layout()<cr>'
