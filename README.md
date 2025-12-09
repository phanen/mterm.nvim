## highlight
* Tabbed buffer in single window.
* Togglable layout.
* Debugprint highlighting/diagnostics/Navigation.

```sh
nvim --clean --cmd 'set rtp^=.'
```

> [!NOTE]
> Enhancement of terminal mode/cursor: https://github.com/phanen/termmode.nvim.

## todo
* persistent session (will nvim has a better `sessionoptions` for terminal)?
* make 'efm' work with term buffer via osc133, term should work like qf
  * from_errorformat in https://github.com/mfussenegger/nvim-lint/blob/1b9cc3ba24953e83319c4f77741553c0564af596/lua/lint/parser.lua#L21
  * more parser, context aware parsing via osc133 C

## credit
* https://github.com/numToStr/FTerm.nvim
* https://github.com/andrewferrier/debugprint.nvim
