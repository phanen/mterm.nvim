local n = require('nvim-test.helpers')
local Screen = require('nvim-test.screen')

local fn = n.fn
local api = n.api
local eq = n.eq
local exec_lua = n.exec_lua
-- local exec_capture = n.exec_capture
local matches = n.matches
local pcall_err = n.pcall_err

describe('mterm', function()
  local screen --- @type test.screen
  before_each(function()
    n.clear()
    screen = Screen.new(30, 5)
    screen:attach()
    -- screen:set_default_attr_ids({
    --   [1] = { background = Screen.colors.NvimLightYellow, foreground = Screen.colors.NvimDarkGray1 },
    --   [2] = { foreground = Screen.colors.NvimDarkGreen },
    --   [3] = { foreground = Screen.colors.NvimLightGrey1, background = Screen.colors.NvimDarkYellow },
    --   [4] = { foreground = Screen.colors.NvimLightGrey4 },
    -- })
    exec_lua(function() ---@diagnostic disable-next-line: duplicate-set-field
      vim.opt.rtp:append('.')
      -- vim.o.ve = 'block'
      -- vim.o.sol = false -- this change `<c-q>G` behavior
      -- vim.cmd.runtime { 'plugin/vbi.lua', bang = true }
    end)
  end)

  it('chore', function() end)
end)
