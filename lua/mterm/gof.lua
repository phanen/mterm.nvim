local M = {}
local api, fn = vim.api, vim.fn
local with = vim._with or require('mterm.with') ---@type fun(context: vim.context.mods, f: function): any

---@param buf1? integer
---@param path1 string
---@param buf2? integer
---@param path2? string
---@return boolean
local buf_edited = function(buf1, path1, buf2, path2)
  buf2 = buf2 or api.nvim_win_get_buf(0)
  return buf1 == buf2 or require('mterm.path').equals(path1, path2 or api.nvim_buf_get_name(buf2))
end

---@param filepath string
---@return integer?
local load_buf = function(filepath)
  local relpath = require('mterm.path').normalize(
    require('mterm.path').relative_to(filepath, require('mterm._').cwd())
  )
  local bufnr = fn.bufadd(relpath)
  if bufnr == 0 then return end
  vim.bo[bufnr].buflisted = true
  return bufnr
end

---@param buf integer
---@param will_replace_curbuf? boolean
---@return boolean, string? success
local set_buf = function(buf, will_replace_curbuf)
  if
    will_replace_curbuf
    and vim.bo.buftype == ''
    and vim.bo.filetype == ''
    and api.nvim_buf_line_count(0) == 1
    and api.nvim_buf_get_lines(0, 0, -1, false)[1] == ''
    and api.nvim_buf_get_name(0) == ''
  then
    vim.bo.bufhidden = 'wipe'
  end
  return pcall(api.nvim_set_current_buf, buf)
end

local feed = api.nvim_feedkeys

---@param ctx? parse.ParseLineResult
---@param focus? boolean force focus the new edit buffer
M.term_edit = function(ctx, focus)
  ctx = ctx or require('mterm.parse').from_line(api.nvim_get_current_line(), false)
  local ft = vim.bo.filetype
  local use_altwin = (ft == 'mterm' or api.nvim_win_get_config(0).relative ~= '')
  local win = use_altwin and fn.win_getid((fn.winnr('#'))) or api.nvim_get_current_win()
  local filepath = ctx.filename
  if not filepath or win == 0 then return feed('gF', 'n', false) end
  with({ win = win }, function()
    if not buf_edited(nil, filepath) then assert(set_buf(assert(load_buf(filepath)))) end
    local pos = {
      require('mterm._').tointeger(ctx.lnum) or 1,
      math.max((require('mterm._').tointeger(ctx.col) or 1) - 1, 0),
    }
    local is_same_pos = require('mterm._').tointeger(ctx.lnum)
      and vim.deep_equal(api.nvim_win_get_cursor(0), pos)
    if not is_same_pos then
      api.nvim_win_set_cursor(0, pos)
      vim.cmd('norm! zz')
    end
  end)
  if not focus then return end
  if ft == 'mterm' then
    require('mterm.mterm').toggle_or_focus()
  else
    api.nvim_set_current_win(win)
  end
end

M.edit = function()
  local ft = vim.bo.ft
  if ft == 'qf' then return feed(vim.keycode('<cr>'), 'n', false) end
  vim.F.nil_wrap(require)('nvim-tree')
  if ft == 'PlenaryTestPopup' then return M.term_edit(nil, true) end
  local gF = api.nvim_win_get_config(0).relative == ''
  if gF then return feed('gF', 'n', false) end
  feed(vim.keycode('<c-w>gF'), 'n', false)
end

return M
