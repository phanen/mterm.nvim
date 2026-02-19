local uv = vim.uv

local M = {}

---@return string
M.cwd = function() return (assert(uv.cwd())) end

---deep merge applied from left to right (left-associative)
---treat `vim.islist` element as trivial val (override left one by deepcopied right one)
---no modification to the origin table
---@generic T: table
---@param ... T|{}
---@return T
M.merge = function(...)
  return vim.tbl_deep_extend('force', ...) -- nlua: ignore
end

--- @param x any
--- @return integer?
M.tointeger = function(x)
  local nx = tonumber(x)
  if nx and nx == math.floor(nx) then
    --- @cast nx integer
    return nx
  end
end

return M
