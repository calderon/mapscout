-- MapScout: trainers (built-in provider, through MapScoutAPI): class,
-- profession, riding and weapon trainers.
-- Each result is named after what it teaches ("Mage trainer", in the player's
-- language), with the place in the subtitle: the name the game gave it ("Sala
-- de los Misterios") when it was harvested in the player's language, else its
-- city. The player's own class comes first; other classes' trainers have their
-- own toggle. Trainers are shown inside Services in the options (spec.parent),
-- and @service finds them too.
--   @trainer (all)  @class  @otherclass  @profession  @riding  @weapon
-- From the static data pack (Core/Packs.lua, category "trainers"), harvested
-- in the game, like the city services (Providers/Services.lua). Trainers only
-- the other faction can use are left out. The pack is only loaded when this
-- provider is on, and its table is let go when it is turned off.
-- Other sources of ours (Adapters/QuestieDBServices.lua) add their entries
-- to these (Trainers.SetExtra), as with the services.

local _, ns = ...
local L = ns.L

local Trainers = {}
ns.Trainers = Trainers

-- The toggles, in the order of the options: { id, word key }
Trainers.CATEGORIES = {
	{ id = "class", words = "TRAINER_CLASS" },
	{ id = "otherclass", words = "TRAINER_OTHERCLASS" },
	{ id = "profession", words = "TRAINER_PROFESSION" },
	{ id = "riding", words = "TRAINER_RIDING" },
	{ id = "weapon", words = "TRAINER_WEAPON" },
}

Trainers.ICONS = {
	class = "Interface\\Icons\\INV_Misc_Book_09",
	profession = "Interface\\Icons\\INV_Misc_Book_11",
	riding = "Interface\\Icons\\Ability_Mount_RidingHorse",
	weapon = "Interface\\Icons\\INV_Sword_04",
}
Trainers.OWN_WEIGHT = 1 -- the player's class trainer comes before the rest
Trainers.OTHER_WEIGHT = 0.3 -- and other classes' after them (the default is 0.5)

-- The pack's place names are in the language they were harvested in: shown
-- only to players of that language (esES and esMX count as one)
local SPANISH = { esES = true, esMX = true }
local function sameLanguage(a, b)
	return a == b or (SPANISH[a] and SPANISH[b]) or false
end

-- Adds the search words of a key (none if it has no words)
local function words(key, into)
	for _, word in ipairs(ns.Words(key)) do
		into[#into + 1] = word
	end
	return into
end

-- The name key of a trainer: TRAINER_MAGE, TRAINER_alchemy, TRAINER_riding...
local function nameKey(kind, what)
	return "TRAINER_" .. (what ~= "" and what or kind)
end

function Trainers.Entries(data)
	local entries = {}
	if not (data and data.maps) then
		return entries
	end
	local locale, names = GetLocale(), data.names or {}
	local faction = UnitFactionGroup("player")
	local _, ownClass = UnitClass("player")
	for mapID, rows in pairs(data.maps) do
		for i, row in ipairs(rows) do
			local kind, what, side = row[1], row[2], row[5]
			if Trainers.ICONS[kind] and (side == "" or not faction or side == faction) then
				local place = row[7] > 0 and sameLanguage(row[6], locale) and names[row[6]] and names[row[6]][row[7]]
				local category, weight = kind, nil
				if kind == "class" then
					if ownClass and what ~= ownClass then
						category, weight = "otherclass", Trainers.OTHER_WEIGHT
					else
						weight = Trainers.OWN_WEIGHT
					end
				end
				local keywords = words("TRAINER", {})
				words("TRAINER_" .. kind:upper(), keywords)
				if what ~= "" then
					words("TRAINER_" .. what:upper(), keywords)
				end
				if place then
					keywords[#keywords + 1] = place:lower()
				end
				local map = ns.MapPlace(mapID)
				entries[#entries + 1] = {
					id = ("%s:%s:%d:%d"):format(kind, what, mapID, i),
					name = L[nameKey(kind, what)],
					subtitle = place or (map and map.name) or nil,
					category = category,
					keywords = keywords,
					weight = weight,
					mapID = mapID,
					x = row[3] / 10000,
					y = row[4] / 10000,
					roams = row[8] == true or nil, -- an NPC who walks a route
					icon = Trainers.ICONS[kind],
				}
			end
		end
	end
	table.sort(entries, function(a, b) return a.id < b.id end)
	return entries
end

-- Whether the pack has a trainer on this map (for either faction): there, our
-- own data replaces other sources (Adapters/QuestieDBServices.lua)
function Trainers.Covers(data, mapID)
	local rows = data and data.maps and data.maps[mapID]
	return rows ~= nil and #rows > 0
end

-- /ms debug trainers: every trainer and where it is
ns.RegisterDebug("trainers", function()
	local record = ns.Registry.Get("trainers")
	local entries = record and record.entries or {}
	local _, reason = ns.Packs.Get("trainers")
	ns.Print(L.DEBUG_TRAINERS_RESULT:format(#entries, tostring(reason or "ok")))
	for _, entry in ipairs(entries) do
		local map = ns.MapPlace(entry.mapID)
		DEFAULT_CHAT_FRAME:AddMessage(("  %s (%s): %s [%s] %.1f, %.1f"):format(entry.name, tostring(entry.subtitle),
			map and map.name or "?", tostring(entry.mapID), entry.x * 100, entry.y * 100))
	end
end, L.DEBUG_TRAINERS)

local categories = {}
for _, category in ipairs(Trainers.CATEGORIES) do
	local list = ns.Words(category.words)
	categories[#categories + 1] = {
		id = category.id,
		name = L["TRAINERS_" .. category.id],
		filter = table.remove(list, 1), -- the main @ word (English, singular)
		filterAliases = list,
	}
end

local provider
local own -- our pack's entries, while on
local extra = {} -- source -> its entries (Trainers.SetExtra)

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
function Trainers.SetExtra(source, entries)
	extra[source] = entries
	push()
end

local aliases = ns.Words("TRAINER")
provider = MapScoutAPI:RegisterProvider("trainers", {
	name = L.TRAINERS_NAME,
	description = L.TRAINERS_DESCRIPTION,
	icon = Trainers.ICONS.class,
	parent = "services", -- trainers are one more kind of service: inside it in the options, found by @service
	filter = table.remove(aliases, 1),
	filterAliases = aliases,
	categories = categories,
	OnEnable = function()
		own = Trainers.Entries((ns.Packs.Get("trainers")))
		push()
	end,
	OnDisable = function()
		own = nil
		ns.Packs.Release("trainers")
	end,
})
