-- MapScout: city services (built-in provider, through MapScoutAPI): banks,
-- auction houses, inns, mailboxes, stable masters, repair vendors, barbers,
-- guild masters and battlemasters.
-- Each result is named after its service ("Bank", in the player's language;
-- a battlemaster after its battleground, "Alterac Valley battlemaster"), with
-- the place in the subtitle: the name the game gave it ("Las Arcas") when it
-- was harvested in the player's language, else its city.
--   @service (all)  @bank  @auction  @inn  @mailbox  @stable  @repair  @barber
--   @guild  @battlemaster
-- From the static data pack (Core/Packs.lua, category "services"), harvested in
-- the game: the client has neither the NPCs nor the mailboxes. Services only
-- the other faction can use are left out. The pack is only loaded when this
-- provider is on, and its table is let go when it is turned off.

local _, ns = ...
local L = ns.L

local Services = {}
ns.Services = Services

-- The services, in the order of the options: { id, word key, icon }
Services.KINDS = {
	{ id = "bank", words = "BANK", icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue" },
	{ id = "auction", words = "AUCTION", icon = "Interface\\Icons\\INV_Misc_Coin_02" },
	{ id = "inn", words = "INN", icon = "Interface\\Icons\\INV_Drink_04" },
	{ id = "mailbox", words = "MAILBOX", icon = "Interface\\Icons\\INV_Letter_15" },
	{ id = "stable", words = "STABLE", icon = "Interface\\Icons\\Ability_Hunter_BeastTaming" },
	{ id = "repair", words = "REPAIR", icon = "Interface\\Icons\\Trade_BlackSmithing" },
	{ id = "barber", words = "BARBER", icon = "Interface\\Icons\\INV_Misc_Comb_02" },
	{ id = "guild", words = "GUILD", icon = "Interface\\Icons\\INV_Misc_Note_05" },
	{ id = "battle", words = "BATTLEMASTER", icon = "Interface\\Icons\\INV_BannerPVP_02" },
}
-- The battlegrounds a battlemaster sends to (row[7]): their name and search
-- words are BATTLE_<id> and BATTLEGROUND_<ID>
Services.BATTLEGROUNDS = { alterac = true, arathi = true, warsong = true }
local BY_ID = {}
for _, kind in ipairs(Services.KINDS) do
	BY_ID[kind.id] = kind
end

-- The pack's place names are in the language they were harvested in: shown
-- only to players of that language (esES and esMX count as one)
local SPANISH = { esES = true, esMX = true }
local function sameLanguage(a, b)
	return a == b or (SPANISH[a] and SPANISH[b]) or false
end

function Services.Entries(data)
	local entries = {}
	if not (data and data.maps) then
		return entries
	end
	local locale, names = GetLocale(), data.names or {}
	local faction = UnitFactionGroup("player")
	for mapID, rows in pairs(data.maps) do
		for i, row in ipairs(rows) do
			local kind, side = BY_ID[row[1]], row[4]
			if kind and (side == "" or not faction or side == faction) then
				local place = row[6] > 0 and sameLanguage(row[5], locale) and names[row[5]] and names[row[5]][row[6]]
				local keywords = ns.Words(kind.words)
				local battleground = Services.BATTLEGROUNDS[row[7] or ""] and row[7]
				if battleground then
					for _, word in ipairs(ns.Words("BATTLEGROUND_" .. battleground:upper())) do
						keywords[#keywords + 1] = word
					end
				end
				if place then
					keywords[#keywords + 1] = place:lower()
				end
				local map = ns.MapPlace(mapID)
				entries[#entries + 1] = {
					id = ("%s:%d:%d"):format(kind.id, mapID, i),
					name = battleground and L["BATTLE_" .. battleground] or L["SERVICE_" .. kind.id],
					subtitle = place or (map and map.name) or nil,
					category = kind.id,
					keywords = keywords,
					mapID = mapID,
					x = row[2] / 10000,
					y = row[3] / 10000,
					icon = kind.icon,
				}
			end
		end
	end
	table.sort(entries, function(a, b) return a.id < b.id end)
	return entries
end

-- Whether the pack has this service on this map (for either faction): there,
-- our own data replaces other sources (Adapters/QuestieDBServices.lua)
function Services.Covers(data, mapID, kindID)
	for _, row in ipairs(data and data.maps and data.maps[mapID] or {}) do
		if row[1] == kindID then
			return true
		end
	end
	return false
end

-- /ms debug services: every service and where it is
ns.RegisterDebug("services", function()
	local record = ns.Registry.Get("services")
	local entries = record and record.entries or {}
	local _, reason = ns.Packs.Get("services")
	ns.Print(L.DEBUG_SERVICES_RESULT:format(#entries, tostring(reason or "ok")))
	for _, entry in ipairs(entries) do
		local map = ns.MapPlace(entry.mapID)
		DEFAULT_CHAT_FRAME:AddMessage(("  %s (%s): %s [%s] %.1f, %.1f"):format(entry.name, tostring(entry.subtitle),
			map and map.name or "?", tostring(entry.mapID), entry.x * 100, entry.y * 100))
	end
end, L.DEBUG_SERVICES)

local categories = {}
for _, kind in ipairs(Services.KINDS) do
	local words = ns.Words(kind.words)
	categories[#categories + 1] = {
		id = kind.id,
		name = L["SERVICE_" .. kind.id],
		filter = table.remove(words, 1), -- the main @ word (English, singular)
		filterAliases = words,
	}
end

local provider
provider = MapScoutAPI:RegisterProvider("services", {
	name = L.SERVICES_NAME,
	description = L.SERVICES_DESCRIPTION,
	icon = Services.KINDS[1].icon,
	filter = "service",
	filterAliases = ns.Words("SERVICES"),
	categories = categories,
	OnEnable = function()
		provider:SetEntries(Services.Entries((ns.Packs.Get("services"))))
	end,
	OnDisable = function()
		ns.Packs.Release("services")
	end,
})
