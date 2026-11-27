-- MapScout adapter: available quests from QuestieDB.
-- QuestieDB is the database addon by the Questie team (GPLv3, separate from
-- Questie, supports Forever). Its data is read at runtime through its public
-- API (LibQuestieDB, contract 4); nothing is copied into MapScout.
-- Without QuestieDB (or with an incompatible one) this file does nothing.
--
-- Available quests are the ones the character can take now: not done, not in
-- the log, level, race and class allowed, prerequisites done, no exclusive
-- quest done (profession quests are left out for now). Like Questie, hidden
-- by default, each with its own setting in the options: quests far above the
-- player's level, gray (trivial) ones, seasonal ones (and even when shown,
-- only while their holiday is on, if the game's calendar says so) and
-- repeatable ones. Quests without a level are always left out:
-- QuestieDB hardly knows them. Each one is placed
-- where its giver stands (an NPC friendly to the player, or an object).
-- QuestieDB groups positions by area (AreaID); they are matched to world map
-- zones by name. Its Forever positions are used as they come (as Questie does).
-- A giver who walks a route (QuestieDB has its waypoints) carries it: the map
-- draws the route instead of one exact point.
-- Built in small steps so the game never freezes, and rebuilt after a pause
-- when the quest log or the level changes, while the map is open or when it opens.

local _, ns = ...
local L = ns.L

local QuestieAdapter = {}
ns.QuestieAdapter = QuestieAdapter

QuestieAdapter.CONTRACT = 4
QuestieAdapter.STEP = 200 -- most quests checked per frame while building
QuestieAdapter.BUDGET_MS = 8 -- and at most this long per frame
QuestieAdapter.THROTTLE = 1 -- seconds after a change before rebuilding
QuestieAdapter.ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
QuestieAdapter.HIGH_LEVEL_GAP = 10 -- more levels above the player than this: hidden
QuestieAdapter.TRIVIAL_GAP = 8 -- gray quests, when the game doesn't say its own range
QuestieAdapter.REPEATABLE_FLAG = 1 -- QuestieDB's special flag for repeatable quests

-- QuestieDB's sorts (zoneOrSort) of holiday quests -> holiday. SEASONAL is a
-- holiday quest of no known holiday: never shown.
QuestieAdapter.HOLIDAY_SORTS = {
	[-22] = "SEASONAL",
	[-21] = "HALLOWS_END",
	[-41] = "DAY_OF_THE_DEAD",
	[-364] = "DARKMOON_FAIRE",
	[-366] = "LUNAR_FESTIVAL",
	[-369] = "MIDSUMMER",
	[-370] = "BREWFEST",
	[-374] = "NOBLEGARDEN",
	[-375] = "PILGRIMS_BOUNTY",
	[-376] = "LOVE_IS_IN_THE_AIR",
	[-378] = "CHILDRENS_WEEK",
	[-402] = "HARVEST_FESTIVAL",
	[-404] = "WINTER_VEIL",
}

-- The settings of the options (all off by default, as in Questie)
QuestieAdapter.SETTINGS = { "highLevel", "lowLevel", "seasonal", "repeatable" }

local DB = rawget(_G, "LibQuestieDB")
if not (DB and DB.RequireContract and DB.RequireContract(QuestieAdapter.CONTRACT) and DB.Quest and DB.Npc) then
	return -- no QuestieDB, or one we don't know how to read
end
QuestieAdapter.db = DB

local band = bit and bit.band

-- Area (AreaID) -> world map zone, matched by name, cached
local areaMaps = {}
QuestieAdapter.unmatchedAreas = {} -- areaID -> times asked, for /ms debug questie areas
function QuestieAdapter.MapOfArea(areaID)
	local cached = areaMaps[areaID]
	if cached ~= nil then
		return cached or nil
	end
	local name = C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID)
	local mapID, mapName = ns.FindMapByName(name)
	if not (mapID and ns.Normalize(mapName) == ns.Normalize(name)) then
		areaMaps[areaID] = false
		QuestieAdapter.unmatchedAreas[areaID] = true
		return nil
	end
	areaMaps[areaID] = mapID
	return mapID
end

-- The first position of a spawn list ({ [areaID] = { {x, y}, ... } }) on a
-- known map: lowest AreaID first, so the result doesn't change between builds
function QuestieAdapter.FirstSpawn(spawns)
	if type(spawns) ~= "table" then
		return nil
	end
	local areas = {}
	for areaID in pairs(spawns) do
		areas[#areas + 1] = areaID
	end
	table.sort(areas)
	for _, areaID in ipairs(areas) do
		local mapID = QuestieAdapter.MapOfArea(areaID)
		local point = mapID and spawns[areaID][1]
		if point and point[1] and point[1] >= 0 and point[2] >= 0 then
			return mapID, point[1] / 100, point[2] / 100
		end
	end
	return nil
end

-- The route an NPC walks, as result entries carry it ({ { mapID, points =
-- { x1, y1, ... } }, ... }), or nil when it stands still. QuestieDB groups its
-- paths ({ [areaID] = { { {x, y}, ... }, ... } }, 0-100) by area; paths on an
-- area with no map, and points off the map (negative), are left out.
function QuestieAdapter.Route(npcID)
	local paths = DB.Npc.waypoints and DB.Npc.waypoints(npcID)
	if type(paths) ~= "table" then
		return nil
	end
	local areas = {}
	for areaID in pairs(paths) do
		areas[#areas + 1] = areaID
	end
	table.sort(areas) -- the same order on every build
	local route = {}
	for _, areaID in ipairs(areas) do
		local mapID = QuestieAdapter.MapOfArea(areaID)
		for _, path in ipairs(mapID and type(paths[areaID]) == "table" and paths[areaID] or {}) do
			local points = {}
			for _, point in ipairs(type(path) == "table" and path or {}) do
				local x, y = point[1], point[2]
				if type(x) == "number" and type(y) == "number" and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
					points[#points + 1] = x / 100
					points[#points + 1] = y / 100
				end
			end
			if #points >= 4 then
				route[#route + 1] = { mapID = mapID, points = points }
			end
		end
	end
	return #route > 0 and route or nil
end

-- What the options say to show: setting -> true/false
function QuestieAdapter.Shown()
	local show = {}
	for _, id in ipairs(QuestieAdapter.SETTINGS) do
		show[id] = ns.Registry.GetSetting("questiedb", id) == true
	end
	return show
end

-- The game's calendar holidays (Holidays table of the Forever client) -> QuestieDB's
-- holiday. Forever has no Brewfest, Pilgrim's Bounty nor Day of the Dead.
QuestieAdapter.CALENDAR_HOLIDAYS = {
	[141] = "WINTER_VEIL",
	[181] = "NOBLEGARDEN",
	[201] = "CHILDRENS_WEEK",
	[263] = "DARKMOON_FAIRE",
	[264] = "DARKMOON_FAIRE",
	[321] = "HARVEST_FESTIVAL",
	[324] = "HALLOWS_END",
	[327] = "LUNAR_FESTIVAL",
	[335] = "LOVE_IS_IN_THE_AIR",
	[341] = "MIDSUMMER",
}

local function minutes(t)
	return (t.hour or 0) * 60 + (t.minute or 0)
end

-- Is a calendar event of today on at this time? (now: the game's calendar time)
-- It starts at its start time on its first day and ends at its end time on its last.
function QuestieAdapter.EventIsOn(event, now)
	local sequence = event.sequenceType
	if sequence == "START" and event.startTime then
		return minutes(now) >= minutes(event.startTime)
	elseif sequence == "END" and event.endTime then
		return minutes(now) < minutes(event.endTime)
	end
	return true -- "ONGOING", or a one-day event
end

-- Holidays on now, from the game's calendar: holiday -> true.
-- Without a calendar (or before it has loaded), none: seasonal quests stay hidden.
-- The calendar's shown month is not changed (the player may have it open):
-- today is found by its distance to that month.
local calendarAsked = false
function QuestieAdapter.ActiveHolidays()
	local on = {}
	local now = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
	if not (now and C_Calendar and C_Calendar.GetMonthInfo and C_Calendar.GetNumDayEvents) then
		return on
	end
	if not calendarAsked and C_Calendar.OpenCalendar then
		calendarAsked = true -- loaded in the background: build again when it is
		ns.RegisterEvent("CALENDAR_UPDATE_EVENT_LIST", "QuestieAdapterCalendar", function()
			ns.UnregisterEvent("CALENDAR_UPDATE_EVENT_LIST", "QuestieAdapterCalendar")
			QuestieAdapter.Changed()
		end)
		C_Calendar.OpenCalendar()
	end
	local shown = C_Calendar.GetMonthInfo(0)
	if not shown then
		return on
	end
	local offset = (now.year - shown.year) * 12 + now.month - shown.month
	for i = 1, C_Calendar.GetNumDayEvents(offset, now.monthDay) or 0 do
		local event = C_Calendar.GetDayEvent(offset, now.monthDay, i)
		local holiday = event and event.calendarType == "HOLIDAY" and QuestieAdapter.CALENDAR_HOLIDAYS[event.eventID]
		if holiday and QuestieAdapter.EventIsOn(event, now) then
			on[holiday] = true
		end
	end
	return on
end

-- Who the player is, for the availability checks
function QuestieAdapter.Player()
	local _, _, raceID = UnitRace("player")
	local _, _, classID = UnitClass("player")
	local faction = UnitFactionGroup("player")
	local trivial = UnitQuestTrivialLevelRange and UnitQuestTrivialLevelRange("player")
	local show = QuestieAdapter.Shown()
	return {
		level = UnitLevel("player") or 1,
		trivialGap = trivial or QuestieAdapter.TRIVIAL_GAP,
		raceMask = DB.Enum and DB.Enum.raceMaskById and DB.Enum.raceMaskById[raceID] or 0,
		classMask = classID and 2 ^ (classID - 1) or 0,
		faction = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil,
		show = show,
		holidays = show.seasonal and QuestieAdapter.ActiveHolidays() or {},
	}
end

local function done(questID)
	return C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(questID) == true
end

local function allDone(list)
	for _, questID in ipairs(list or {}) do
		if not done(questID) then
			return false
		end
	end
	return true
end

local function anyDone(list)
	for _, questID in ipairs(list or {}) do
		if done(questID) then
			return true
		end
	end
	return false
end

local function allowed(mask, playerMask)
	return not mask or mask == 0 or not band or band(mask, playerMask) ~= 0
end

-- Can the character take this quest now?
function QuestieAdapter.IsAvailable(questID, who, inLog)
	local Q = DB.Quest
	if inLog[questID] or done(questID) then
		return false
	end
	local show = who.show or {}
	if not show.highLevel and (Q.requiredLevel(questID) or 0) > who.level then
		return false -- not yet: shown only with the high-level setting
	end
	local holiday = QuestieAdapter.HOLIDAY_SORTS[Q.zoneOrSort(questID)]
	if holiday and (holiday == "SEASONAL" or not (show.seasonal and who.holidays and who.holidays[holiday])) then
		return false -- holiday quests: only while their holiday is on
	end
	local special = Q.specialFlags(questID)
	if not show.repeatable and special and band and band(special, QuestieAdapter.REPEATABLE_FLAG) ~= 0 then
		return false -- repeatable turn-ins (war effort, reputation...)
	end
	local questLevel = Q.questLevel(questID)
	if not questLevel or questLevel <= 0 then
		return false -- no level: QuestieDB hardly knows it (system quests, missing data)
	end
	if not show.highLevel and questLevel > who.level + QuestieAdapter.HIGH_LEVEL_GAP then
		return false -- far above the player
	end
	if not show.lowLevel and who.level - questLevel > who.trivialGap then
		return false -- gray: too low to be worth it
	end
	local maxLevel = Q.requiredMaxLevel(questID)
	if maxLevel and maxLevel > 0 and who.level > maxLevel then
		return false
	end
	if not allowed(Q.requiredRaces(questID), who.raceMask) or not allowed(Q.requiredClasses(questID), who.classMask) then
		return false
	end
	if Q.requiredSkill(questID) then
		return false -- profession quests: not handled yet
	end
	local single = Q.preQuestSingle(questID)
	if not allDone(Q.preQuestGroup(questID)) or (single and #single > 0 and not anyDone(single)) then
		return false
	end
	if anyDone(Q.exclusiveTo(questID)) then
		return false
	end
	return true
end

-- True when the NPC also finishes the quest
local function finishes(questID, npcID)
	local finishers = DB.Quest.finishedBy and DB.Quest.finishedBy(questID)
	for _, id in ipairs(finishers and finishers[1] or {}) do
		if id == npcID then
			return true
		end
	end
	return false
end

local function friendlyNpc(npcID, who)
	local friendly = DB.Npc.friendlyToFaction(npcID)
	return not friendly or not who.faction or friendly:find(who.faction, 1, true)
end

local function objectAt(objectIDs)
	if not DB.Object then
		return nil
	end
	for _, objectID in ipairs(objectIDs) do
		local mapID, x, y = QuestieAdapter.FirstSpawn(DB.Object.spawns(objectID))
		if mapID then
			return DB.Object.name(objectID), mapID, x, y
		end
	end
	return nil
end

-- Where the quest is taken: the first giver NPC friendly to the player, or an
-- object. A quest that starts at an object and at an NPC who also finishes it
-- (a book to bring to someone) is placed at the object: the NPC is where it is
-- handed in, and is returned as the fifth value.
function QuestieAdapter.Giver(questID, who)
	local starters = DB.Quest.startedBy(questID) or {}
	local npcs, objects = starters[1] or {}, starters[2] or {}
	if #objects > 0 then
		for _, npcID in ipairs(npcs) do
			if friendlyNpc(npcID, who) and finishes(questID, npcID) then
				local name, mapID, x, y = objectAt(objects)
				if mapID then
					return name, mapID, x, y, DB.Npc.name(npcID)
				end
				break
			end
		end
	end
	for _, npcID in ipairs(npcs) do
		if friendlyNpc(npcID, who) then
			local mapID, x, y = QuestieAdapter.FirstSpawn(DB.Npc.spawns(npcID))
			if mapID then
				return DB.Npc.name(npcID), mapID, x, y, nil, npcID
			end
		end
	end
	return objectAt(objects)
end

local function questsInLog()
	local inLog = {}
	if C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(i)
			if info and info.questID then
				inLog[info.questID] = true
			end
		end
	end
	return inLog
end

-- The quest's title in the player's language: the game's own when it knows the
-- quest (cached), QuestieDB's otherwise (which may be in English)
function QuestieAdapter.Title(questID)
	local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
	if type(title) == "string" and title ~= "" then
		return title
	end
	return DB.Quest.name(questID) or ("#" .. questID)
end

local function entryFor(questID, who)
	local Q = DB.Quest
	local giver, mapID, x, y, handIn, giverID = QuestieAdapter.Giver(questID, who)
	if not mapID then
		return nil
	end
	local route = giverID and QuestieAdapter.Route(giverID) -- a giver who walks a route
	local level = Q.questLevel(questID) or Q.requiredLevel(questID) or 0
	local details = {}
	for _, line in ipairs(Q.objectivesText(questID) or {}) do
		details[#details + 1] = line
	end
	if handIn then
		details[#details + 1] = L.AVAILABLE_STARTS_AT:format(giver or "?")
		details[#details + 1] = L.AVAILABLE_HAND_IN:format(handIn)
	else
		details[#details + 1] = L.AVAILABLE_GIVER:format(giver or "?")
	end
	local required = Q.requiredLevel(questID) or 0
	if required > who.level then
		details[#details + 1] = L.AVAILABLE_REQUIRES:format(required)
	end
	local keywords = ns.Words("AVAILABLE")
	keywords[#keywords + 1] = giver
	keywords[#keywords + 1] = handIn
	return {
		id = questID,
		name = QuestieAdapter.Title(questID),
		subtitle = L.AVAILABLE_SUBTITLE:format(level, giver or "?"),
		keywords = keywords,
		details = details,
		icon = QuestieAdapter.ICON,
		category = handIn and "books" or nil, -- the rest have no category: always shown
		mapID = mapID,
		x = x,
		y = y,
		roams = route and true or nil,
		route = route,
		questID = questID,
	}
end

-- Building in steps ------------------------------------------------------------------

local provider
local building -- the build in progress, or nil
local outOfDate, timer = false, nil

QuestieAdapter.stats = {}

-- Checks the next STEP quests of a build; publishes the entries when all are
-- done. A build replaced by a newer one stops at its next step.
local step
step = function(build)
	if build ~= building then
		return
	end
	local stop = math.min(build.index + QuestieAdapter.STEP - 1, #build.ids)
	local started = debugprofilestop()
	local i = build.index
	while i <= stop do
		local questID = build.ids[i]
		if QuestieAdapter.IsAvailable(questID, build.who, build.inLog) then
			local entry = entryFor(questID, build.who)
			if entry then
				build.entries[#build.entries + 1] = entry
			else
				build.unplaced = build.unplaced + 1
			end
		end
		i = i + 1
		if debugprofilestop() - started > QuestieAdapter.BUDGET_MS then
			break -- the rest on the next frame
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
	QuestieAdapter.stats = {
		quests = #build.ids, available = #build.entries, unplaced = build.unplaced,
		ms = debugprofilestop() - build.start,
	}
	if provider and provider:IsEnabled() then
		provider:SetEntries(build.entries)
	end
end

function QuestieAdapter.Build()
	if timer then
		timer:Cancel()
		timer = nil
	end
	outOfDate = false
	local build = {
		ids = DB.Quest.GetAllIds() or {}, index = 1, entries = {}, unplaced = 0,
		who = QuestieAdapter.Player(), inLog = questsInLog(), start = debugprofilestop(),
	}
	building = build
	C_Timer.After(0, function()
		step(build)
	end)
end

-- Something changed (a quest taken or turned in, a new level)
local function changed()
	if not ns.Map.IsShown() then
		outOfDate = true
		return
	end
	if not timer then
		timer = C_Timer.NewTimer(QuestieAdapter.THROTTLE, QuestieAdapter.Build)
	end
end
QuestieAdapter.Changed = changed

local EVENTS = { "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_LEVEL_UP" }

local following = false
local function followMap()
	if following then
		return
	end
	following = true
	ns.Map.Listen(function(what)
		if what == "shown" and outOfDate then
			QuestieAdapter.Build()
		end
	end)
end

local aliases = ns.Words("AVAILABLE")
for _, word in ipairs(ns.Words("QUESTS")) do
	aliases[#aliases + 1] = word -- found with @mision / @quest too
end
aliases[#aliases + 1] = "quest"

provider = MapScoutAPI:RegisterProvider("questiedb", {
	name = L.AVAILABLE_NAME,
	description = L.AVAILABLE_DESCRIPTION,
	icon = QuestieAdapter.ICON,
	group = "quests",
	groupName = L.GROUP_QUESTS,
	filter = "available",
	filterAliases = aliases,
	-- Book quests (started at a book, handed in to an NPC): found on their own with @book
	categories = {
		{ id = "books", name = L.AVAILABLE_BOOKS, filter = "book", filterAliases = ns.Words("BOOKS") },
	},
	OnEnable = function()
		followMap()
		QuestieAdapter.Build()
		for _, event in ipairs(EVENTS) do
			ns.RegisterEvent(event, "QuestieAdapter", changed)
		end
	end,
	OnDisable = function()
		building = nil
		for _, event in ipairs(EVENTS) do
			ns.UnregisterEvent(event, "QuestieAdapter")
		end
		if timer then
			timer:Cancel()
			timer = nil
		end
	end,
})

local settings = {}
for _, id in ipairs(QuestieAdapter.SETTINGS) do
	local key = "AVAILABLE_SHOW_" .. id:upper()
	settings[#settings + 1] = { id = id, name = L[key], tooltip = L[key .. "_TIP"], default = false }
end
ns.Registry.AddSettings("questiedb", settings)

-- A setting changed in the options (or all restored): build again
ns.Registry.Listen(function(what, id)
	if what == "setting" and id == "questiedb" and provider:IsEnabled() then
		QuestieAdapter.Build()
	end
end)

-- /ms debug questie areas: zones that couldn't be matched to a map
local function debugAreas()
	local list = {}
	for areaID in pairs(QuestieAdapter.unmatchedAreas) do
		list[#list + 1] = areaID
	end
	table.sort(list)
	ns.Print(("%d areas without a map:"):format(#list))
	local parts = {}
	for i = 1, math.min(40, #list) do
		parts[#parts + 1] = ("%d %s"):format(list[i], tostring(C_Map.GetAreaInfo(list[i])))
	end
	DEFAULT_CHAT_FRAME:AddMessage("  " .. table.concat(parts, " · "))
end

-- /ms debug questie quest <name>: QuestieDB's fields of the quests with that name
local function debugQuest(name)
	local Q = DB.Quest
	local ids = Q.IdsByName and Q.IdsByName(name) or {}
	ns.Print(("%d quests named \"%s\""):format(#ids, name))
	for _, id in ipairs(ids) do
		local starters = Q.startedBy(id) or {}
		DEFAULT_CHAT_FRAME:AddMessage(("  %d: level %s req %s, sort %s, flags %s/%s, races %s, classes %s, givers %s"):format(
			id, tostring(Q.questLevel(id)), tostring(Q.requiredLevel(id)), tostring(Q.zoneOrSort(id)),
			tostring(Q.questFlags(id)), tostring(Q.specialFlags(id)), tostring(Q.requiredRaces(id)),
			tostring(Q.requiredClasses(id)), table.concat(starters[1] or {}, ",")))
	end
end

ns.RegisterDebug("questie", function(args)
	if args == "areas" then
		debugAreas()
		return
	end
	local name = args and args:match("^quest%s+(.+)$")
	if name then
		debugQuest(name)
		return
	end
	local s = QuestieAdapter.stats
	ns.Print(L.DEBUG_QUESTIE_RESULT:format(DB.contractVersion or 0, s.quests or 0, s.available or 0, s.unplaced or 0,
		s.ms or 0))
end, L.DEBUG_QUESTIE)
