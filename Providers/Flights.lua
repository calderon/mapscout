-- MapScout: flight masters (built-in provider, through MapScoutAPI).
-- From the game (C_TaxiMap), in Forever as the audit (#20) found it: asked for
-- a continent, it gives all its flight nodes, with positions on that map and
-- no known/unknown state outside the flight window. So:
--   * each node is placed in the most precise map at its point
--     (C_Map.GetMapInfoAtPosition: a city wins over the zone around it) and its
--     position converted to that map;
--   * nodes of the other faction are left out (they can't be used);
--   * the nodes this character knows are learnt when the flight map opens
--     (TAXIMAP_OPENED: the map of routes, not the first "I need a ride"
--     talk), all of them at once, and kept per character; unknown ones show
--     dimmed, with a hint in the tooltip until that first time.
--   @flight (and @vuelo...)

local _, ns = ...
local L = ns.L

local Flights = {}
ns.Flights = Flights

Flights.ICON_KNOWN = "Interface\\TaxiFrame\\UI-Taxi-Icon-Green"
Flights.ICON_UNKNOWN = "Interface\\TaxiFrame\\UI-Taxi-Icon-Gray"

-- Enum.FlightPathFaction / Enum.FlightPathState (numbers if the enum is missing)
local FACTION_HORDE, FACTION_ALLIANCE = 1, 2
local STATE_UNREACHABLE = 2

local function hostile(node)
	local faction = UnitFactionGroup("player")
	return (faction == "Alliance" and node.faction == FACTION_HORDE)
		or (faction == "Horde" and node.faction == FACTION_ALLIANCE)
end

local function known()
	return ns.charDB and ns.charDB.knownTaxi or {}
end

function Flights.Entries()
	local entries, seen = {}, {}
	if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap and C_Map.GetMapChildrenInfo) then
		return entries
	end
	local knownNodes = known()
	for _, continentID in ipairs(ns.Continents()) do
		for _, node in ipairs(C_TaxiMap.GetTaxiNodesForMap(continentID) or {}) do
			local position = node.position
			local x, y = position and position.x, position and position.y
			if node.nodeID and not seen[node.nodeID] and x and x >= 0 and x <= 1 and y >= 0 and y <= 1
				and not hostile(node) then
				seen[node.nodeID] = true
				local mapID, px, py = ns.PlaceOnMap(continentID, x, y)
				local isKnown = knownNodes[node.nodeID] == true
				local details
				if not isKnown and not (ns.charDB and ns.charDB.taxiLearnt) then
					details = { L.FLIGHTS_HOW_TO_LEARN } -- this character never opened a flight map
				end
				entries[#entries + 1] = {
					details = details,
					id = node.nodeID,
					name = node.name,
					subtitle = isKnown and L.FLIGHTS_SUBTITLE or L.FLIGHTS_SUBTITLE_UNKNOWN,
					keywords = ns.Words("FLIGHT_MASTER"),
					mapID = mapID,
					x = px,
					y = py,
					icon = isKnown and Flights.ICON_KNOWN or Flights.ICON_UNKNOWN,
					dimmed = not isKnown,
					weight = isKnown and 0.6 or 0.3,
				}
			end
		end
	end
	return entries
end

local provider

local function publish()
	if provider and provider:IsEnabled() then
		provider:SetEntries(Flights.Entries())
	end
end

-- The flight window is open: learn which nodes this character knows.
function Flights.LearnKnown()
	if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and ns.charDB) then
		return 0
	end
	local mapID = GetTaxiMapID and GetTaxiMapID() or (WorldMapFrame and WorldMapFrame:GetMapID())
	local learnt = 0
	local firstTime = not ns.charDB.taxiLearnt
	ns.charDB.taxiLearnt = true
	for _, node in ipairs(C_TaxiMap.GetAllTaxiNodes(mapID) or {}) do
		if node.nodeID and node.state ~= nil and node.state ~= STATE_UNREACHABLE
			and not ns.charDB.knownTaxi[node.nodeID] then
			ns.charDB.knownTaxi[node.nodeID] = true
			learnt = learnt + 1
		end
	end
	if learnt > 0 or firstTime then
		publish()
	end
	return learnt
end

provider = MapScoutAPI:RegisterProvider("flights", {
	name = L.FLIGHTS_NAME,
	description = L.FLIGHTS_DESCRIPTION,
	icon = Flights.ICON_KNOWN,
	filter = "flight",
	filterAliases = ns.Words("FLIGHTS"),
	OnEnable = function()
		publish()
		ns.RegisterEvent("TAXIMAP_OPENED", "Flights", Flights.LearnKnown)
	end,
	OnDisable = function()
		ns.UnregisterEvent("TAXIMAP_OPENED", "Flights")
	end,
})

-- /ms debug flights: a few nodes with the map they were placed in -------------------

-- With the flight window open: what the game says about its nodes
local function debugTaxi()
	local taxiMap = GetTaxiMapID and GetTaxiMapID()
	local worldMap = WorldMapFrame and WorldMapFrame:GetMapID()
	local best = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	ns.Print(("taxi map %s, world map %s, player map %s, NumTaxiNodes %s"):format(tostring(taxiMap), tostring(worldMap),
		tostring(best), tostring(NumTaxiNodes and NumTaxiNodes())))
	for _, mapID in ipairs({ taxiMap, worldMap, best }) do
		local nodes = mapID and C_TaxiMap.GetAllTaxiNodes(mapID) or {}
		local states = {}
		for i = 1, math.min(4, #nodes) do
			states[#states + 1] = ("%s=%s"):format(tostring(nodes[i].name), tostring(nodes[i].state))
		end
		DEFAULT_CHAT_FRAME:AddMessage(("  GetAllTaxiNodes(%s): %d nodes %s"):format(tostring(mapID), #nodes,
			table.concat(states, ", ")))
	end
	if NumTaxiNodes and TaxiNodeName and TaxiNodeGetType then
		for i = 1, math.min(4, NumTaxiNodes()) do
			DEFAULT_CHAT_FRAME:AddMessage(("  TaxiNode %d: %s %s"):format(i, tostring(TaxiNodeName(i)),
				tostring(TaxiNodeGetType(i))))
		end
	end
end

ns.RegisterDebug("flights", function(args)
	if args == "taxi" then
		debugTaxi()
		return
	end
	local entries = Flights.Entries()
	local knownCount = 0
	for _, entry in ipairs(entries) do
		if not entry.dimmed then
			knownCount = knownCount + 1
		end
	end
	ns.Print(L.DEBUG_FLIGHTS_RESULT:format(#entries, knownCount, UnitFactionGroup("player") or "?"))
	for i = 1, math.min(8, #entries) do
		local entry = entries[i]
		local place = ns.MapPlace(entry.mapID)
		DEFAULT_CHAT_FRAME:AddMessage(("  %s -> %s (%d) %.1f, %.1f%s"):format(entry.name, place and place.name or "?",
			entry.mapID, entry.x * 100, entry.y * 100, entry.dimmed and " ·" or ""))
	end
end, L.DEBUG_FLIGHTS)
