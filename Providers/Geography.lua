-- MapScout: places of the world map (built-in provider, through MapScoutAPI).
-- Every continent, capital city, zone and other map of its own (battlegrounds,
-- loose islands...), straight from the game (C_Map), with the names in the
-- player's language. Choosing one opens that map: no halo or distance
-- (entries are marked isMap).
--   @place (all)  @continent  @city  @zone  @battleground (plurals work too)
-- The game doesn't tell capitals from zones: Geography.CAPITALS lists them.
-- Dungeon interiors are left to the dungeons provider, which points to their
-- entrances.
-- Towns and named places without a map of their own (Goldshire, Crossroads,
-- Whelgar's Excavation Site...) come from the static data pack (category
-- "places": the names the world map writes, where it writes them). They are
-- points, with the halo, not maps. The pack is only loaded while one of these
-- two categories is on. Subzones whose name is part of the map's art
-- (Saldean's Farm) come from the pack too ("areas": a point inside each one,
-- from the terrain), as named places.
--   @town  @subzone (plurals work too)

local _, ns = ...
local L = ns.L

local Geography = {}
ns.Geography = Geography

local ROOTS = { 946, 947 } -- Cosmic (Retail), Azeroth (Forever, Classic)

-- mapType -> category
Geography.CATEGORY_OF = {
	[2] = "continents",
	[3] = "zones", -- capitals are zones too for the game: see CAPITALS
	[5] = "others", -- micro maps (a building, a district with its own map)
	[6] = "others", -- orphan maps (battlegrounds, islands without a parent)
}

-- Capital cities, by uiMapID (our own list: the game has no such flag)
Geography.CAPITALS = {
	[1453] = true, -- Stormwind City
	[1455] = true, -- Ironforge
	[1457] = true, -- Darnassus
	[1454] = true, -- Orgrimmar
	[1456] = true, -- Thunder Bluff
	[1458] = true, -- Undercity
}

local ICONS = {
	towns = "Interface\\Icons\\INV_Misc_Bag_EnchantedRunecloth",
	subzones = "Interface\\Icons\\INV_Misc_Map_01",
	continents = "Interface\\Icons\\INV_Misc_Map02",
	cities = "Interface\\Icons\\Spell_Arcane_TeleportStormWind",
	zones = "Interface\\Icons\\INV_Misc_Map_01",
	others = "Interface\\Icons\\INV_Misc_Map08",
}

-- Every map of the world tree, once, as search entries.
function Geography.Entries()
	local entries, seen = {}, {}
	if not (C_Map and C_Map.GetMapChildrenInfo) then
		return entries
	end
	for _, root in ipairs(ROOTS) do
		for _, info in ipairs(C_Map.GetMapChildrenInfo(root, nil, true) or {}) do
			local category = Geography.CAPITALS[info.mapID] and "cities" or Geography.CATEGORY_OF[info.mapType]
			if category and not seen[info.mapID] and info.name and info.name ~= "" then
				seen[info.mapID] = true
				entries[#entries + 1] = {
					id = info.mapID,
					name = info.name,
					category = category,
					mapID = info.mapID,
					x = 0.5,
					y = 0.5,
					isMap = true,
					icon = ICONS[category],
					weight = (category == "continents" or category == "cities") and 0.7 or 0.5,
				}
			end
		end
	end
	return entries
end

-- Towns and named places from the data pack, as search entries (points)
local CATEGORY_OF_KIND = { town = "towns", place = "subzones" }

function Geography.PackEntries(data)
	local entries = {}
	if not (data and data.places and data.names) then
		return entries
	end
	local names, english = data.names[GetLocale()] or data.names.enUS or {}, data.names.enUS or {}
	for poi, row in pairs(data.places) do
		local category = CATEGORY_OF_KIND[row[1]]
		local name = names[poi] or english[poi]
		if category and name then
			local mapID, x, y = ns.PlaceOnMap(row[2], row[3] / 10000, row[4] / 10000)
			local keywords
			if english[poi] and english[poi] ~= name then
				keywords = { english[poi]:lower() }
			end
			entries[#entries + 1] = {
				id = "poi:" .. poi,
				name = name,
				subtitle = category == "towns" and L.GEOGRAPHY_TOWN or L.GEOGRAPHY_SUBZONE,
				category = category,
				keywords = keywords,
				mapID = mapID,
				x = x,
				y = y,
				icon = ICONS[category],
				weight = category == "towns" and 0.6 or 0.45,
			}
		end
	end
	-- Subzones the map writes no label for (from the terrain): named places too
	local areaNames = data.areaNames or {}
	local localArea, englishArea = areaNames[GetLocale()] or areaNames.enUS or {}, areaNames.enUS or {}
	for area, row in pairs(data.areas or {}) do
		local name = localArea[area] or englishArea[area]
		if name then
			local mapID, x, y = ns.PlaceOnMap(row[1], row[2] / 10000, row[3] / 10000)
			local keywords
			if englishArea[area] and englishArea[area] ~= name then
				keywords = { englishArea[area]:lower() }
			end
			entries[#entries + 1] = {
				id = "area:" .. area,
				name = name,
				subtitle = L.GEOGRAPHY_SUBZONE,
				category = "subzones",
				keywords = keywords,
				mapID = mapID,
				x = x,
				y = y,
				icon = ICONS.subzones,
				weight = 0.45,
			}
		end
	end
	table.sort(entries, function(a, b) return a.id < b.id end)
	return entries
end

local provider

-- The pack is needed only while towns or subzones are on
local function wantsPack()
	return ns.Registry.IsCategoryEnabled("geography", "towns") or ns.Registry.IsCategoryEnabled("geography", "subzones")
end

function Geography.Rebuild()
	local entries = Geography.Entries()
	if wantsPack() then
		for _, entry in ipairs(Geography.PackEntries((ns.Packs.Get("places")))) do
			entries[#entries + 1] = entry
		end
	else
		ns.Packs.Release("places")
	end
	provider:SetEntries(entries)
end

provider = MapScoutAPI:RegisterProvider("geography", {
	name = L.GEOGRAPHY_NAME,
	description = L.GEOGRAPHY_DESCRIPTION,
	icon = ICONS.zones,
	-- @ words: the main one in singular, plurals still work (see ns.Words)
	filter = "place",
	filterAliases = ns.Words("GEOGRAPHY"),
	categories = {
		{ id = "continents", name = L.GEOGRAPHY_CONTINENTS, filter = "continent", filterAliases = ns.Words("CONTINENTS") },
		{ id = "cities", name = L.GEOGRAPHY_CITIES, filter = "city", filterAliases = ns.Words("CITIES") },
		{ id = "zones", name = L.GEOGRAPHY_ZONES, filter = "zone", filterAliases = ns.Words("ZONES") },
		{ id = "towns", name = L.GEOGRAPHY_TOWNS, filter = "town", filterAliases = ns.Words("TOWNS") },
		{ id = "subzones", name = L.GEOGRAPHY_SUBZONES, filter = "subzone", filterAliases = ns.Words("SUBZONES") },
		{ id = "others", name = L.GEOGRAPHY_OTHERS, filter = "battleground", filterAliases = ns.Words("OTHERS") },
	},
	OnEnable = function()
		Geography.Rebuild()
	end,
	OnDisable = function()
		ns.Packs.Release("places")
	end,
})

-- Towns or subzones turned on or off: load or let go of the pack's places
local packed
ns.Registry.Listen(function(what, id)
	if what == "categories" and (id == nil or id == "geography") and provider:IsEnabled() then
		local wants = wantsPack()
		if wants ~= packed then
			packed = wants
			Geography.Rebuild()
		end
	elseif what == "toggled" and id == "geography" then
		packed = provider:IsEnabled() and wantsPack() or nil
	end
end)
