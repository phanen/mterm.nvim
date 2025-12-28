local fn, api, uv = vim.fn, vim.api, vim.uv
---START INJECT parse.lua

local M = {}
local api, fn = vim.api, vim.fn

local from_cword = function(cword)
  local word = fn.expand(cword or '<cWORD>')
  local file, lnum, col
  file, lnum, col = word:match('^(.-):(%d+):(%d+).*$')
  if not file then -- Try file:line
    file, lnum = word:match('^(.-):(%d+).*$')
  end
  if not file then -- Try file @ line:column
    file, lnum, col = word:match('^(.-) @ (%d+):(%d+)$')
  end
  if not file then -- Try file @ line
    file, lnum = word:match('^(.-) @ (%d+)$')
  end
  file = file or word
  file = file:gsub(':$', ''):gsub('^"', ''):gsub('"$', ''):gsub('",$', '')
  return file, lnum, col
end

---@class parse.ParseLineResult
---@field line string
---@field content? string
---@field filename? string
---@field lnum? string 1-index
---@field prefix? string
---@field suffix? string
---@field col? string

---@param line? string
---@param only? boolean debugprint only
---@return parse.ParseLineResult
M.from_line = function(line, only)
  line = line or api.nvim_get_current_line()
  only = only ~= false
  local prefix, filename, lnum, suffix = line:match('(DEBUGPRINT%[%d+%]:%s*)(%S+):(%d+)(.*)')
  if not only and not prefix then
    ---@diagnostic disable-next-line: redefined-local
    local file, lnum, col = from_cword()
    return { line = line, filename = file, lnum = lnum, col = col }
  end
  return {
    line = line,
    content = line:match('^DEBUGPRINT%[%d+%]:%s*(.*)'),
    filename = filename,
    lnum = lnum,
    prefix = prefix,
    suffix = suffix,
  }
end

local mark ---@type integer?
local myns = api.nvim_create_namespace('my.nvim.terminal.prompt')

---@param buf integer extmark buf
---@param lnum integer extmark lnum
---@param ctx? parse.ParseLineResult
---@return boolean?
M.render = function(buf, lnum, ctx)
  ctx = ctx or M.from_line(api.nvim_buf_get_lines(buf, lnum, lnum + 1, false)[1])
  if mark then
    pcall(api.nvim_buf_del_extmark, buf, myns, mark)
    mark = nil
  end
  if not ctx.prefix then return end
  local opts = {
    hl_mode = 'combine',
    virt_text_pos = 'overlay',
    virt_text = {
      { ctx.prefix, 'Debug' },
      { ctx.filename, 'qfFileName' },
      { ':' },
      { ctx.lnum, 'qfLineNr' },
    },
  }
  mark = api.nvim_buf_set_extmark(buf, myns, lnum, 0, opts)
  return true
end

local asinteger = tonumber ---@type fun(x: any): integer
local maxcol = vim.v.maxcol

---@param lines string[]
---@return table<integer, vim.Diagnostic.Set[]>
M.diags = function(lines)
  ---@type table<integer, vim.Diagnostic.Set[]>
  local bufdiags = {}
  vim.iter(lines):each(function(line)
    local parsed = M.from_line(line)
    local lnum = asinteger(parsed.lnum)
    if not lnum then return end
    local buf = parsed.filename and fn.bufadd(parsed.filename) or nil
    if not buf then return end
    bufdiags[buf] = bufdiags[buf] or {}
    ---@type vim.Diagnostic.Set
    local diag = {
      lnum = lnum - 1,
      col = asinteger(parsed.col),
      end_col = maxcol,
      message = vim.trim(parsed.suffix or ''),
      severity = vim.diagnostic.severity.WARN,
    }
    table.insert(bufdiags[buf], diag)
  end)
  return bufdiags
end

return M
