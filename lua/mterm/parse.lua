local fn, api, uv = vim.fn, vim.api, vim.uv
---START INJECT parse.lua

local M = {}

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

return M
