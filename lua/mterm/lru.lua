---START INJECT class/lru.lua

---@alias lru.key any

---@class lru.Node
---@field key lru.key
---@field prev lru.Node
---@field next lru.Node

---@class lru.Lru
---@field hash table<lru.key, lru.Node>
---@field head lru.Node
---@field size integer
local M = {}
M.__index = M

---@return lru.Lru
M.new = function()
  local head = {}
  head.next, head.prev = head, head
  return setmetatable({ hash = {}, head = head, size = 0 }, M)
end

---@param k lru.key
---@return lru.Node
function M:get(k) return self.hash[k] end

---@param k lru.key
---@param v any
function M:set(k, v) self.hash[k] = v end

---@param node lru.Node
function M:delete(node)
  self.hash[node.key] = nil
  node.prev.next = node.next
  node.next.prev = node.prev
  self.size = self.size - 1
end

---@param node lru.Node
---@param inserted table
function M:insert_after(node, inserted)
  inserted.next = node.next
  node.next.prev = inserted
  inserted.prev = node
  node.next = inserted
  self.hash[inserted.key] = inserted
  self.size = self.size + 1
end

---@param key lru.key
function M:access(key)
  local node = self.hash[key]
  if node then self:delete(node) end
  self:insert_after(self.head, node or { key = key })
end

---@param node lru.Node
---@param wrap? boolean
---@return lru.Node?
function M:next_of(node, wrap)
  local n = node.next
  return n ~= self.head and n or (wrap and self:next_of(n) or nil)
end

---@param node lru.Node
---@param wrap? boolean
---@return lru.Node?
function M:prev_of(node, wrap)
  local n = node.prev
  return n ~= self.head and n or (wrap and self:prev_of(n) or nil)
end

function M:pairs(reverse)
  local node = reverse and self.head.prev or self.head.next
  return function()
    if node == self.head then return end
    local key, cur = node.key, node
    node = reverse and node.prev or node.next
    return key, cur
  end
end

return M
