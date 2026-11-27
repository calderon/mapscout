-- MapScout adapter: spirit healers (the angel at a graveyard) from QuestieDB.
-- Forever's client data has no graveyard table, and the game's graveyard API
-- returns none, so QuestieDB's NPCs (read at runtime, nothing copied) are the
-- only source for now: the NPCs with the SPIRIT_HEALER flag.
-- A provider of its own, not a service: a player who just died looks for the
-- nearest graveyard, and @service shouldn't list them. Registered only with
-- QuestieDB (without it there would be nothing to show, so no toggle either).
-- One NPC can stand at many graveyards: one result per spawn, named "Spirit
-- Healer" in the player's language, with the zone as subtitle (and as a search
-- word: "graveyard ironforge").
-- Needs Adapters/QuestieDB.lua (loaded first). Built in small steps while on.

local _, ns = ...
local L = ns.L

local Adapter = ns.QuestieAdapter
if not (Adapter and Adapter.db and Adapter.db.Npc and Adapter.db.Npc.GetAllIds) then
	return -- no QuestieDB, or one we can't read
end
local DB = Adapter.db
local FLAG = DB.Enum and DB.Enum.npcFlags and DB.Enum.npcFlags.SPIRIT_HEALER or 0
local band = bit and bit.band

local Healers = {}
ns.QuestieSpiritHealers = Healers

Healers.STEP = 400 -- most NPCs checked per frame
Healers.BUDGET_MS = 8 -- and at most this long per frame
Healers.ICON = "Interface\\Icons\\Spell_Holy_Resurrection"

-- The entries of one NPC (one per spawn on a known map), or none
function Healers.EntriesFor(npcID, who, into)
	into = into or {}
	local flags = DB.Npc.npcFlags(npcID)
	if FLAG == 0 or not flags or not band or band(flags, FLAG) == 0 then
		return into
	end
	local friendly = DB.Npc.friendlyToFaction(npcID)
	if friendly and friendly ~= "" and who.faction and not friendly:find(who.faction, 1, true) then
		return into -- not for the player's faction
	end
	local spawns = DB.Npc.spawns(npcID)
	if type(spawns) ~= "table" then
		return into
	end
	local areas = {}
	for areaID in pairs(spawns) do
		areas[#areas + 1] = areaID
	end
	table.sort(areas) -- the same ids in every build
	for _, areaID in ipairs(areas) do
		local mapID = Adapter.MapOfArea(areaID)
		for i, point in ipairs(mapID and spawns[areaID] or {}) do
			if point[1] and point[2] and point[1] >= 0 and point[2] >= 0 then
				local map = ns.MapPlace(mapID)
				local keywords = {}
				for _, word in ipairs(who.keywords or ns.Words("SPIRIT_HEALER")) do
					keywords[#keywords + 1] = word
				end
				if map and map.name then
					keywords[#keywords + 1] = map.name:lower() -- "cementerio forjaz"
				end
				into[#into + 1] = {
					id = ("%d:%d:%d"):format(npcID, areaID, i),
					name = L.SPIRIT_HEALER,
					subtitle = map and map.name or nil,
					keywords = keywords,
					icon = Healers.ICON,
					mapID = mapID,
					x = point[1] / 100,
					y = point[2] / 100,
					npcID = npcID,
				}
			end
		end
	end
	return into
end

local provider
local building
Healers.stats = {}

local step
step = function(build)
	if build ~= building then
		return
	end
	local stop = math.min(build.index + Healers.STEP - 1, #build.ids)
	local started = debugprofilestop()
	local i = build.index
	while i <= stop do
		Healers.EntriesFor(build.ids[i], build.who, build.entries)
		i = i + 1
		if debugprofilestop() - started > Healers.BUDGET_MS then
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
	Healers.stats = { npcs = #build.ids, healers = #build.entries, ms = debugprofilestop() - build.start }
	if provider and provider:IsEnabled() then
		provider:SetEntries(build.entries)
	end
end

function Healers.Build()
	local who = Adapter.Player()
	who.keywords = ns.Words("SPIRIT_HEALER") -- read once, not per spawn
	local build = { ids = DB.Npc.GetAllIds() or {}, index = 1, entries = {}, who = who, start = debugprofilestop() }
	building = build
	C_Timer.After(0, function()
		step(build)
	end)
end

local aliases = ns.Words("SPIRIT_HEALERS")
provider = MapScoutAPI:RegisterProvider("spirithealers", {
	name = L.SPIRIT_HEALERS_NAME,
	description = L.SPIRIT_HEALERS_DESCRIPTION,
	icon = Healers.ICON,
	filter = table.remove(aliases, 1), -- the main @ word (English, singular)
	filterAliases = aliases,
	OnEnable = function()
		Healers.Build()
	end,
	OnDisable = function()
		building = nil
	end,
})

ns.RegisterDebug("spirithealers", function()
	local s = Healers.stats
	ns.Print(L.DEBUG_SPIRIT_HEALERS_RESULT:format(s.npcs or 0, s.healers or 0, s.ms or 0))
end, L.DEBUG_SPIRIT_HEALERS)
