-- MapScout adapter: spirit healers (the angel at a graveyard) from QuestieDB.
-- A stopgap until our own data (harvested in the game) covers the world:
-- QuestieDB's NPCs with the SPIRIT_HEALER flag, read at runtime (nothing
-- copied), handed to MapScout's Spirit healers (Providers/SpiritHealers.lua,
-- SpiritHealers.SetExtra), so one option turns both sources on and off.
-- Where our pack has a graveyard, QuestieDB's spirit healer there is left out:
-- each graveyard harvested moves to our data by itself.
-- One NPC can stand at many graveyards: one result per spawn.
-- Needs Adapters/QuestieDB.lua (loaded first): without QuestieDB it does
-- nothing. Built in small steps while Spirit healers is on.

local _, ns = ...
local L = ns.L

local Adapter = ns.QuestieAdapter
local Own = ns.SpiritHealers
if not (Own and Adapter and Adapter.db and Adapter.db.Npc and Adapter.db.Npc.GetAllIds) then
	return -- no QuestieDB, or one we can't read
end
local DB = Adapter.db
local FLAG = DB.Enum and DB.Enum.npcFlags and DB.Enum.npcFlags.SPIRIT_HEALER or 0
local band = bit and bit.band

local Healers = {}
ns.QuestieSpiritHealers = Healers

Healers.STEP = 400 -- most NPCs checked per frame
Healers.BUDGET_MS = 8 -- and at most this long per frame

-- The entries of one NPC (one per spawn on a known map) added to into
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
			local x, y = point[1], point[2]
			if x and y and x >= 0 and y >= 0 then
				x, y = x / 100, y / 100
				if not (who.covered and who.covered(mapID, x, y)) then
					local entry = Own.Entry(("q:%d:%d:%d"):format(npcID, areaID, i), mapID, x, y, who.keywords)
					entry.npcID = npcID
					into[#into + 1] = entry
				end
			end
		end
	end
	return into
end

local building
Healers.stats = {}

local function isOn()
	local record = ns.Registry.Get("spirithealers")
	return record ~= nil and record.enabled == true
end

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
	if isOn() then
		Own.SetExtra("questiedb", build.entries)
	end
end

function Healers.Build()
	local who = Adapter.Player()
	who.keywords = ns.Words("SPIRIT_HEALER") -- read once, not per spawn
	local data = ns.Packs.Get("spirithealers")
	if data then
		who.covered = function(mapID, x, y)
			return Own.Covers(data, mapID, x, y)
		end
	end
	local build = { ids = DB.Npc.GetAllIds() or {}, index = 1, entries = {}, who = who, start = debugprofilestop() }
	building = build
	C_Timer.After(0, function()
		step(build)
	end)
end

-- Spirit healers turned on or off: build, or let go of what was built
local pending = false
ns.Registry.Listen(function(what, id)
	if what == "toggled" and id == "spirithealers" and not pending then
		pending = true
		C_Timer.After(0, function()
			pending = false
			if isOn() then
				Healers.Build()
			else
				building = nil
				Own.SetExtra("questiedb", nil)
			end
		end)
	end
end)

ns.RegisterDebug("questiehealers", function()
	local s = Healers.stats
	ns.Print(L.DEBUG_QUESTIE_HEALERS_RESULT:format(s.npcs or 0, s.healers or 0, s.ms or 0))
end, L.DEBUG_QUESTIE_HEALERS)
