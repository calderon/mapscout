-- MapScout: dungeons and raids (built-in provider, through MapScoutAPI).
-- Each one by name (in the player's language, and in English too), pointing
-- to its entrance on the outdoor map; the subtitle says dungeon or raid and
-- its recommended level.
--   @instance (all)  @dungeon  @raid (plurals work too)
-- Where they are comes from the static data pack (Core/Packs.lua, category
-- "dungeons"): the game client of WoW Forever does not tell
-- (C_EncounterJournal.GetDungeonEntrancesForMap returns nothing there). The
-- pack is only loaded when this provider is on, and its table is let go when
-- it is turned off.
-- Only entrances checked in the game have a place (the pack says uiMapID 0
-- for the rest): those are still found by name, "entrance to be confirmed",
-- and lead nowhere, so MapScout never shows a wrong point.
-- A point on a continent map (the pack stores it there when zone maps overlap)
-- is placed in its zone by the game, always on the outdoor zone or city
-- (ns.PlaceOutdoors).

local _, ns = ...
local L = ns.L

local Dungeons = {}
ns.Dungeons = Dungeons

Dungeons.ICONS = {
	dungeon = "Interface\\Icons\\INV_Misc_Key_03",
	raid = "Interface\\Icons\\INV_Misc_Head_Dragon_Black",
}
local CATEGORY = { dungeon = "dungeons", raid = "raids" }

-- Where an entrance goes on the map: (mapID, x, y), always a zone or city.
-- Only a continent point is placed by the game: a point already on its zone
-- stays there (near a border, the game may answer with the zone next to it:
-- Uldaman, at the north edge of the Badlands).
local MAP_TYPE_CONTINENT = 2
function Dungeons.Place(mapID, x, y)
	local place = ns.MapPlace(mapID)
	if place and place.mapType == MAP_TYPE_CONTINENT then
		return ns.PlaceOutdoors(mapID, x, y)
	end
	return mapID, x, y
end

function Dungeons.Entries(data)
	local entries = {}
	if not (data and data.entrances and data.names) then
		return entries
	end
	local names, english = data.names[GetLocale()] or data.names.enUS or {}, data.names.enUS or {}
	for instance, row in pairs(data.entrances) do
		local kind, uiMap, x, y, level = row[1], row[2], row[3] / 10000, row[4] / 10000, row[5]
		local name = names[instance] or english[instance]
		if name and CATEGORY[kind] then
			local mapID, px, py, details
			if uiMap and uiMap > 0 then
				mapID, px, py = Dungeons.Place(uiMap, x, y)
			else
				details = { L.DUNGEONS_NO_ENTRANCE }
			end
			local what = kind == "raid" and L.DUNGEONS_RAID or L.DUNGEONS_DUNGEON
			if level and level > 0 then
				what = L.DUNGEONS_SUBTITLE:format(what, level)
			end
			if not mapID then
				what = L.DUNGEONS_PENDING:format(what)
			end
			local keywords = ns.Words(kind == "raid" and "RAID" or "DUNGEON")
			if english[instance] and english[instance] ~= name then
				keywords[#keywords + 1] = english[instance]:lower()
			end
			entries[#entries + 1] = {
				id = instance,
				name = name,
				subtitle = what,
				details = details,
				category = CATEGORY[kind],
				keywords = keywords,
				mapID = mapID,
				x = px,
				y = py,
				icon = Dungeons.ICONS[kind],
				weight = mapID and 0.6 or 0.5,
			}
		end
	end
	table.sort(entries, function(a, b) return a.id < b.id end)
	return entries
end

-- /ms debug dungeons: where each entrance ended up
ns.RegisterDebug("dungeons", function()
	local record = ns.Registry.Get("dungeons")
	local entries = record and record.entries or {}
	local _, reason = ns.Packs.Get("dungeons")
	ns.Print(L.DEBUG_DUNGEONS_RESULT:format(#entries, tostring(reason or "ok")))
	for _, entry in ipairs(entries) do
		local place = ns.MapPlace(entry.mapID)
		DEFAULT_CHAT_FRAME:AddMessage(("  %s: %s [%s, %s] %.1f, %.1f"):format(entry.name, place and place.name or "?",
			tostring(entry.mapID), tostring(place and place.mapType), (entry.x or 0) * 100, (entry.y or 0) * 100))
	end
end, L.DEBUG_DUNGEONS)

local provider
provider = MapScoutAPI:RegisterProvider("dungeons", {
	name = L.DUNGEONS_NAME,
	description = L.DUNGEONS_DESCRIPTION,
	icon = Dungeons.ICONS.dungeon,
	filter = "instance",
	filterAliases = ns.Words("INSTANCES"),
	categories = {
		{ id = "dungeons", name = L.DUNGEONS_DUNGEONS, filter = "dungeon", filterAliases = ns.Words("DUNGEONS") },
		{ id = "raids", name = L.DUNGEONS_RAIDS, filter = "raid", filterAliases = ns.Words("RAIDS") },
	},
	OnEnable = function()
		provider:SetEntries(Dungeons.Entries((ns.Packs.Get("dungeons"))))
	end,
	OnDisable = function()
		ns.Packs.Release("dungeons")
	end,
})
