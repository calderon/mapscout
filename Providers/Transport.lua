-- MapScout: boats, zeppelins, skyships and trams (built-in provider, through
-- MapScoutAPI). One result per dock, named after where it is (the town next to
-- it, or its map), with where it goes in the subtitle: "Boat to Ratchet". The
-- destinations are search words too, so "Booty Bay" and "Ratchet" both find
-- the Booty Bay dock. Docks of the other faction (the zeppelins for the
-- Alliance, the tram for the Horde) are left out, and so are they as
-- destinations.
--   @transport (all)  @boat  @zeppelin (skyships too)  @tram
-- From the static data pack (Core/Packs.lua, category "transport"): the game
-- does not tell where its transports stop. The pack is only loaded when this
-- provider is on, and its table is let go when it is turned off.

local _, ns = ...
local L = ns.L

local Transport = {}
ns.Transport = Transport

Transport.ICONS = {
	boat = "Interface\\Icons\\INV_Misc_Anchor",
	zeppelin = "Interface\\Icons\\INV_ZeppelinMount",
	skyship = "Interface\\Icons\\INV_AirshipMountGoblin",
	tram = "Interface\\Icons\\Ability_Foundryraid_TrainDeath",
}
local CATEGORY = { boat = "boats", zeppelin = "zeppelins", skyship = "zeppelins", tram = "trams" }
local SUBTITLE = {
	boat = "TRANSPORT_BOAT_TO",
	zeppelin = "TRANSPORT_ZEPPELIN_TO",
	skyship = "TRANSPORT_SKYSHIP_TO",
	tram = "TRANSPORT_TRAM_TO",
}
local WORDS = { boat = "BOAT", zeppelin = "ZEPPELIN", skyship = "SKYSHIP", tram = "TRAM" }

-- Where a dock is, and its name (in the player's language) and English name:
-- the town it is named after, or the map the game places it in
local function place(row, names, english)
	local uiMap, x, y, town = row[2], row[3] / 10000, row[4] / 10000, row[5]
	local mapID, px, py = ns.PlaceOutdoors(uiMap, x, y)
	local name = town and town > 0 and (names[town] or english[town])
	if not name then
		local map = ns.MapPlace(mapID)
		name = map and map.name
	end
	return name, town and english[town], mapID, px, py
end

function Transport.Entries(data)
	local entries = {}
	if not (data and data.docks and data.names) then
		return entries
	end
	local names, english = data.names[GetLocale()] or data.names.enUS or {}, data.names.enUS or {}
	local faction = UnitFactionGroup("player")
	local docks = {}
	for id, row in pairs(data.docks) do
		local side = row[6]
		if CATEGORY[row[1]] and (side == "" or not faction or side == faction) then
			local name, englishName, mapID, x, y = place(row, names, english)
			if name then
				docks[id] = { row = row, name = name, english = englishName, mapID = mapID, x = x, y = y }
			end
		end
	end
	for id, dock in pairs(docks) do
		local kind = dock.row[1]
		local keywords = ns.Words(WORDS[kind])
		if dock.english and dock.english ~= dock.name then
			keywords[#keywords + 1] = dock.english:lower()
		end
		local to = {}
		for i = 7, #dock.row do
			local other = docks[dock.row[i]]
			if other then
				to[#to + 1] = other.name
				keywords[#keywords + 1] = other.name:lower()
				if other.english and other.english ~= other.name then
					keywords[#keywords + 1] = other.english:lower()
				end
			end
		end
		if #to > 0 then
			entries[#entries + 1] = {
				id = id,
				name = dock.name,
				subtitle = L[SUBTITLE[kind]]:format(table.concat(to, ", ")),
				category = CATEGORY[kind],
				keywords = keywords,
				mapID = dock.mapID,
				x = dock.x,
				y = dock.y,
				icon = Transport.ICONS[kind],
				weight = 0.6,
			}
		end
	end
	table.sort(entries, function(a, b) return a.id < b.id end)
	return entries
end

-- /ms debug transport: every dock and where it ended up
ns.RegisterDebug("transport", function()
	local record = ns.Registry.Get("transport")
	local entries = record and record.entries or {}
	local _, reason = ns.Packs.Get("transport")
	ns.Print(L.DEBUG_TRANSPORT_RESULT:format(#entries, tostring(reason or "ok")))
	for _, entry in ipairs(entries) do
		local map = ns.MapPlace(entry.mapID)
		DEFAULT_CHAT_FRAME:AddMessage(("  %s (%s): %s [%s] %.1f, %.1f"):format(entry.name, entry.subtitle,
			map and map.name or "?", tostring(entry.mapID), (entry.x or 0) * 100, (entry.y or 0) * 100))
	end
end, L.DEBUG_TRANSPORT)

local provider
provider = MapScoutAPI:RegisterProvider("transport", {
	name = L.TRANSPORT_NAME,
	description = L.TRANSPORT_DESCRIPTION,
	icon = Transport.ICONS.boat,
	filter = "transport",
	filterAliases = ns.Words("TRANSPORTS"),
	categories = {
		{ id = "boats", name = L.TRANSPORT_BOATS, filter = "boat", filterAliases = ns.Words("BOATS") },
		{ id = "zeppelins", name = L.TRANSPORT_ZEPPELINS, filter = "zeppelin", filterAliases = ns.Words("ZEPPELINS") },
		{ id = "trams", name = L.TRANSPORT_TRAMS, filter = "tram", filterAliases = ns.Words("TRAMS") },
	},
	OnEnable = function()
		provider:SetEntries(Transport.Entries((ns.Packs.Get("transport"))))
	end,
	OnDisable = function()
		ns.Packs.Release("transport")
	end,
})
