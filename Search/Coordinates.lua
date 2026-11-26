-- MapScout: a search for coordinates ("45 67", "Elwynn 42 65") gives one
-- result first: going to that point, on the named zone or the open map.
-- Search/Query.lua reads the numbers and the zone; this turns them into a
-- result. (Later, #98 makes it a query handler like any provider's.)

local _, ns = ...
local L = ns.L

local Coordinates = {}
ns.Coordinates = Coordinates

Coordinates.ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"

-- The result for the query's coordinates, or nil if there are none (or no
-- map to put them on). zoneMapID: the open map.
function Coordinates.Result(query, zoneMapID)
	local coords = query.coords
	local mapID = query.mapID or zoneMapID
	if not (coords and mapID) then
		return nil
	end
	local place = ns.MapPlace(mapID)
	local where = ("%.1f, %.1f"):format(coords.x * 100, coords.y * 100)
	local entry = {
		id = ("%d:%.4f:%.4f"):format(mapID, coords.x, coords.y),
		name = place and L.COORDS_GO_IN:format(where, place.name) or L.COORDS_GO:format(where),
		subtitle = L.COORDS_SUBTITLE,
		mapID = mapID,
		x = coords.x,
		y = coords.y,
		icon = Coordinates.ICON,
	}
	return {
		item = { key = "coordinates:" .. entry.id, provider = "coordinates", entry = entry, name = entry.name, weight = 1 },
		score = math.huge,
		inZone = zoneMapID ~= nil and (mapID == zoneMapID or ns.IsMapInside(mapID, zoneMapID)) or nil,
		noRemember = true, -- every point is different: not for frequency nor history
	}
end
