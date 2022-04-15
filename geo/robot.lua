local netmove = require("netmove")

local start_location = {x = 141, y = 69, z = 17}
local nm = new_netmove(start_location, "east")

local path = nm:getpath(start_location, {x=start_location.x + 8, z=start_location.z})
print("response: ", path)
print("got fields")
for k,v in pairs(path) do
  print(k,v)
end
nm:followPath(path)