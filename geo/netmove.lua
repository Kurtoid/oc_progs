local robot = require("robot")
local mt = require("minitel")
local ser = require("serialization")
local directions = {north = {x = 0, y = 0, z = -1, left = "west", right = "east", back="south"},
                    south = {x = 0, y = 0, z = 1, right = "west", left = "east", back="north"},
                    east = {x = 1, y = 0, z = 0, left = "north", right = "south", back="west"},
                    west = {x = -1, y = 0, z = 0, left = "south", right = "north", back="east"}, up = {x = 0, y = 1, z = 0},
                    down = {x = 0, y = -1, z = 0}}

local compasspoints = {north=0, east=1, south=2, west=3}
local netmove = {}

function new_netmove(position, orientation)
  local o = {}
  setmetatable(o, {__index = netmove})
  o.current_position = position
  o.current_direction = orientation
  return o
end

function netmove:forward()
  local result = robot.forward()
  if result == true then
    local current_direction = directions[self.current_direction]
    self.current_position.x = self.current_position.x + current_direction.x
    self.current_position.y = self.current_position.y + current_direction.y
    self.current_position.z = self.current_position.z + current_direction.z
  end
  return result
end

function netmove:backward()
  local result = robot.back()
  if result == true then
    local back_direction = directions[self.current_direction].back
    back_direction = directions[back_direction]
    self.current_position.x = self.current_position.x + back_direction.x
    self.current_position.y = self.current_position.y + back_direction.y
    self.current_position.z = self.current_position.z + back_direction.z
  end
  return result
end

function netmove:turnLeft()
  robot.turnLeft()
  self.current_direction = directions[self.current_direction].left
end

function netmove:turnRight()
  robot.turnRight()
  self.current_direction = directions[self.current_direction].right
end

function netmove:moveUp()
  local result = robot.up()
  self.current_position.y = self.current_position.y + 1
  return result
end

function netmove:moveDown()
  local result = robot.down()
  self.current_position.y = self.current_position.y - 1
  return result
end

-- TODO: verify that this works
function netmove:face(direction)
  local diff = compasspoints[direction] - compasspoints[self.current_direction]
  if diff < 0 then diff = diff + 4 end
  if diff == 0 then
    return true
  end
  if diff == 1 then
    return self:turnRight()
  end
  if diff == 2 then
    local result = nil
    result = self:turnRight()
    result = self:turnRight() or result
    return result
  end
  if diff == 3 then
    return self:turnLeft()
  end
end

function netmove:getpath(start, stop)
  local message = {type="nav_request", start_pos=start, end_pos=stop}
  local message_str = ser.serialize(message)
  mt.rsend("geo_server", 2, message_str)
  -- wait for a stream
  local stream = mt.listen(3)
  -- the path will be in multiple chunks, ending with an EOF
  local message = ''
  local chunk = ''
  while true do
    chunk = stream:read("*a")
    os.sleep()
    message = message .. chunk
    -- check if the last 3 characters are 'EOF'
    if #message >= 3 and string.sub(message, #message - 2, #message) == 'EOF' then
      -- remove the 'EOF'
      message = message:sub(1, #message - 3)
      -- exit loop
      break
    end
  end
  -- close the stream
  stream:close()
  -- deserialize the message
  local message = ser.unserialize(message)
  return message
end

function netmove:gettsp(position, corner1, corner2)
  local message = {type='tsp_request', corner1=corner1, corner2=corner2, start_pos = position}
  local message_str = ser.serialize(message)
  mt.rsend("geo_server", 2, message_str)
  -- wait for a stream
  local stream = mt.listen(3)
  -- TODO: move chunk recieving to a function
  -- the path will be in multiple chunks, ending with an EOF
  local message = ''
  local chunk = ''
  while true do
    chunk = stream:read("*a")
    os.sleep()
    message = message .. chunk
    -- check if the last 3 characters are 'EOF'
    if #message >= 3 and string.sub(message, #message - 2, #message) == 'EOF' then
      -- remove the 'EOF'
      message = message:sub(1, #message - 3)
      -- exit loop
      break
    end
  end
  -- close the stream
  stream:close()
  -- deserialize the message
  local message = ser.unserialize(message)
  return message
end

function manhattan_dist(p1, p2)
  return math.abs(p1.x - p2.x) + math.abs(p1.y - p2.y) + math.abs(p1.z - p2.z)
end

function netmove:do_path_step(p1, p2)
  -- if manhattan_dist(p1, p2) ~= 1 then
  --   error("p1 and p2 in do_path_step should be 1 block apart")
  -- end
  local y_diff = p2.y - p1.y
  if y_diff == 1 then
    return self:moveUp()
  end
  if y_diff == -1 then
    return self:moveDown()
  end
  local x_diff = p2.x - p1.x
  if x_diff == 1 then
    self:face("east")
    return self:forward()
  end
  if x_diff == -1 then
    self:face("west")
    return self:forward()
  end
  local z_diff = p2.z - p1.z
  if z_diff == -1 then
    self:face("north")
    return self:forward()
  end
  if z_diff == 1 then
    self:face("south")
    return self:forward()
  end
  print("how did we get here?")
  print("p1: " .. p1.x .. "," .. p1.y .. "," .. p1.z)
  print("p2: " .. p2.x .. "," .. p2.y .. "," .. p2.z)
  return
end

function netmove:followPath(path)
  print("got path of length " .. #path)
  -- make sure the first position on the path is _our_ position
  if path[1][1] ~= self.current_position.x or path[1][2] ~= self.current_position.y or path[1][3] ~= self.current_position.z then
    error("The first position on the path is not our current position")
  end
  for i = 1, #path - 1 do
    local current_position = path[i]
    current_position = {x=current_position[1], y=current_position[2], z=current_position[3]}
    local next_position = path[i + 1]
    next_position = {x=next_position[1], y=next_position[2], z=next_position[3]}
    print("moving from " .. current_position.x .. "," .. current_position.y .. "," .. current_position.z .. " to " .. next_position.x .. "," .. next_position.y .. "," .. next_position.z)
    local result = self:do_path_step(current_position, next_position)
    if result == false then
      error("Failed to move to next position")
      -- TODO: recovery
      break
    end
  end
  print("path done!")
end
