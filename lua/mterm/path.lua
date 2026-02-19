-- https://github.com/ibhagwan/fzf-lua/blob/db4764d61597dd548ccc31b625d7ccbb68a92925/lua/fzf-lua/path.lua
---START INJECT path.lua

local string_sub = string.sub
local string_byte = string.byte
local fn = vim.fn

local M = {}

local if_win = function(a, b)
  if _G.is_win then return a end
  return b
end

M.dot_byte = string_byte('.')
M.colon_byte = string_byte(':')
M.fslash_byte = string_byte('/')
M.bslash_byte = string_byte([[\]])

---@param path string?
---@return string
M.separator = function(path)
  if _G.is_win and path then
    local maybe_separators = { string_byte(path, 3), string_byte(path, 2) }
    for _, s in ipairs(maybe_separators) do
      if M.byte_is_separator(s) then return string.char(s) end
    end
  end
  vim.F.if_nil()
  return string.char(if_win(M.bslash_byte, M.fslash_byte))
end

M.separator_byte = function(path) return string_byte(M.separator(path), 1) end

---@param byte number
---@return boolean
M.byte_is_separator = function(byte)
  if _G.is_win then
    return byte == M.bslash_byte or byte == M.fslash_byte
  else
    return byte == M.fslash_byte
  end
end

M.is_separator = function(c) return M.byte_is_separator(string_byte(c, 1)) end

---@param path string
---@return boolean
M.ends_with_separator = function(path) return M.byte_is_separator(string_byte(path, #path)) end

---@param path string
---@return string
M.add_trailing = function(path)
  if M.ends_with_separator(path) then return path end
  return path .. M.separator(path)
end

---@param path string
---@return string
M.remove_trailing = function(path)
  while M.ends_with_separator(path) do
    path = path:sub(1, #path - 1)
  end
  return path
end

---@param path string
---@return boolean
M.is_absolute = function(path)
  return if_win(string_byte(path, 2) == M.colon_byte, string_byte(path, 1) == M.fslash_byte)
end

---@param path string
---@return boolean
M.has_cwd_prefix = function(path)
  return #path > 1
    and string_byte(path, 1) == M.dot_byte
    and M.byte_is_separator(string_byte(path, 2))
end

---@param path string
---@return string
M.strip_cwd_prefix = function(path)
  if M.has_cwd_prefix(path) then
    return #path > 2 and path:sub(3) or ''
  else
    return path
  end
end

---@param path string
---@return string
M.render_crlf = function(path) return (path:gsub('\n', '␊'):gsub('\r', '␍')) end

---@param path string
---@return string
M.tail = function(path)
  local end_idx = M.ends_with_separator(path) and #path - 1 or #path
  for i = end_idx, 1, -1 do
    if M.byte_is_separator(string_byte(path, i)) then return path:sub(i + 1) end
  end
  return path
end

M.basename = M.tail

---@param path string
---@param remove_trailing boolean?
---@return string?
M.parent = function(path, remove_trailing)
  path = M.remove_trailing(path)
  for i = #path, 1, -1 do
    if M.byte_is_separator(string_byte(path, i)) then
      local parent = path:sub(1, i)
      if remove_trailing then parent = M.remove_trailing(parent) end
      return parent
    end
  end
end

---@param path string
---@return string
M.normalize = function(path)
  local p = M.tilde_to_HOME(path)
  if _G.is_win then p = (p:gsub([[\]], [[/]])) end
  return p
end

---@param p1 string
---@param p2 string
---@return boolean
M.equals = function(p1, p2)
  p1 = M.normalize(M.remove_trailing(p1))
  p2 = M.normalize(M.remove_trailing(p2))
  if _G.is_win then
    p1 = string.lower(p1)
    p2 = string.lower(p2)
  end
  return p1 == p2
end

---@param path string
---@param relative_to string
---@return boolean, string?
M.is_relative_to = function(path, relative_to)
  local path_no_trailing = M.tilde_to_HOME(path)
  path = M.add_trailing(path_no_trailing)
  relative_to = M.add_trailing(M.tilde_to_HOME(relative_to))
  local pidx, ridx = 1, 1
  repeat
    local pbyte = string_byte(path, pidx)
    local rbyte = string_byte(relative_to, ridx)
    if M.byte_is_separator(pbyte) and M.byte_is_separator(rbyte) then
      repeat
        pidx = pidx + 1
      until not M.byte_is_separator(string_byte(path, pidx))
      repeat
        ridx = ridx + 1
      until not M.byte_is_separator(string_byte(relative_to, ridx))
    elseif
      _G.is_win and pbyte and rbyte and string.char(pbyte):lower() == string.char(rbyte):lower()
      or pbyte == rbyte
    then
      pidx = pidx + 1
      ridx = ridx + 1
    else
      return false, nil
    end
  until ridx > #relative_to
  return true, pidx <= #path_no_trailing and path_no_trailing:sub(pidx) or '.'
end

---@param path string
---@param relative_to string
---@return string
M.relative_to = function(path, relative_to)
  local is_relative_to, relative_path = M.is_relative_to(path, relative_to)
  return is_relative_to and relative_path or path
end

---@param path string
---@param no_tail boolean?
---@return string?
M.extension = function(path, no_tail)
  local file = no_tail and path or M.tail(path)
  for i = #file, 1, -1 do
    if string_byte(file, i) == M.dot_byte then return file:sub(i + 1) end
  end
end

---@param paths string[]
---@return string
M.join = function(paths)
  local separator = M.separator(paths[1])
  local ret = ''
  for i = 1, #paths do
    local p = paths[i]
    if p then
      if i < #paths and not M.ends_with_separator(p) then p = p .. separator end
      ret = ret .. p
    end
  end
  return ret
end

M.HOME = function()
  if not M.__HOME then M.__HOME = if_win(os.getenv('USERPROFILE'), os.getenv('HOME')) end
  return M.__HOME
end

---@param path string
---@return string
M.tilde_to_HOME = function(path) return (path:gsub('^~', M.HOME())) end

---@param path string
---@return string
M.HOME_to_tilde = function(path)
  if _G.is_win then
    local home = M.HOME()
    if path:sub(1, #home):lower() == home:lower() then path = '~' .. path:sub(#home + 1) end
  else
    path = path:gsub('^' .. vim.pesc(M.HOME()), '~')
  end
  return path
end

---@param str string
---@param start_idx integer
---@return integer?
local function find_next_separator(str, start_idx)
  local SEPARATOR_BYTES = if_win({ M.fslash_byte, M.bslash_byte }, { M.fslash_byte })
  for i = start_idx or 1, #str do
    for _, byte in ipairs(SEPARATOR_BYTES) do
      if string_byte(str, i) == byte then return i end
    end
  end
end

---@param s string
---@param i? integer
---@return integer?
local function utf8_char_len(s, i)
  local c = string_byte(s, i or 1)
  if not c then
    return
  elseif c > 0 and c <= 127 then
    return 1
  elseif c >= 194 and c <= 223 then
    return 2
  elseif c >= 224 and c <= 239 then
    return 3
  elseif c >= 240 and c <= 244 then
    return 4
  end
end

---@param s string
---@param from integer
---@param to? integer
---@return string
local function utf8_sub(s, from, to)
  local ret = ''
  local byte_i, utf8_i = from, from
  while byte_i <= #s and (not to or utf8_i <= to) do
    local c_len = utf8_char_len(s, byte_i) ---@cast c_len-?
    local c = string_sub(s, byte_i, byte_i + c_len - 1)
    ret = ret .. c
    byte_i = byte_i + c_len
    utf8_i = utf8_i + 1
  end
  return ret
end

M.shorten = function(path, max_len, sep)
  sep = sep or M.separator(path)
  local parts = {}
  local start_idx = 1
  max_len = max_len and tonumber(max_len) > 0 and max_len or 1
  if _G.is_win and M.is_absolute(path) then
    table.insert(parts, path:sub(1, 2))
    start_idx = 4
  end
  repeat
    local i = find_next_separator(path, start_idx)
    local end_idx = i and start_idx + math.min(i - start_idx, max_len) - 1 or nil
    local part = utf8_sub(path, start_idx, end_idx) ---@cast i-?
    if end_idx and part == '.' and i - start_idx > 1 then
      part = utf8_sub(path, start_idx, end_idx + 1)
    end
    table.insert(parts, part)
    if i then start_idx = i + 1 end
  until not i
  return table.concat(parts, sep)
end

M.lengthen = function(path)
  local separator = M.separator(path)
  local glob_expr = require('mterm.escape').glob(path)
  local glob_expr_prefix = ''
  if M.is_absolute(path) then
    if _G.is_win then
      glob_expr_prefix = glob_expr:sub(1, 3)
      glob_expr = glob_expr:sub(4)
    else
      glob_expr_prefix = glob_expr:sub(1, 1)
      glob_expr = glob_expr:sub(2)
    end
  end
  glob_expr = glob_expr_prefix .. glob_expr:gsub(separator, '%*' .. separator)
  return fn.glob(glob_expr):match('[^\n]+')
    or string.format("<glob expand failed for '%s'>", glob_expr)
end

---@param str string
---@return boolean
M.is_uri = function(str) return str:match('^[%a%-]+://') ~= nil end

return M
