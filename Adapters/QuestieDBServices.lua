-- MapScout adapter: services (bank, inn, trainer...) from QuestieDB.
-- QuestieDB's NPCs carry the game's NPC flags; read at runtime (nothing
-- copied) they give the services of the world before MapScout has its own data
-- packs, which stay needed for players without QuestieDB.
-- Needs Adapters/QuestieDB.lua (loaded first): without QuestieDB it does nothing.
--
-- Each NPC goes in one category, the first of SERVICES it has (an innkeeper
-- also sells: it is an inn); its keywords name all its services, so typing
-- finds it under any of them. Flight masters have their own provider.
-- Only NPCs friendly to the player, placed where they stand. Built once per
-- session, in small steps.
-- A stopgap until MapScout's own data covers the world: where MapScout's
-- services (Providers/Services.lua, on) have a service on a map, this adapter
-- leaves that service out on that map. Each city harvested moves to our data
-- by itself; turning our services on or off builds this list again.

local _, ns = ...
local L = ns.L

local Adapter = ns.QuestieAdapter
if not (Adapter and Adapter.db and Adapter.db.Npc and Adapter.db.Npc.GetAllIds) then
	return -- no QuestieDB, or one we can't read
end
local DB = Adapter.db
local FLAGS = DB.Enum and DB.Enum.npcFlags or {}
local band = bit and bit.band

local Services = {}
ns.QuestieServices = Services

Services.STEP = 400 -- most NPCs checked per frame
Services.BUDGET_MS = 8 -- and at most this long per frame

-- In priority order: { category, flags, word key, icon }
Services.SERVICES = {
	{ id = "bank", flags = { "BANKER" }, words = "BANK", icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue" },
	{ id = "auction", flags = { "AUCTIONEER" }, words = "AUCTION", icon = "Interface\\Icons\\INV_Misc_Coin_02" },
	{ id = "inn", flags = { "INNKEEPER" }, words = "INN", icon = "Interface\\Icons\\INV_Drink_04" },
	{ id = "stable", flags = { "STABLEMASTER" }, words = "STABLE", icon = "Interface\\Icons\\Ability_Hunter_BeastTaming" },
	{ id = "trainer", flags = { "TRAINER" }, words = "TRAINER", icon = "Interface\\Icons\\INV_Misc_Book_09" },
	{ id = "repair", flags = { "REPAIR" }, words = "REPAIR", icon = "Interface\\Icons\\Trade_BlackSmithing" },
	{ id = "battle", flags = { "BATTLEMASTER" }, words = "BATTLEMASTER", icon = "Interface\\Icons\\INV_BannerPVP_02" },
	{ id = "guild", flags = { "PETITIONER", "TABARD_DESIGNER" }, words = "GUILD", icon = "Interface\\Icons\\INV_Misc_Note_05" },
	{ id = "vendor", flags = { "VENDOR" }, words = "VENDOR", icon = "Interface\\Icons\\INV_Misc_Bag_08" },
}

-- The flag bits of each service in this flavor (flags it lacks are skipped)
for _, service in ipairs(Services.SERVICES) do
	service.mask = 0
	for _, name in ipairs(service.flags) do
		service.mask = service.mask + (FLAGS[name] or 0)
	end
end

local function has(flags, mask)
	return mask > 0 and band and band(flags, mask) ~= 0
end

-- The entry of an NPC, or nil if it offers no service we list or isn't usable
function Services.EntryFor(npcID, who)
	local flags = DB.Npc.npcFlags(npcID)
	if not flags or flags == 0 then
		return nil
	end
	local main
	local keywords = {}
	for _, service in ipairs(Services.SERVICES) do
		if has(flags, service.mask) then
			main = main or service
			for _, word in ipairs(ns.Words(service.words)) do
				keywords[#keywords + 1] = word
			end
		end
	end
	if not main then
		return nil
	end
	local friendly = DB.Npc.friendlyToFaction(npcID)
	if friendly and who.faction and not friendly:find(who.faction, 1, true) then
		return nil -- hostile to the player
	end
	local mapID, x, y = Adapter.FirstSpawn(DB.Npc.spawns(npcID))
	if not mapID then
		return nil
	end
	if who.covered and who.covered(mapID, main.id) then
		return nil -- MapScout's own data has this service here
	end
	local subName = DB.Npc.subName(npcID)
	if subName and subName ~= "" then
		keywords[#keywords + 1] = subName
	end
	return {
		id = npcID,
		name = DB.Npc.name(npcID) or ("#" .. npcID),
		subtitle = (subName and subName ~= "") and subName or L["SERVICE_" .. main.id],
		category = main.id,
		keywords = keywords,
		icon = main.icon,
		mapID = mapID,
		x = x,
		y = y,
		npcID = npcID,
	}
end

local provider
local building
Services.stats = {}

local step
step = function(build)
	if build ~= building then
		return
	end
	local stop = math.min(build.index + Services.STEP - 1, #build.ids)
	local started = debugprofilestop()
	local i = build.index
	while i <= stop do
		local entry = Services.EntryFor(build.ids[i], build.who)
		if entry then
			build.entries[#build.entries + 1] = entry
		end
		i = i + 1
		if debugprofilestop() - started > Services.BUDGET_MS then
			break
		end
	end
	build.index = i
	if build.index <= #build.ids then
		C_Timer.After(0, function()
			step(build)
		end)
		return
	end
	building = nil
	Services.stats = { npcs = #build.ids, services = #build.entries, ms = debugprofilestop() - build.start }
	if provider and provider:IsEnabled() then
		provider:SetEntries(build.entries)
	end
end

-- What MapScout's own services cover: fn(mapID, service), or nil when they
-- are off (or have no data)
local function ownCoverage()
	local own = ns.Registry.Get("services")
	if not (own and own.enabled and ns.Services) then
		return nil
	end
	local data = ns.Packs.Get("services")
	if not data then
		return nil
	end
	return function(mapID, kind)
		return ns.Services.Covers(data, mapID, kind)
	end
end

function Services.Build()
	local who = Adapter.Player()
	who.covered = ownCoverage()
	local build = {
		ids = DB.Npc.GetAllIds() or {}, index = 1, entries = {}, who = who, start = debugprofilestop(),
	}
	building = build
	C_Timer.After(0, function()
		step(build)
	end)
end

local categories = {}
for _, service in ipairs(Services.SERVICES) do
	local words = ns.Words(service.words)
	categories[#categories + 1] = {
		id = service.id,
		name = L["SERVICE_" .. service.id],
		filter = table.remove(words, 1), -- the main @ word (English, singular)
		filterAliases = words,
	}
end

provider = MapScoutAPI:RegisterProvider("questiedb-services", {
	name = L.QUESTIE_SERVICES_NAME,
	description = L.QUESTIE_SERVICES_DESCRIPTION,
	icon = Services.SERVICES[1].icon,
	filter = "service",
	filterAliases = ns.Words("SERVICES"),
	categories = categories,
	OnEnable = Services.Build, -- once per session: services don't change
	OnDisable = function()
		building = nil
	end,
})

-- Our services turned on or off: what they cover changed
ns.Registry.Listen(function(what, id)
	if what == "toggled" and id == "services" and provider and provider:IsEnabled() then
		Services.Build()
	end
end)

ns.RegisterDebug("questieservices", function()
	local s = Services.stats
	ns.Print(L.DEBUG_QUESTIE_SERVICES_RESULT:format(s.npcs or 0, s.services or 0, s.ms or 0))
end, L.DEBUG_QUESTIE_SERVICES)
