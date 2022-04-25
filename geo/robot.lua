local netmove = require("netmove")

local start_location = {x = 141, y = 70, z = 16}
local nm = new_netmove(start_location, "east")

-- local path = nm:getpath(start_location, {x=start_location.x + 8, z=start_location.z})
local path = nm:gettsp(start_location, {x=start_location.x + 4, z=start_location.z+4, y=start_location.y+4}, {x=start_location.x - 4, z=start_location.z-4, y=start_location.y-4})
print("response: ", path)
print("got fields")
for k,v in pairs(path) do
  print(k,v)
end
nm:followPath(path['path'])