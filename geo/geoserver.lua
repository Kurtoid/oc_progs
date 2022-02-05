local cpt = require("component")
local geo = cpt.proxy(cpt.geolyzer.address)
local event = require("event")
local ser = require("serialization")
local mt = require("minitel")
local computer = require("computer")

local geolyzers = {}

local BLK_CLEAR = 0
local BLK_BLOCKED = 1
local BLK_UNMAPPED = 2

function is_blocked(blk)
  if blk == BLK_BLOCKED or blk == BLK_UNMAPPED then
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

function get_maps_for_point(x, y, z)
  local maps = {}
  for i, geolyzer in ipairs(geolyzers) do
    local map = geolyzer
    if is_point_in_bounds(x, y, z, map) then
      table.insert(maps, map)
    end
  end
  return maps
end

--- use the availible geolyser data
function get_block(x, y, z)
  x = math.floor(x)
  y = math.floor(y)
  z = math.floor(z)
  local maps = get_maps_for_point(x, y, z)
  if #maps == 0 then
    return BLK_UNMAPPED
  end
  for i, map in ipairs(maps) do
    local x = x - map['bounds']['x'][1]
    local y = y - map['bounds']['y'][1]
    local z = z - map['bounds']['z'][1]
    -- print(x, y, z)
    -- print(map['data'][x][z][y])
    local blk = map['data'][x][z][y]
    if blk ~= BLK_CLEAR then
      return blk
    end
  end
  return BLK_CLEAR
end

function manhattan_dist(start_pos, end_pos)
  return math.abs(start_pos[1] - end_pos[1]) + math.abs(start_pos[2] - end_pos[2]) + math.abs(start_pos[3] - end_pos[3])
end

function get_best_from_open_set(open_set)
  local best_dist = math.huge
  local best_node = nil
  for i, node in ipairs(open_set) do
    local dist = manhattan_dist(node.pos, node.goal)
    if dist < best_dist then
      best_dist = dist
      best_node = node
    end
  end
  return best_node
end

function reconstruct_path(came_from, current_node)
  local path = {}
  while current_node do
    table.insert(path, current_node)
    current_node = came_from[current_node.pos]
  end
  return path
end

function get_neighbors(pos)
  local neighbors = {}
  for i = -1, 1 do
    for j = -1, 1 do
      for k = -1, 1 do
        if i == 0 and j == 0 and k == 0 then
          -- don't include self
        else
          table.insert(neighbors, {x = pos[1] + i, y = pos[2] + j, z = pos[3] + k})
        end
      end
    end
  end
  return neighbors
end

function a_star(start_pos, end_pos)
  local open_set = {}
  local closed_set = {}
  local g_score = {}
  local f_score = {}
  local came_from = {}
  local start_node = {pos = start_pos, g_score = 0, f_score = manhattan_dist(start_pos, end_pos)}
  table.insert(open_set, start_node)
  g_score[start_pos] = 0
  f_score[start_pos] = start_node.f_score
  while #open_set > 0 do
    local current = get_best_from_open_set(open_set)
    if current.pos[1] == end_pos[1] and current.pos[2] == end_pos[2] and current.pos[3] == end_pos[3] then
      return reconstruct_path(came_from, current.pos)
    end
    table.remove(open_set, 1)
    table.insert(closed_set, current.pos)
    local neighbors = get_neighbors(current.pos)
    for i, neighbor in ipairs(neighbors) do
      if not is_blocked(get_block(neighbor[1], neighbor[2], neighbor[3])) then
        local tentative_g_score = g_score[current.pos] + 1
        if not g_score[neighbor] or tentative_g_score < g_score[neighbor] then
          came_from[neighbor] = current.pos
          g_score[neighbor] = tentative_g_score
          f_score[neighbor] = g_score[neighbor] + manhattan_dist(neighbor, end_pos)
          local node = {pos = neighbor, g_score = g_score[neighbor], f_score = f_score[neighbor]}
          table.insert(open_set, node)
        end
      end
    end
  end
end

function add_map(map)
  -- check if any geolyser has the same name
  -- if so, replace it. otherwise, add it
  local found = false
  for i, geolyzer in ipairs(geolyzers) do
    if geolyzer['name'] == map['name'] then
      geolyzers[i] = map
      found = true
      break
    end
  end
  if not found then
    table.insert(geolyzers, map)
  end
end

function get_known_bounds()
  local known_bounds = {x = {0, 0}, y = {0, 0}, z = {0, 0}}
  for i, map in ipairs(geolyzers) do
    local bounds = map['bounds']
    -- for each dimension
    for dim, bounds_dim in pairs(bounds) do
      -- for each bound
      for i, bound in ipairs(bounds_dim) do
        if known_bounds[dim][1] > bound then
          known_bounds[dim][1] = bound
        end
        if known_bounds[dim][2] < bound then
          known_bounds[dim][2] = bound
        end
      end
    end
  end
  return known_bounds
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
  local x_offset = bounds['x'][1]
  local y_offset = bounds['y'][1]
  local z_offset = bounds['z'][1]
  print(bounds['x'][1], bounds['x'][2], bounds['y'][1], bounds['y'][2], bounds['z'][1], bounds['z'][2])
  for x = 1, 48 do
    -- holo_data[x] = {}
    print('drawing row ', x)
    for z = 1, 48 do
      -- holo_data[x][z] = {}
      for y = 1, 32 do
        local x_pos = ((x - 1) * x_range / 48.0) + x_offset
        local z_pos = ((z - 1) * z_range / 48.0) + z_offset
        local y_pos = ((y - 1) * y_range / 32.0) + y_offset
        local blk = get_block(x_pos, y_pos, z_pos)
        -- set hologram if blk ~= clear or unmapped
        local show_block = blk ~= BLK_CLEAR and blk ~= BLK_UNMAPPED
        if blk == BLK_UNMAPPED then
          print('unmapped: ', x_pos, y_pos, z_pos)
        end
        hologram.set(x, y, z, show_block)
        if computer.energy() / computer.maxEnergy() < 0.2 then
          os.sleep(1)
        end
      end
    end
  end

end

-- END HOLO FUNCTIONS
local host_packets = {}
function msg_recieve(_, from, port, data)
  local packet = ser.unserialize(data)
  if not packet then
    -- this might be a fragment
    if (host_packets[from] == nil) then
      host_packets[from] = data
    else
      host_packets[from] = host_packets[from] .. data
      local try_deser = ser.unserialize(host_packets[from])
      if (try_deser) then
        packet = try_deser
        -- remove the packet from the queue
        host_packets[from] = nil
      end
    end
  end
  for k, v in pairs(packet) do
    print(k) -- ,v)
  end
  if packet['type'] == "single_scan" then
    print("got data")
    add_map(packet['map'])
    local result = xpcall(display_known_maps, function(err)
      print(err)
      print(debug.traceback())
    end)
  end
end

function send_scan_request()
  local msg = {action = "scan"}
  msg = ser.serialize(msg)
  mt.usend("~", 1, msg)
end

local event_handlers = {}
function main()
  table.insert(event_handlers, event.listen("net_msg", msg_recieve))
  send_scan_request()
  event.pull("interrupted")
  print("interrupted")
  for i, handler in ipairs(event_handlers) do
    event.cancel(handler)
  end
end
main()
