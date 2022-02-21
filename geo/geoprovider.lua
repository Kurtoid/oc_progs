local cpt = require("component")
local geo = cpt.proxy(cpt.geolyzer.address)
local computer = require("computer")
local mt = require("minitel")
local event = require("event")
local ser = require("serialization")

local geo_range = 4 -- for now
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
  local data = {}
  for x = -geo_range, geo_range do
    data[x + geo_range] = {}
    print('row ' .. x)
    for z = -geo_range, geo_range do
      -- scan the whole column
      data[x + geo_range][z + geo_range] = geolyzer.scan(x, z)
    end
  end
  return data
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
  print('opening stream')
  mt.send('geo_server', 2, 'open_block_stream')
  local stream = mt.listen(3)
  print('sending')
  -- write message in 1024 byte chunks
  for i = 1, #message, 1024 do
    local stop_pos = math.min(i + 1024-1, #message)
    stream:write(message:sub(i, stop_pos))
  end
  stream:write("EOF")
  print('closing stream')
  stream:close()
  print('done')
  dump_map_to_file(message)
end

local event_handlers = {}

local host_packets = {}

function msg_recieve(event, from, port, data)
  -- TODO: validate
  print("msg rec")
  local packet = ser.unserialize(data)
  if (not packet) then
    return
  end
  if packet['action'] == 'scan' then
    scan_and_send(from, port)
  end
end
function main()
  table.insert(event_handlers, event.listen("net_msg", msg_recieve))
  table.insert(event_handlers, event.listen("net_broadcast", msg_recieve))
  scan_and_send("geo_server", 1)
  -- wait forever for an interrupt signal
  local result = event.pull("interrupted")
  print("interrupted")
  -- cancel all event handlers
  for _, handler in pairs(event_handlers) do
    event.cancel(handler)
  end
end

main()
