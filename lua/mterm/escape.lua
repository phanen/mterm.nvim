local M = {}

---@param str string
---@return string
M.rg = function(str) return (str:gsub('[%(|%)|\\|%[|%]|%-|%{%}|%?|%+|%*|%^|%$|%.,]', '\\%1')) end

---@param str string
---@return string
M.lua_escape = function(str) return (str:gsub('%%', '%%%%')) end

---@param str string
---@return string
M.glob = function(str)
  return (str:gsub('[%{}[%]]', function(x) return [[\]] .. x end))
end

return M
