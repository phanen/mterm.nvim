local api, uv = vim.api, vim.uv

local M = {}

---@return string
M.cwd = function() return (assert(uv.cwd())) end

local _NVIM_VERSION
---vim.version.parse should exist, since usually we check nightly feature
---@param version string
---@return boolean
M.has_version = function(version)
  _NVIM_VERSION = _NVIM_VERSION
    or vim.version.parse(api.nvim_exec2('version', { output = true }).output:match('NVIM (.-)\n'))
  return _NVIM_VERSION >= vim.version.parse(version)
end

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
