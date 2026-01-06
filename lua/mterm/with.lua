---START INJECT with.lua

local api = vim.api
local scope_map = { buf = 'bo', global = 'go', win = 'wo' }
local scope_order = { 'o', 'wo', 'bo', 'go', 'env' }
local state_restore_order = { 'bo', 'wo', 'go', 'env' }

local validate = function(name, val, expected_type, optional)
  if val == nil then
    if not optional then error(string.format('%s: expected %s, got nil', name, expected_type)) end
    return
  end
  if type(val) ~= expected_type then
    error(string.format('%s: expected %s, got %s', name, expected_type, type(val)))
  end
end

---@param context vim.context.mods
---@return vim.api.keyset.cmd.mods
local build_cmd_mods = function(context)
  local mods = {}
  if context.silent ~= nil then mods.silent = context.silent end
  if context.unsilent ~= nil then mods.unsilent = context.unsilent end
  if context.emsg_silent ~= nil then mods.emsg_silent = context.emsg_silent end
  if context.hide ~= nil then mods.hide = context.hide end
  if context.keepalt ~= nil then mods.keepalt = context.keepalt end
  if context.keepjumps ~= nil then mods.keepjumps = context.keepjumps end
  if context.keepmarks ~= nil then mods.keepmarks = context.keepmarks end
  if context.keeppatterns ~= nil then mods.keeppatterns = context.keeppatterns end
  if context.lockmarks ~= nil then mods.lockmarks = context.lockmarks end
  if context.noautocmd ~= nil then mods.noautocmd = context.noautocmd end
  ---@diagnostic disable-next-line: return-type-mismatch
  return next(mods) and mods or nil
end

---@param context vim.context.mods
---@return vim.context.state
local get_context_state = function(context)
  ---@type vim.context.state
  local res = { bo = {}, env = {}, go = {}, wo = {} }

  for _, scope in ipairs(scope_order) do
    for name, _ in
      pairs(context[scope] or {} --[[@as table<string,any>]])
    do
      local sc = scope == 'o' and scope_map[api.nvim_get_option_info2(name, {}).scope] or scope

      res[sc][name] = vim.F.if_nil(res[sc][name], vim[sc][name], vim.NIL)

      if sc ~= 'env' and res.go[name] == nil then res.go[name] = res.go[name] or vim.go[name] end
    end
  end

  return res
end

---@param context vim.context.mods
---@param f function
---@return ...
local function _with(context, f)
  validate('context', context, 'table')
  validate('f', f, 'function')

  validate('context.bo', context.bo, 'table', true)
  validate('context.buf', context.buf, 'number', true)
  validate('context.emsg_silent', context.emsg_silent, 'boolean', true)
  validate('context.env', context.env, 'table', true)
  validate('context.go', context.go, 'table', true)
  validate('context.hide', context.hide, 'boolean', true)
  validate('context.keepalt', context.keepalt, 'boolean', true)
  validate('context.keepjumps', context.keepjumps, 'boolean', true)
  validate('context.keepmarks', context.keepmarks, 'boolean', true)
  validate('context.keeppatterns', context.keeppatterns, 'boolean', true)
  validate('context.lockmarks', context.lockmarks, 'boolean', true)
  validate('context.noautocmd', context.noautocmd, 'boolean', true)
  validate('context.o', context.o, 'table', true)
  validate('context.sandbox', context.sandbox, 'boolean', true)
  validate('context.silent', context.silent, 'boolean', true)
  validate('context.unsilent', context.unsilent, 'boolean', true)
  validate('context.win', context.win, 'number', true)
  validate('context.wo', context.wo, 'table', true)

  if context.buf then
    if not api.nvim_buf_is_valid(context.buf) then error('Invalid buffer id: ' .. context.buf) end
  end

  if context.win then
    if not api.nvim_win_is_valid(context.win) then error('Invalid window id: ' .. context.win) end
    if context.buf and api.nvim_win_get_buf(context.win) ~= context.buf then
      error('Can not set both `buf` and `win` context.')
    end
  end

  if context.sandbox then error('Vim:E48: Not allowed in sandbox') end

  local saved_state = {
    buf = context.buf and api.nvim_get_current_buf(),
    win = context.win and api.nvim_get_current_win(),
  }

  local need_temp_noautocmd = (context.buf or context.win)
  if need_temp_noautocmd then saved_state.temp_eventignore = vim.go.eventignore end

  local callback = function()
    if need_temp_noautocmd then vim.go.eventignore = 'all' end
    if context.win then api.nvim_set_current_win(context.win) end
    if context.buf then api.nvim_set_current_buf(context.buf) end
    if need_temp_noautocmd then vim.go.eventignore = saved_state.temp_eventignore end

    local ok, state = pcall(get_context_state, context)
    if not ok then error(state, 0) end

    for _, scope in ipairs(scope_order) do
      for name, context_value in
        pairs(context[scope] or {} --[[@as table<string,any>]])
      do
        --- @diagnostic disable-next-line:no-unknown
        vim[scope][name] = context_value
      end
    end

    local res
    local cmd_mods = build_cmd_mods(context)

    local result_slot = {}
    local wrapper = function() result_slot.res = { pcall(f) } end

    _G._vim_with_callback = wrapper
    api.nvim_cmd({ cmd = 'lua', args = { '_G._vim_with_callback()' }, mods = cmd_mods or {} }, {})
    _G._vim_with_callback = nil

    res = result_slot.res

    for _, scope in ipairs(state_restore_order) do
      for name, cached_value in
        pairs(state[scope] --[[@as table<string,any>]])
      do
        --- @diagnostic disable-next-line:no-unknown
        vim[scope][name] = cached_value
      end
    end

    if need_temp_noautocmd then vim.go.eventignore = 'all' end
    if saved_state.buf then api.nvim_set_current_buf(saved_state.buf) end
    if saved_state.win then api.nvim_set_current_win(saved_state.win) end
    if need_temp_noautocmd then vim.go.eventignore = saved_state.temp_eventignore end

    if not res[1] then error(res[2], 0) end
    return unpack(res, 2, table.maxn(res))
  end

  return callback()
end

return _with
