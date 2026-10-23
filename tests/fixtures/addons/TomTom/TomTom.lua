-- Test double of TomTom: AddWaypoint(mapID, x, y, opts) -> uid, RemoveWaypoint(uid).
TomTom = { waypoints = {} }
function TomTom:AddWaypoint(map, x, y, opts)
  -- the real one computes with x and y at once (TomTom.lua GetKeyArgs): fail the same way
  local _ = x * 10000 + y * 10000 + map
  local uid = { map = map, x = x, y = y, title = opts and opts.title }
  self.waypoints[#self.waypoints + 1] = uid
  return uid
end
function TomTom:RemoveWaypoint(uid)
  for i = #self.waypoints, 1, -1 do
    if self.waypoints[i] == uid then
      table.remove(self.waypoints, i)
    end
  end
end
