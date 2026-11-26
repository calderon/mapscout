-- MapScout: going to a result (click on it, or Enter for the first one).
--   1. opens its map, if it isn't the open one (for a whole map, isMap, that's all)
--   2. shows the golden halo on the place, until the map closes or changes
--   3. only if the player turns them on (off by default, so nothing clashes
--      with Bridge's own pins): the game's map pin, tracking it (the on-screen
--      marker), and a TomTom waypoint (with Bridge loaded and no TomTom,
--      Bridge's TomTom turns it into a stop)
--   4. closes the list and leaves the box, so the map is free to use
--   5. remembers the choice: how often (ranking, #58) and recent (history, #59)

local _, ns = ...
local L = ns.L

local Waypoint = {}
ns.Waypoint = Waypoint

Waypoint.HISTORY_SIZE = 10

-- The map where the game allows a pin for this point: the point's own map or
-- the nearest map above it, with the point's position on that map.
function Waypoint.PinMap(mapID, x, y)
	if not (C_Map and C_Map.CanSetUserWaypointOnMap) then
		return nil
	end
	local id, px, py = mapID, x, y
	for _ = 1, 10 do
		if C_Map.CanSetUserWaypointOnMap(id) then
			return id, px, py
		end
		local info = C_Map.GetMapInfo(id)
		local parent = info and info.parentMapID
		if not parent or parent == 0 then
			return nil
		end
		px, py = ns.Preview.PositionOnMap(mapID, x, y, parent)
		if not px then
			return nil
		end
		id = parent
	end
	return nil
end

-- Sets the pins the player wants for a place. Returns the map of the game's
-- pin, or nil when it couldn't be set.
function Waypoint.Set(entry)
	local options = ns.db and ns.db.options.waypoint or {}
	local pinMap
	if options.native and UiMapPoint and C_Map.SetUserWaypoint then
		local mapID, x, y = Waypoint.PinMap(entry.mapID, entry.x, entry.y)
		if mapID then
			C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
			if options.superTrack and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
				C_SuperTrack.SetSuperTrackedUserWaypoint(true)
			end
			pinMap = mapID
		end
	end
	if options.tomtom and TomTom and TomTom.AddWaypoint then
		ns.API.SafeCall(TomTom.AddWaypoint, TomTom, entry.mapID, entry.x, entry.y,
			{ title = entry.name, from = "MapScout", persistent = false })
	end
	return pinMap
end

-- Remembers that the player chose this result (account: how often and when;
-- character: recent choices, newest first, without repeats).
function Waypoint.Remember(result, text)
	local key = result.item.key
	if ns.db then
		local frequency = ns.db.frequency[key] or { count = 0 }
		frequency.count = frequency.count + 1
		frequency.last = time()
		ns.db.frequency[key] = frequency
	end
	if ns.charDB then
		local history = ns.charDB.history
		for i = #history, 1, -1 do
			if history[i].key == key then
				table.remove(history, i)
			end
		end
		table.insert(history, 1, { key = key, text = text, name = result.item.entry.name, time = time() })
		for i = #history, Waypoint.HISTORY_SIZE + 1, -1 do
			history[i] = nil
		end
	end
end

-- Goes to a result. text: what the player had typed (for the history).
function Waypoint.Go(result, text)
	local entry = result.item.entry
	if not (entry.mapID and entry.x and entry.y) then
		return false
	end
	GameTooltip:Hide()
	if WorldMapFrame and WorldMapFrame:GetMapID() ~= entry.mapID then
		WorldMapFrame:SetMapID(entry.mapID) -- the list searches again for the new map...
	end
	ns.Results.Hide() -- ...and is closed after that
	if ns.SearchBar.box then
		ns.SearchBar.box:ClearFocus()
	end
	if entry.isMap then -- a whole map (a zone, a continent): opening it is all
		Waypoint.Remember(result, text)
		return true
	end
	local options = ns.db and ns.db.options.waypoint or {}
	if not Waypoint.Set(entry) and options.native then
		ns.Print(L.WAYPOINT_NOT_POSSIBLE:format(entry.name))
	end
	ns.Preview.Show(entry) -- stays until the map closes or changes
	Waypoint.Remember(result, text)
	return true
end
