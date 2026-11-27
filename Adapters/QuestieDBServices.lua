-- MapScout adapter: services (bank, inn, trainer...) from QuestieDB.
-- QuestieDB's NPCs carry the game's NPC flags; read at runtime (nothing
-- copied) they give the services of the world before MapScout has its own data
-- packs, which stay needed for players without QuestieDB.
-- Needs Adapters/QuestieDB.lua (loaded first): without QuestieDB it does nothing.
--
-- Not a provider of its own: where a service comes from is MapScout's
-- business, not the player's. Its services go into MapScout's Services
-- (Providers/Services.lua) and its trainers into Trainers, so their toggles
-- and categories work for both sources. It adds to Services the kinds only
-- it gives (quartermaster, vendor). Built while Services or Trainers is on.
--
-- A quartermaster (its title, "Quartermaster" or "Intendente", says so: no flag
-- does) goes in that category instead. A trainer goes in the Trainers
-- category its title names (class, profession, riding, weapon), or none.
-- Each NPC goes in one category, the first of SERVICES it has (an innkeeper
-- also sells: it is an inn); its keywords name all its services, so typing
-- finds it under any of them. Flight masters have their own provider.
-- Only NPCs friendly to the player, placed where they stand. Built in small
-- steps.
-- A stopgap until MapScout's own data covers the world: where our pack has a
-- service on a map, this adapter leaves that service out on that map;
-- trainers likewise where our pack has any on that map. Each city harvested
-- moves to our data by itself.

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
	{ id = "quartermaster", flags = {}, words = "QUARTERMASTER", icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
	{ id = "vendor", flags = { "VENDOR" }, words = "VENDOR", icon = "Interface\\Icons\\INV_Misc_Bag_08" },
}

-- The flag bits of each service in this flavor (flags it lacks are skipped)
for _, service in ipairs(Services.SERVICES) do
	service.mask = 0
	for _, name in ipairs(service.flags) do
		service.mask = service.mask + (FLAGS[name] or 0)
	end
end

for _, service in ipairs(Services.SERVICES) do
	if service.id == "quartermaster" then
		Services.QUARTERMASTER = service
	end
end

-- Whether an NPC's title names a quartermaster
function Services.IsQuartermaster(title)
	title = (title or ""):lower()
	for _, word in ipairs(ns.Words("QUARTERMASTER")) do
		if title:find(word, 1, true) then
			return true
		end
	end
	return false
end

-- Trainers' categories by the words of their title, in the order they are
-- tried: { category, word keys }. Classes last ("Weapon Master" is no class).
Services.TRAINER_KINDS = {
	{ "riding", { "TRAINER_RIDING" } },
	{ "weapon", { "TRAINER_WEAPON" } },
	{ "profession", { "TRAINER_ALCHEMY", "TRAINER_BLACKSMITHING", "TRAINER_COOKING", "TRAINER_ENCHANTING",
		"TRAINER_ENGINEERING", "TRAINER_FISHING", "TRAINER_HERBALISM", "TRAINER_FIRSTAID", "TRAINER_SKINNING",
		"TRAINER_LEATHERWORKING", "TRAINER_TAILORING", "TRAINER_MINING" } },
}
Services.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function names(text, key)
	for _, word in ipairs(ns.Words(key)) do
		if text:find(" " .. ns.Normalize(word) .. " ", 1, true) then
			return true
		end
	end
	return false
end

-- The Trainers category of a trainer by its title ("Mage Trainer",
-- "Instructora de herrería"), or nil when it doesn't say. ownClass: the
-- player's class (CLASS token): its trainers are "class", others "otherclass".
function Services.TrainerCategory(title, ownClass)
	local text = " " .. ns.Normalize(title or "") .. " "
	for _, kind in ipairs(Services.TRAINER_KINDS) do
		for _, key in ipairs(kind[2]) do
			if names(text, key) then
				return kind[1]
			end
		end
	end
	for _, class in ipairs(Services.CLASSES) do
		if names(text, "TRAINER_" .. class) then
			return (ownClass and class ~= ownClass) and "otherclass" or "class"
		end
	end
	return nil
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
		if Services.IsQuartermaster(subName) then
			main = Services.QUARTERMASTER
			for _, word in ipairs(ns.Words(main.words)) do
				keywords[#keywords + 1] = word
			end
		end
	end
	local entry = {
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
	if main.id == "trainer" then
		entry.trainer = true -- goes to Trainers, in the category its title names
		entry.category = Services.TrainerCategory(subName, who.class)
		local trainers = ns.Trainers
		if trainers and entry.category then
			entry.icon = trainers.ICONS[entry.category == "otherclass" and "class" or entry.category] or entry.icon
			if entry.category == "class" then
				entry.weight = trainers.OWN_WEIGHT
			elseif entry.category == "otherclass" then
				entry.weight = trainers.OTHER_WEIGHT
			end
		end
	end
	return entry
end

local building
local built -- the last list built, while Services or Trainers is on
Services.stats = {}

-- Whether one of MapScout's providers is on
local function isOn(id)
	local record = ns.Registry.Get(id)
	return record ~= nil and record.enabled == true
end

-- Hands the list to Services and Trainers (nil: takes it back)
local function share(entries)
	local services, trainers
	if entries then
		services, trainers = {}, {}
		for _, entry in ipairs(entries) do
			local into = entry.trainer and trainers or services
			into[#into + 1] = entry
		end
	end
	if ns.Services then
		ns.Services.SetExtra("questiedb", services)
	end
	if ns.Trainers then
		ns.Trainers.SetExtra("questiedb", trainers)
	end
end

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
	built = build.entries
	Services.stats = { npcs = #build.ids, services = #build.entries, ms = debugprofilestop() - build.start }
	share(built)
end

-- The pack data of one of MapScout's own providers, or nil when it is off
-- (or has no data)
local function ownData(id, module)
	if not (isOn(id) and module) then
		return nil
	end
	return ns.Packs.Get(id)
end

-- What MapScout's own services and trainers cover: fn(mapID, service), or nil
-- when both are off (or have no data)
local function ownCoverage()
	local services, trainers = ownData("services", ns.Services), ownData("trainers", ns.Trainers)
	if not (services or trainers) then
		return nil
	end
	return function(mapID, kind)
		if kind == "trainer" then
			return trainers ~= nil and ns.Trainers.Covers(trainers, mapID)
		end
		return services ~= nil and ns.Services.Covers(services, mapID, kind)
	end
end

function Services.Build()
	local who = Adapter.Player()
	who.covered = ownCoverage()
	local _, class = UnitClass("player")
	who.class = class
	local build = {
		ids = DB.Npc.GetAllIds() or {}, index = 1, entries = {}, who = who, start = debugprofilestop(),
	}
	building = build
	C_Timer.After(0, function()
		step(build)
	end)
end

-- Services or Trainers turned on or off: what our pack covers changed, so
-- build again; with both off, nothing is kept
local pending = false
local function rebuild()
	pending = false
	if isOn("services") or isOn("trainers") then
		Services.Build()
	else
		building, built = nil, nil
		share(nil)
	end
end

-- The kinds of service only QuestieDB gives, added to our Services
local extraKinds = {}
for _, service in ipairs(Services.SERVICES) do
	if service.id == "quartermaster" or service.id == "vendor" then
		local words = ns.Words(service.words)
		extraKinds[#extraKinds + 1] = {
			id = service.id,
			name = L["SERVICE_" .. service.id],
			filter = table.remove(words, 1), -- the main @ word (English, singular)
			filterAliases = words,
		}
	end
end
ns.Registry.AddCategories("services", extraKinds)

ns.Registry.Listen(function(what, id)
	if what == "toggled" and (id == "services" or id == "trainers") and not pending then
		pending = true -- both turned on at login: one build
		C_Timer.After(0, rebuild)
	end
end)

ns.RegisterDebug("questieservices", function()
	local s = Services.stats
	ns.Print(L.DEBUG_QUESTIE_SERVICES_RESULT:format(s.npcs or 0, s.services or 0, s.ms or 0))
end, L.DEBUG_QUESTIE_SERVICES)
