## highlight
* Tabbed buffer in single window.
* Togglable layout.
* Debugprint highlighting/diagnostics/Navigation.

```sh
bash .run.sh
```

> [!NOTE]
> Enhancement of terminal mode/cursor: https://github.com/phanen/tmode.nvim.

## opencode provider

```lua
package.preload['opencode.provider.mterm'] = function() return require('mterm').opencode() end
vim.g.opencode_opts = { provider = { mterm = {}, enabled = 'mterm' } }
```

## todo
* persistent session (will nvim has a better `sessionoptions` for terminal)?
* make 'efm' work with term buffer via osc133, term should work like qf
  * from_errorformat in https://github.com/mfussenegger/nvim-lint/blob/1b9cc3ba24953e83319c4f77741553c0564af596/lua/lint/parser.lua#L21
  * more parser, context aware parsing via osc133 C

## credit/related
* https://github.com/numToStr/FTerm.nvim
* https://github.com/andrewferrier/debugprint.nvim
* https://github.com/gh-liu/nvim-winterm
* https://github.com/m00qek/baleia.nvim
  * like `vim.api.nvim_open_term(0, {})` but don't need libverm
