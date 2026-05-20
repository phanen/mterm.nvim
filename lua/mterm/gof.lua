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

local codex_edited_hunk = '^%s*•%s*Edited%s+(.+)%s+%(%+%d+%s*-%d+%)%s*$'
local opencode_edited_hunk = '^%s*┃%s*←%s*Edit%s+(.-)%s*$'
local opencode_wrote_hunk = '^%s*┃%s*#%s*Wrote%s+(.-)%s*$'

---@param line string
---@return integer?
local parse_codex_lnum = function(line) return tonumber(line:match('^%s*(%d+)')) end

---@param line string
---@return integer?
local parse_opencode_lnum = function(line) return tonumber(line:match('^%s*┃%s*(%d+)')) end

---@param win integer
---@return string? filepath
---@return integer? lnum
local peek_codex_diff = function(win)
  local buf = api.nvim_win_get_buf(win)
  local row = api.nvim_win_get_cursor(win)[1]
  local line = api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ''
  local lnum = parse_codex_lnum(line)
  if not lnum then return end
  for i = row, 1, -1 do
    local header = api.nvim_buf_get_lines(buf, i - 1, i, false)[1] or ''
    local filepath = header:match(codex_edited_hunk)
    if filepath then return filepath, lnum end
  end
end

---@param win integer
---@return string? filepath
---@return integer? lnum
local peek_opencode_diff = function(win)
  local buf = api.nvim_win_get_buf(win)
  local row = api.nvim_win_get_cursor(win)[1]
  local line = api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ''
  local lnum = parse_opencode_lnum(line)
  if not lnum then return end
  for i = row, 1, -1 do
    local header = api.nvim_buf_get_lines(buf, i - 1, i, false)[1] or ''
    local filepath = header:match(opencode_edited_hunk) or header:match(opencode_wrote_hunk)
    if filepath then return filepath, lnum end
  end
end

---@param ... string
---@return boolean
local is_cmd = function(...)
  local command = (vim.b.last_term_cmd or table.concat(
    api.nvim_get_chan_info(vim.bo.channel).argv,
    ' '
  )):match('^(%S+)') or ''
  command = require('mterm.path').tail(command)
  for _, name in ipairs({ ... }) do
    if command:match('^' .. vim.pesc(name) .. '$') then return true end
  end
  return false
end

---@param ctx? parse.ParseLineResult
---@param focus? boolean force focus the new edit buffer
M.term_edit = function(ctx, focus)
  ctx = ctx or require('mterm.parse').from_line(api.nvim_get_current_line(), false)
  local ft = vim.bo.filetype
  local use_altwin = (ft == 'mterm' or api.nvim_win_get_config(0).relative ~= '')
  local win = use_altwin and fn.win_getid((fn.winnr('#'))) or api.nvim_get_current_win()
  local filepath = ctx and ctx.filename
  if is_cmd('codex') then
    local edit_filepath, edit_lnum = peek_codex_diff(0)
    if edit_filepath and edit_lnum then
      filepath = edit_filepath
      ctx = ctx or {}
      ctx.filename = edit_filepath
      ctx.lnum = edit_lnum
    end
  elseif is_cmd('opencode') then
    local edit_filepath, edit_lnum = peek_opencode_diff(0)
    if edit_filepath and edit_lnum then
      filepath = edit_filepath
      ctx = ctx or {}
      ctx.filename = edit_filepath
      ctx.lnum = edit_lnum
    end
  end
  if not filepath or win == 0 then return feed('gF', 'n', false) end
  filepath = vim.fs.normalize(filepath)
  if not vim.uv.fs_stat(filepath) then
    filepath = vim.fs.joinpath('src', filepath)
    if not vim.uv.fs_stat(filepath) then return end
  end
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
