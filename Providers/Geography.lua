-- MapScout: places of the world map (built-in provider, through MapScoutAPI).
-- Every continent, capital city, zone and other map of its own (battlegrounds,
-- loose islands...), straight from the game (C_Map), with the names in the
-- player's language. Choosing one opens that map: no halo or distance
-- (entries are marked isMap).
--   @place (all)  @continent  @city  @zone  @battleground (plurals work too)
-- The game doesn't tell capitals from zones: Geography.CAPITALS lists them.
-- Dungeon interiors are left to the instances provider (#42), which points
-- to their entrances. Subzones without a map of their own (a district of a
-- city) need positions from the static data pack: a later issue.

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

local provider
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
		{ id = "others", name = L.GEOGRAPHY_OTHERS, filter = "battleground", filterAliases = ns.Words("OTHERS") },
	},
	OnEnable = function()
		provider:SetEntries(Geography.Entries())
	end,
})
