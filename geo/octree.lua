-- stolen/borrowed from https://github.com/mentlerd/GM13-Ramblings/blob/master/octree.lua
-- The MIT License (MIT)
-- Copyright (C) 2014 David Mentler
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software
-- and associated documentation files (the "Software"), to deal in the Software without restriction,
-- including without limitation the rights to use, copy, modify, merge, publish, distribute,
-- sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- - The above copyright notice and this permission notice shall be included in all copies 
--    or substantial portions of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING 
-- BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
-- DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
local TREE = {}

TREE.__index = TREE

function new_octree()
  local tree = {root = {size = 1, x = 0, y = 0, z = 0}}

  setmetatable(tree, TREE)
  return tree
end

function new_octree_from_root(root)
  local tree = {root = root.root}

  setmetatable(tree, TREE)
  return tree
end

-- Tree metatable
function TREE:expandIfNeeded(x, y, z)
  local root = self.root

  local size = root.size

  -- Relative coordinates
  local rX = x - root.x
  local rY = y - root.y
  local rZ = z - root.z

  -- Out of bounds marks
  local xPos = rX >= size
  local xNeg = rX < -size

  local yPos = rY >= size
  local yNeg = rY < -size

  local zPos = rZ >= size
  local zNeg = rZ < -size

  -- Check if the point is in the bounds
  if (xPos or xNeg or yPos or yNeg or zPos or zNeg) then

    -- Change the root node to fit
    local node = {size = size * 2, x = 0, y = 0, z = 0}

    local index = 0

    -- Offset the new root, and place the old into it
    if (rX >= 0) then
      node.x = root.x + size
    end
    if (rY >= 0) then
      node.y = root.y + size
    end
    if (rZ >= 0) then
      node.z = root.z + size
    end

    if (rX < 0) then
      node.x = root.x - size
      index = index + 1
    end
    if (rY < 0) then
      node.y = root.y - size
      index = index + 2
    end
    if (rZ < 0) then
      node.z = root.z - size
      index = index + 4
    end

    node[index] = root

    -- Earse previous root information
    root.size = nil
    root.x = nil
    root.y = nil
    root.z = nil

    -- Set the new root
    self.root = node

    -- Repeat until the size is sufficient
    self:expandIfNeeded(x, y, z)
  end
end

function TREE:get(x, y, z)
  self:expandIfNeeded(x, y, z)

  -- Convert the coordinates relative to the root
  local node = self.root
  local size = node.size

  local rX = x - node.x
  local rY = y - node.y
  local rZ = z - node.z

  while (true) do
    size = size / 2

    local index = 0

    -- Seek, and offset the point for the next node
    if (rX >= 0) then
      index = index + 1
      rX = rX - size
    else
      rX = rX + size
    end

    if (rY >= 0) then
      index = index + 2
      rY = rY - size
    else
      rY = rY + size
    end

    if (rZ >= 0) then
      index = index + 4
      rZ = rZ - size
    else
      rZ = rZ + size
    end

    -- Get the node/value at the calculated index
    local child = node[index]

    if (type(child) ~= "table") then
      return child
    end

    -- We must go deeper!
    node = child
  end
end

local function mergeIfCan(stack, path, ref)

  for i = #stack, 1, -1 do
    local node = stack[i]

    -- Check if every value is the same in the node		
    for x = 0, 7, 1 do
      if (ref ~= node[x]) then
        -- Break if any is not
        return
      end
    end

    -- Successful merge
    stack[i - 1][path[i]] = ref
  end

end

function TREE:set(x, y, z, value)
  self:expandIfNeeded(x, y, z)

  -- Convert the coordinates relative to the root
  local node = self.root
  local size = node.size

  local rX = x - node.x
  local rY = y - node.y
  local rZ = z - node.z

  local stack = {}
  local path = {}

  while (true) do
    size = size / 2

    local index = 0

    if (rX >= 0) then
      index = index + 1
      rX = rX - size
    else
      rX = rX + size
    end

    if (rY >= 0) then
      index = index + 2
      rY = rY - size
    else
      rY = rY + size
    end

    if (rZ >= 0) then
      index = index + 4
      rZ = rZ - size
    else
      rZ = rZ + size
    end

    table.insert(stack, node)
    table.insert(path, index)

    -- Get the node/value at the calculated index
    local child = node[index]
    if (type(child) ~= "table") then

      if (child ~= value) then

        -- No node/value present
        if (child == nil) then

          -- If the size is not 1, it needs further populating,
          -- Otherwise, it just needs a value
          if (size ~= 0.5) then
            child = {}
            node[index] = child
          else
            node[index] = value

            mergeIfCan(stack, path, value)
            return
          end
        else

          -- There is a node, but its value does not match, divide it
          -- If the size is over 1, otherwise, just set the value
          if (size ~= 0.5) then
            local split = {child, child, child, child, child, child, child, child}

            child = split
            node[index] = split
          else
            -- Hit a real leaf, set the value and walk away
            node[index] = value

            mergeIfCan(stack, path, value)
            return
          end
        end
      else
        -- This treenode already has the same value, nothing to do
        return
      end
    end
    node = child
  end
end
