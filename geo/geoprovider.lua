local cpt = require("component")
local geo = cpt.proxy(cpt.geolyzer.address)
local computer = require("computer")
local mt = require("minitel")
local event = require("event")
local ser = require("serialization")
require("octree")

local geo_range = 9 -- for now
local geo_vert_range = 32

local geolyzers = {}
local geolyser_data = {}
local hostname = os.getenv()["HOSTNAME"]

-- temporary: location for single geolyzer
local geolyzer_location = {x = 142, y = 73, z = 10}
local geolyser_bounds = {x = {geolyzer_location['x'] - geo_range, geolyzer_location['x'] + geo_range},
                         y = {geolyzer_location['y'] - geo_vert_range, geolyzer_location['y'] + geo_vert_range},
                         z = {geolyzer_location['z'] - geo_range, geolyzer_location['z'] + geo_range}}

function scan_single_geolyzer(geolyzer)
  local octree = new_octree()

  for x = -geo_range, geo_range do
    print('row ' .. x)
    for z = -geo_range, geo_range do
      -- scan the whole column
      -- data[x + geo_range][z + geo_range] = geolyzer.scan(x, z)
      local scan_result = geolyzer.scan(x, z)
      for y = 1, #scan_result do
        local block = scan_result[y]
        if block >0.1 then
          octree:set(x + geo_range, y, z + geo_range, 1)
        -- else
        --   octree:set(x + geo_range, y, z + geo_range, 0)
        end

      end

    end
  end
  return octree
end

function dump_map_to_file(map)
  local file = io.open('map_out.txt', 'w')
  file:write(map)
  file:close()
end

function scan_and_send(from, port)
  print('scanning')
  -- TODO: use all geolyzers
  local data = scan_single_geolyzer(geo)
  local message = {action = 'scan_result', type = 'single_scan',
                   map = {data = data, bounds = geolyser_bounds, location = geolyzer_location, name = hostname}}
  print('serializing')
  message = ser.serialize(message)
  print('serialized to ' .. #message .. ' bytes')
  print('opening stream')
  mt.send('geo_server', 2, 'open_block_stream')
  local stream = mt.listen(3)
  if stream == nil then
    -- TODO: does listen ever time out?
    print('didn\'t get connection from main')
  end
  print('sending')
  stream:write(message)
  stream:write("EOF")
  print('closing stream')
  stream:close()
  print('done')
  dump_map_to_file(message)
end

local event_handlers = {}

local host_packets = {}

function msg_recieve(event, from, port, data)
  print("msg rec")
  if port == 1 then
    local packet = ser.unserialize(data)
    if (not packet) then
      return
    end
    if packet['action'] == 'scan' then
      scan_and_send(from, port)
    end
  end
end
function main()
  table.insert(event_handlers, event.listen("net_msg", msg_recieve))
  table.insert(event_handlers, event.listen("net_broadcast", msg_recieve))
  xpcall(function()
    scan_and_send("geo_server", 1)
  end, function(err)
    print(err)
    print(debug.traceback())
  end)
  -- wait forever for an interrupt signal
  local result = event.pull("interrupted")
  print("interrupted")
  -- cancel all event handlers
  for _, handler in pairs(event_handlers) do
    event.cancel(handler)
  end
end

main()
