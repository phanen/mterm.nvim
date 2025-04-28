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

## todo
* task management... spawn a new task by `:send`
  * (wait... why cannot I use `:tab term {cmd}`)
* tmux session (will nvim has a better `sessionoptions` for terminal)?

## credit
* https://github.com/numToStr/FTerm.nvim
