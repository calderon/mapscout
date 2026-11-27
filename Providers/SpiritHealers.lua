-- MapScout: spirit healers, the angel at each graveyard (built-in provider,
-- through MapScoutAPI).
-- A provider of its own, not a service: a player who just died looks for the
-- nearest graveyard, and @service shouldn't list them all.
--   @spirithealer, @graveyard (@angel, @cementerio)
-- Each result is named "Spirit Healer" in the player's language, with its zone
-- as subtitle and as a search word ("graveyard duskwood").
-- From the static data pack (Core/Packs.lua, category "spirithealers"),
-- harvested in the game: Forever's client has no graveyard data. Every spirit
-- healer is for both factions. The pack is only loaded while this provider is
-- on, and let go when it is turned off.
-- Until our data covers the world, QuestieDB fills the gaps
-- (Adapters/QuestieDBSpiritHealers.lua, through SpiritHealers.SetExtra): a
-- graveyard of ours replaces its spirit healer there.

local _, ns = ...
local L = ns.L

local SpiritHealers = {}
ns.SpiritHealers = SpiritHealers

SpiritHealers.ICON = "Interface\\Icons\\Spell_Holy_Resurrection"
SpiritHealers.NEAR = 0.03 -- map units: another source's point this close to ours is the same graveyard

-- One result. keywords: the words of every spirit healer (ns.Words, read once)
function SpiritHealers.Entry(id, mapID, x, y, keywords)
	local map = ns.MapPlace(mapID)
	local words = {}
	for _, word in ipairs(keywords or ns.Words("SPIRIT_HEALER")) do
		words[#words + 1] = word
	end
	if map and map.name then
		words[#words + 1] = map.name:lower() -- "cementerio dun morogh"
	end
	return {
		id = id,
		name = L.SPIRIT_HEALER,
		subtitle = map and map.name or nil,
		keywords = words,
		icon = SpiritHealers.ICON,
		mapID = mapID,
		x = x,
		y = y,
	}
end

function SpiritHealers.Entries(data)
	local entries = {}
	if not (data and data.maps) then
		return entries
	end
	local keywords = ns.Words("SPIRIT_HEALER")
	for mapID, rows in pairs(data.maps) do
		for i, row in ipairs(rows) do
			entries[#entries + 1] = SpiritHealers.Entry(("%d:%d"):format(mapID, i), mapID, row[1] / 10000,
				row[2] / 10000, keywords)
		end
	end
	table.sort(entries, function(a, b) return a.id < b.id end)
	return entries
end

-- Whether the pack has a graveyard at this point (on the same map, within
-- NEAR): there, our own data replaces other sources
function SpiritHealers.Covers(data, mapID, x, y)
	for _, row in ipairs(data and data.maps and data.maps[mapID] or {}) do
		local dx, dy = row[1] / 10000 - x, row[2] / 10000 - y
		if dx * dx + dy * dy < SpiritHealers.NEAR * SpiritHealers.NEAR then
			return true
		end
	end
	return false
end

local provider
local own -- our pack's entries, while on
local extra = {} -- source -> its entries (SpiritHealers.SetExtra)

local function push()
	if not (provider and provider:IsEnabled()) then
		return
	end
	local list = {}
	for _, entry in ipairs(own or {}) do
		list[#list + 1] = entry
	end
	for _, entries in pairs(extra) do
		for _, entry in ipairs(entries) do
			list[#list + 1] = entry
		end
	end
	provider:SetEntries(list)
end

-- Entries from another source of ours (nil drops them), shown with the pack's
function SpiritHealers.SetExtra(source, entries)
	extra[source] = entries
	push()
end

-- /ms debug spirithealers: how many, and from where
ns.RegisterDebug("spirithealers", function()
	local _, reason = ns.Packs.Get("spirithealers")
	local others = 0
	for _, entries in pairs(extra) do
		others = others + #entries
	end
	ns.Print(L.DEBUG_SPIRIT_HEALERS_RESULT:format(#(own or {}), others, tostring(reason or "ok")))
end, L.DEBUG_SPIRIT_HEALERS)

local aliases = ns.Words("SPIRIT_HEALERS")
provider = MapScoutAPI:RegisterProvider("spirithealers", {
	name = L.SPIRIT_HEALERS_NAME,
	description = L.SPIRIT_HEALERS_DESCRIPTION,
	icon = SpiritHealers.ICON,
	filter = table.remove(aliases, 1), -- the main @ word (English, singular)
	filterAliases = aliases,
	OnEnable = function()
		own = SpiritHealers.Entries((ns.Packs.Get("spirithealers")))
		push()
	end,
	OnDisable = function()
		own = nil
		ns.Packs.Release("spirithealers")
	end,
})
