local robot = require("robot")
local component = require("component")
local geolyzer = component.proxy(component.geolyzer.address)
local current_position = {x = 0, y = 0, z = 0}

local directions = {north = {x = 0, y = 1, z = 0, left = "west", right = "east"},
                    south = {x = 0, y = -1, z = 0, right = "west", left = "east"},
                    east = {x = 1, y = 0, z = 0, left = "north", right = "south"},
                    west = {x = -1, y = 0, z = 0, left = "south", right = "north"}, up = {x = 0, y = 0, z = 1},
                    down = {x = 0, y = 0, z = -1}}

local current_direction = "north"

-- wrap the robot movement code to update the position
function forward()
  local result = robot.forward()
  if result == true then
    current_position.x = current_position.x + directions[current_direction].x
    current_position.y = current_position.y + directions[current_direction].y
    current_position.z = current_position.z + directions[current_direction].z
  end
  return result
end

function backward()
  local result = robot.back()
  if result == true then
    current_position.x = current_position.x + directions[current_direction].x
    current_position.y = current_position.y + directions[current_direction].y
    current_position.z = current_position.z + directions[current_direction].z
  end
  return result
end

function turnLeft()
  robot.turnLeft()
  current_direction = directions[current_direction].left
end

function turnRight()
  robot.turnRight()
  current_direction = directions[current_direction].right
end

function moveUp()
  local result = robot.up()
  current_position.z = current_position.z + 1
  return result
end

function moveDown()
  local result = robot.down()
  current_position.z = current_position.z - 1
  return result
end

function isOnGround()
  -- check if we're on the ground, ie the block below is not passable
  local result = robot.detectDown()
  if result == true then
    return true
  else
    return false
  end
end

function isAboveAll()
  return geolyzer.canSeeSky()
end

function isAtCeiling()
  return robot.detectUp() == true
end

--- if there's a block above us, try to get on top of it by moving backwards, up, and then forward
function getAboveAll(steps)
  if steps == nil then
    steps = 1
  end
  if steps > 3 then
    print('warning: recursion depth in getAboveAll()')
    return false
  end
  if isAboveAll() == true then
    return true
  end
  print("entered getAboveAll()")
  -- copy the current position - not used for now, but could be
  local original_position = {x = current_position.x, y = current_position.y, z = current_position.z}
  while isAboveAll() == false do
    -- move up until the block above isn't passable
    while isAtCeiling() == false do
      moveUp()
    end
    -- turn around and make sure we can back up
    turnLeft()
    turnLeft()
    if robot.detect() == true then
      -- there's another block in the way, so we're below a convex obstacle. this _shouldn't_ happen
      -- TODO
    end
    forward()
    turnRight()
    turnRight()
    local success = moveUp()
    if success == false then
      getAboveAll(steps+1)
    end
    -- move up until there's nothing in front
    while robot.detect() == true do
      local success = moveUp()
      if success == false then
        -- we've hit the ceiling, so we need to back up - again. recursion time
        getAboveAll(steps + 1)
        return
      end
    end
    -- move forward and try again
    forward()
  end
end

--- move forward, moving up or down if necessary
function safeMoveForward()
  if robot.detect() == true then
    while robot.detect() == true do
      moveUp()
    end
  end
  forward()
  getAboveAll()
  if robot.detectDown() == false then
    while robot.detectDown() == false do
      moveDown()
    end
  end
end

-- remove snow within a rectangle, where the robot is the bottom left corner
function clearArea(width, height)
  for x = 1, width do
    for y = 1, height do
      safeMoveForward()
    end
    if x % 2 == 1 then
      turnLeft()
    else
      turnRight()
    end
    safeMoveForward()
    if x % 2 == 1 then
      turnLeft()
    else
      turnRight()
    end
  end
end

function main()
  clearArea(10, 10)
end

main()
