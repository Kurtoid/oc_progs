local cpt = require("component")
local geo = cpt.proxy(cpt.geolyzer.address)
local event = require("event")
local ser = require("serialization")
local mt = require("minitel")
local computer = require("computer")
require("octree")

local geolysers = {bounds= {x={nil,nil}, y={nil,nil}, z={nil,nil}},
                   data= new_octree()}

local BLK_CLEAR = 0
local BLK_BLOCKED = 1
local BLK_UNMAPPED = -1

function is_blocked(blk)
  if blk ~= BLK_CLEAR then
    return true
  end
  return false
end

--- check if a point is within a map
---@param x number x in global coordinates
---@param y number y in global coordinates
---@param z number z in global coordinates
---@param map table
function is_point_in_bounds(x, y, z, map)
  local bounds = map['bounds']
  if x >= bounds['x'][1] and x <= bounds['x'][2] and y > bounds['y'][1] and y < bounds['y'][2] and z >= bounds['z'][1] and
      z <= bounds['z'][2] then
    return true
  end
end

--- use the availible geolyser data
function get_block(x, y, z)
  x = math.floor(x)
  y = math.floor(y)
  z = math.floor(z)
  -- print(x, y, z)
  -- print(map['data'][x][z][y])
  if x == nil or z == nil or y == nil then
    return BLK_UNMAPPED
  end
  local blk = geolysers['data']:get(x, y, z)

  if blk ~= BLK_CLEAR and blk ~= nil then
    return blk
  end
  return BLK_CLEAR
end

function clear_block(x, y, z)
  local x = x - geolysers['bounds']['x'][1]
  local y = y - geolysers['bounds']['y'][1]
  local z = z - geolysers['bounds']['z'][1]
  -- print(x, y, z)
  -- print(map['data'][x][z][y])
  if x == nil or z == nil or y == nil then
    return
  end
  geolysers['data']:set(x, y, z, BLK_CLEAR)
end

function manhattan_dist(start_pos, end_pos)
  return math.abs(start_pos[1] - end_pos[1]) + math.abs(start_pos[2] - end_pos[2]) + math.abs(start_pos[3] - end_pos[3])
end

-- A STAR CODE -- 

function reconstruct_path(came_from, current_node)
  local path = {}
  while current_node do
    table.insert(path, current_node)
    current_node = came_from[current_node]
  end
  -- reverse the path
  local path_rev = {}
  for i = #path, 1, -1 do
    table.insert(path_rev, path[i])
  end
  return path_rev
end

function get_neighbors(pos)
  local neighbors = {}
  local dx = {-1, 1, 0, 0, 0, 0}
  local dy = {0, 0, -1, 1, 0, 0}
  local dz = {0, 0, 0, 0, -1, 1}
  for i = 1, 6 do
    local nx = pos[1] + dx[i]
    local ny = pos[2] + dy[i]
    local nz = pos[3] + dz[i]
    if get_block(nx, ny, nz) <= BLK_CLEAR then
      table.insert(neighbors, {nx, ny, nz})
    end
  end
  return neighbors
end

function table_contains(table, element)
  for i, e in ipairs(table) do
    if e[1] == element[1] and e[2] == element[2] and e[3] == element[3] then
      return true
    end
  end
  return false
end

function index_of(table, element)
  for i, e in ipairs(table) do
    if e[1] == element[1] and e[2] == element[2] and e[3] == element[3] then
      return i
    end
  end
  return -1
end

function a_star(start_pos, end_pos)
  local closed_set = {}
  local open_set = {}
  local came_from = {}
  local g_score = {}
  local f_score = {}
  local start_node = {start_pos[1], start_pos[2], start_pos[3]}
  local end_node = {end_pos[1], end_pos[2], end_pos[3]}
  table.insert(open_set, start_node)
  g_score[start_node] = 0
  f_score[start_node] = manhattan_dist(start_node, end_node)
  while #open_set > 0 do
    local current = open_set[1]
    for i, node in ipairs(open_set) do
      if f_score[node] < f_score[current] then
        current = node
      end
    end
    if current[1] == end_node[1] and current[2] == end_node[2] and current[3] == end_node[3] then
      return reconstruct_path(came_from, current)
    end
    table.remove(open_set, index_of(open_set, current))
    table.insert(closed_set, current)
    local neighbors = get_neighbors(current)
    for i, neighbor in ipairs(neighbors) do
      if not table_contains(closed_set, neighbor) then
        local tentative_g_score = g_score[current] + 1
        if not table_contains(open_set, neighbor) then
          table.insert(open_set, neighbor)
        elseif g_score[neighbor] ~= nil and tentative_g_score >= g_score[neighbor] then
          goto continue
        end
        came_from[neighbor] = current
        g_score[neighbor] = tentative_g_score
        f_score[neighbor] = g_score[neighbor] + manhattan_dist(neighbor, end_node)
      end
      ::continue::
    end
  end
  return nil
end
-- END A STAR CODE --

-- SURFACE TSP CODE --
--- get a list of all the sky-facing blocks within the selected bounds
function top_blocks_for_bounds(bounds)
  print("getting top blocks for bounds")
  print(bounds['x'][1], bounds['x'][2], bounds['y'][1], bounds['y'][2], bounds['z'][1], bounds['z'][2])
  local top_blocks = {}
  -- for each column within the bounds
  for x = bounds['x'][1], bounds['x'][2] do
    -- for each row within the bounds
    for z = bounds['z'][1], bounds['z'][2] do
      -- for each block within the bounds
      for y = bounds['y'][2] - 1, bounds['y'][1], -1 do
        local blk = get_block(x, y, z)
        -- if block is solid and not unmapped
        if blk ~= BLK_CLEAR and blk ~= BLK_UNMAPPED then
          -- if block above is not unmapped
          if get_block(x, y + 1, z) ~= BLK_UNMAPPED then
            table.insert(top_blocks, {x, y + 1, z})
          end
          break
        end
      end
    end
  end
  return top_blocks
end

function top_block_for_xz(x, z)
  local bounds = get_known_bounds()
  for y = bounds['y'][2] - 1, bounds['y'][1], -1 do
    local blk = get_block(x, y, z)
    if blk ~= BLK_CLEAR and blk ~= BLK_UNMAPPED then
      if get_block(x, y + 1, z) ~= BLK_UNMAPPED then
        return y + 1
      end
    end
  end
end

function nearest_neighbor_tsp(top_blocks)
  local path = {}
  local visited = {}
  table.insert(path, {1, 0})
  visited[1] = true
  while #visited < #top_blocks do
    local nearest = nil
    local nearest_cost = math.huge
    for i, block in ipairs(top_blocks) do
      if not visited[i] then
        -- local cost = cost_mat[path[#path][1]][i]
        local cost = manhattan_dist(top_blocks[path[#path][1]], block)
        if cost == nil then
          cost = math.huge
        end
        if cost < nearest_cost then
          nearest = i
          nearest_cost = cost
        end
      end
    end
    table.insert(path, {nearest, nearest_cost})
    visited[nearest] = true
  end
  local pt_path = {}
  for i = 1, #path do
    table.insert(pt_path, top_blocks[path[i][1]])
  end
  return pt_path
end
-- 
function fill_path(path)
  local paths = {}
  local current_path = {}
  for i, block in ipairs(path) do
    if i == #path then
      -- don't do the last block, since we'd run out of bounds
      break
    end
    -- run a_star between i and i+1, and add the result to the new path
    -- print("running a_star on ", i)
    if block == nil or path[i + 1] == nil then
      print("block or next block is nil")
      break
    end
    local new_path_part = a_star(block, path[i + 1])
    if new_path_part == nil then
      -- print("breaking path into chunks")
      table.insert(paths, current_path)
      current_path = {}
    else
      for j, block in ipairs(new_path_part) do
        if j == #new_path_part then
          break
        end

        table.insert(current_path, block)
      end
    end
  end
  if #current_path > 0 then
    table.insert(paths, current_path)
  end
  return paths
end

-- END TSP CODE --

function add_map(map)
  -- map['data'] is a serialized octree
  map['data'] = new_octree_from_root(map['data'])
  -- for each block in map, add it to the octree
  -- since we don't have a octree join, iterate through the boundary space
  for x = map['bounds']['x'][1], map['bounds']['x'][2] do
    for y = map['bounds']['y'][1], map['bounds']['y'][2] do
      for z = map['bounds']['z'][1], map['bounds']['z'][2] do
        -- map['data'] is in local coordinates (centered around bounds)
        -- we need to put these into global coordinates
        local blk = map['data']:get(x - map['bounds']['x'][1], y - map['bounds']['y'][1], z - map['bounds']['z'][1])
        geolysers['data']:set(x, y, z, blk)
      end
    end
  end

  -- update the bounds
  -- for each dimension
  for dim, bounds in pairs(map['bounds']) do
    -- for each bound
    for i, bound in ipairs(bounds) do
      if geolysers['bounds'][dim][1] == nil or geolysers['bounds'][dim][1] > bound then
        geolysers['bounds'][dim][1] = bound
      end
      if geolysers['bounds'][dim][2] == nil or geolysers['bounds'][dim][2] < bound then
        geolysers['bounds'][dim][2] = bound
      end
    end
  end
end

function get_known_bounds()
  return geolysers['bounds']
end

-- BEGIN HOLO FUNCTIONS
local hologram = cpt.proxy(cpt.hologram.address)
function display_known_maps()
  print('displaying hologram')
  hologram.clear()
  local bounds = get_known_bounds()
  print('bounds: ', bounds)
  local x_range = bounds['x'][2] - bounds['x'][1]
  local y_range = bounds['y'][2] - bounds['y'][1]
  local z_range = bounds['z'][2] - bounds['z'][1]
  local max_xz_range = math.max(x_range, z_range)
  local x_offset = bounds['x'][1]
  local y_offset = bounds['y'][1]
  local z_offset = bounds['z'][1]
  print(bounds['x'][1], bounds['x'][2], bounds['y'][1], bounds['y'][2], bounds['z'][1], bounds['z'][2])
  for x = 1, 48 do
    for z = 1, 48 do
      for y = 1, 32 do
        local x_pos = ((x - 1) * max_xz_range / 48.0) + x_offset
        local z_pos = ((z - 1) * max_xz_range / 48.0) + z_offset
        local y_pos = ((y - 1) * y_range / 32.0) + y_offset
        local blk = get_block(x_pos, y_pos, z_pos)
        local show_block = blk ~= BLK_CLEAR and blk ~= BLK_UNMAPPED
        hologram.set(x, y, z, show_block)
        -- os.sleep()

        if computer.energy() / computer.maxEnergy() < 0.2 then
          os.sleep(1)
        end
      end
    end
  end
end


function pathfinding_demo()
  local bounds = get_known_bounds()
  local top_blocks = top_blocks_for_bounds(bounds)
  print("top blocks: ", #top_blocks)
  local path = nearest_neighbor_tsp(top_blocks)
  local new_paths = fill_path(path)
  print("found paths: ", #new_paths)
  -- DEBUG: save the path to a file
  local file = io.open('path.txt', 'w')
  for path_index, path in ipairs(new_paths) do
    for i, block in ipairs(path) do
      file:write(block[1], ' ', block[2], ' ', block[3], '\n')
    end
    file:write('\n')
  end
  file:close()
end

-- END HOLO FUNCTIONS
function read_block_stream(from)
  print('opening stream from ', from)
  local stream = mt.open(from, 3)
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
  print('got message')
  stream:close()
  print('closed stream')
  local packet = ser.unserialize(message)
  add_map(packet['map'])
  display_known_maps()
  -- pathfinding_demo()
end

function handle_nav_request(packet, from)
  local start_pos = packet['start_pos']
  local end_pos = packet['end_pos']
  local path = nil
  local error_message = nil
  -- the y position for end_pos is optional - if so, get the corresponding top block for that xz
  if end_pos.y == nil then
    end_pos.y = top_block_for_xz(end_pos.x, end_pos.z)
    if end_pos.y == nil then
      error_message = 'no top block for xz'
      goto error
    end
  end
  print("planning from ", start_pos.x, start_pos.y, start_pos.z, " to ", end_pos.x, end_pos.y, end_pos.z)
  -- geolysers might consider the robot to be a block, so clear the robot's position
  clear_block(start_pos.x, start_pos.y, start_pos.z)
  -- clear the end position
  clear_block(end_pos.x, end_pos.y, end_pos.z)
  path = a_star({start_pos.x, start_pos.y, start_pos.z}, {end_pos.x, end_pos.y, end_pos.z})
  -- the path could be very large, so send it over a stream
  -- the client should be listening
  ::error::
  local stream = mt.open(from, 3)
  if stream == nil then
    print('could not open stream to ', from)
  end
  local message = ser.serialize({path = path, error_message = error_message})
  message = message .. 'EOF'
  stream:write(message)
  stream:close()
  print("path sent to ", from, ": ", #path)
end

local host_packets = {}
function msg_recieve(_, from, port, data)
  xpcall(function()
    if port == 2 and data == 'open_block_stream' then
      read_block_stream(from)
    elseif port == 2 then
      local packet = ser.unserialize(data)
      -- throw away unreadable packets
      if packet == nil then
        return
      end
      if packet['type'] == 'nav_request' then
        handle_nav_request(packet, from)
      end
    end
  end, function(err)
    print('error: ', err)
    print(debug.traceback())
  end)
end

function send_scan_request()
  local msg = {action = "scan"}
  msg = ser.serialize(msg)
  mt.usend("~", 1, msg)
end
 
local event_handlers = {}
function main()
  -- display_known_maps()
  table.insert(event_handlers, event.listen("net_msg", msg_recieve))
  -- send_scan_request()
  event.pull("interrupted")
  print("interrupted")
  for i, handler in ipairs(event_handlers) do
    event.cancel(handler)
  end
end
main()
