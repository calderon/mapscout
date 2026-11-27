-- MapScout recorder: notices the moments the game tells where something is,
-- and tells whoever is listening. It stores nothing: the development harvest
-- mode (Debug/Harvest.lua), the contribution mode and learning places while
-- playing each keep what they need, in their own way.
-- Zero bloat: it listens to no event until someone starts it, and stops
-- listening when the last one stops.
--   Recorder.Start(owner, fn)   fn(kind, record, why) at every moment
--   Recorder.Stop(owner)
-- What fn gets (kind: record). Positions are the player's, on the most precise
-- map (an NPC is within a few steps of whoever talks to it), rounded to 4
-- decimals; at is time().
--   "npc": { service, id, spawn, name, faction, title, locale, map, x, y, at },
--     plus gossip (its options, service "gossip"), skill (service "trainer")
--     and repair (service "vendor"). Talking to a service NPC (bank, auction,
--     vendor, trainer, stable, flight master, guild, battlemaster, innkeeper,
--     transmogrifier, barber) or opening its gossip window
--   "object": { service, id, map, x, y, at }. Opening a mailbox or a guild bank
--   "entrance": { instance, name, kind, map, x, y, at }. Entering a dungeon or
--     raid: where the player stood just before the loading screen
--   "death": { map, x, y, continent, cx, cy, died, at }. Dying: the graveyard
--     the ghost will appear at (on its outdoor zone; cx, cy on the continent)
--   "healer": { npc, map, x, y, at }. A spirit healer talked to as a ghost
--   "direction": { map, x, y, name, texture, poi, guard, asked, locale, at }.
--     The place a city guard marks on the map when asked for a service
--     ("Profession trainer > Alchemy": the choices that led to it)
-- When an entrance or a death happened but gave no place, record is nil and
-- why says what there was: entrance { name, kind, instance, age, noPosition },
-- death { map, continent }.

local _, ns = ...

local Recorder = {}
ns.Recorder = Recorder

-- event -> service
Recorder.SERVICES = {
	BANKFRAME_OPENED = "bank",
	AUCTION_HOUSE_SHOW = "auction",
	MERCHANT_SHOW = "vendor",
	TRAINER_SHOW = "trainer",
	PET_STABLE_SHOW = "stable",
	TAXIMAP_OPENED = "flight",
	GUILD_REGISTRAR_SHOW = "guild",
	OPEN_TABARD_FRAME = "tabard",
	BATTLEFIELDS_SHOW = "battlemaster",
	CONFIRM_BINDER = "innkeeper",
	GOSSIP_SHOW = "gossip",
	-- older events, only where the client still has them
	TRANSMOGRIFY_OPEN = "transmog",
	GUILDBANKFRAME_OPENED = "guildbank",
}

-- Windows opened through the interaction manager (Enum.PlayerInteractionType
-- name -> service), for services without an event of their own
Recorder.INTERACTIONS = { Transmogrifier = "transmog", GuildBanker = "guildbank", Barber = "barber" }

-- Services that are objects, not NPCs, when the game gives no GUID
local OBJECTS = { mailbox = true, guildbank = true }

local listeners = {} -- owner -> fn
local running = false

local function tell(kind, record, why)
	for _, fn in pairs(listeners) do
		xpcall(fn, geterrorhandler(), kind, record, why)
	end
	return record
end

-- Helpers -----------------------------------------------------------------

-- Whether this client has an event (registering an unknown one is an error)
function Recorder.HasEvent(event)
	if C_EventUtils and C_EventUtils.IsEventValid then
		return C_EventUtils.IsEventValid(event) and true or false
	end
	return true
end

-- The kind, ID and spawn in a GUID ("Creature-0-1-2-3-1234-0000" ->
-- "Creature", 1234, "0000"). The spawn tells apart NPCs that share an ID.
function Recorder.ParseGUID(guid)
	if type(guid) ~= "string" then
		return nil
	end
	local kind, _, _, _, _, id, spawn = strsplit("-", guid)
	return kind, tonumber(id), spawn
end

function Recorder.Round(value)
	return math.floor(value * 10000 + 0.5) / 10000
end
local round = Recorder.Round

-- Where the player is: uiMapID, x, y (0..1), or nil
function Recorder.Where()
	local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not position then
		return nil
	end
	local x, y = position:GetXY()
	if not x or (x == 0 and y == 0) then
		return nil
	end
	return mapID, x, y
end

-- A key for one place on a map, about 1/1000 of the map wide
-- ("mailbox:1455:356:604"; without a prefix, "1455:356:604")
function Recorder.PlaceKey(prefix, mapID, x, y)
	local key = ("%d:%d:%d"):format(mapID, math.floor(x * 1000), math.floor(y * 1000))
	return prefix and (prefix .. ":" .. key) or key
end

-- The continent a map is in, or nil (an instance has none)
function Recorder.ContinentOf(mapID)
	local id, seen = mapID, 0
	while id and id ~= 0 and seen < 10 do
		local info = C_Map.GetMapInfo(id)
		if not info then
			return nil
		end
		if info.mapType == 2 then
			return id
		end
		id, seen = info.parentMapID, seen + 1
	end
	return nil
end

-- Gossip options (icon:name), to tell services apart later
local function gossipOptions()
	local list = {}
	if C_GossipInfo and C_GossipInfo.GetOptions then
		for _, option in ipairs(C_GossipInfo.GetOptions() or {}) do
			list[#list + 1] = tostring(option.icon) .. ":" .. tostring(option.name)
		end
	end
	return list
end

-- The line under a unit's name in its tooltip ("Intendente de Forjaz",
-- or its level when it has no title), or nil
local scanner
function Recorder.UnitTitle(unit)
	if C_TooltipInfo and C_TooltipInfo.GetUnit then
		local info = C_TooltipInfo.GetUnit(unit)
		local line = info and info.lines and info.lines[2]
		return line and line.leftText or nil
	end
	if not CreateFrame then
		return nil
	end
	scanner = scanner or CreateFrame("GameTooltip", "MapScoutRecorderTooltip", nil, "GameTooltipTemplate")
	scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
	scanner:SetUnit(unit)
	local line = _G.MapScoutRecorderTooltipTextLeft2
	local text = line and line:GetText()
	scanner:Hide()
	return text
end

-- The skill a trainer's window teaches ("Riding", "Mining"), or nil: tells
-- riding and profession trainers apart (a class trainer teaches its schools)
function Recorder.TrainerSkill()
	if not (GetNumTrainerServices and GetTrainerServiceSkillLine) then
		return nil
	end
	for i = 1, GetNumTrainerServices() or 0 do
		local skill = GetTrainerServiceSkillLine(i)
		if skill and skill ~= "" then
			return skill
		end
	end
	return nil
end

-- Keeping NPCs (pure, for whoever stores them) ----------------------------

Recorder.SIGHTINGS = 10 -- most places kept per NPC
Recorder.SAME_SPOT = 0.002 -- closer places on one map are the same (map units)

-- Keeps where an NPC was talked to ({ map, x, y, spawn } in record.seen), so
-- one who walks a route (seen far apart) can be told from one who stands
-- still. spawn tells apart NPCs that share an ID (every Ironforge mountaineer
-- is 727): only places of one spawn are compared. The same spot of the same
-- spawn again is not added.
function Recorder.AddSighting(record, mapID, x, y, spawn)
	local seen = record.seen or {}
	record.seen = seen
	for _, spot in ipairs(seen) do
		if spot[1] == mapID and spot[4] == spawn and math.abs(spot[2] - x) < Recorder.SAME_SPOT
			and math.abs(spot[3] - y) < Recorder.SAME_SPOT then
			return
		end
	end
	if #seen < Recorder.SIGHTINGS then
		seen[#seen + 1] = { mapID, x, y, spawn }
	end
end

-- Adds an "npc" record to npcs (npc ID -> what is known of it): its services
-- add up, its last place and sightings are kept, and what a window did not say
-- (title, skill) keeps what was known. Returns the NPC's entry.
function Recorder.AddNPC(npcs, npc)
	local entry = npcs[npc.id] or { id = npc.id, services = {} }
	npcs[npc.id] = entry
	entry.name, entry.faction, entry.locale = npc.name, npc.faction, npc.locale
	entry.title = npc.title or entry.title
	entry.map, entry.x, entry.y, entry.at = npc.map, npc.x, npc.y, npc.at
	Recorder.AddSighting(entry, npc.map, npc.x, npc.y, npc.spawn)
	if npc.service == "gossip" then
		entry.gossip = npc.gossip
	elseif npc.service == "trainer" then
		entry.services.trainer = true
		entry.skill = npc.skill or entry.skill
	else
		entry.services[npc.service] = true
		if npc.repair then
			entry.services.repair = true
		end
	end
	return entry
end

-- Adds a "direction" record to directions (place key -> record). Several
-- guards, or several questions, giving one place are one record, with every
-- question asked ("Bank | Mailbox"). Returns it, or nil when that question was
-- already there (the second look after the same choice).
function Recorder.AddDirection(directions, direction)
	local key = Recorder.PlaceKey(nil, direction.map, direction.x, direction.y)
	local asked = direction.asked or ""
	local old = directions[key]
	local list = {}
	for part in ((old and old.asked) or ""):gmatch("[^|]+") do
		part = strtrim(part)
		if part == asked and asked ~= "" then
			return nil
		end
		if part ~= "" then
			list[#list + 1] = part
		end
	end
	list[#list + 1] = asked
	table.sort(list)
	local record = {}
	for field, value in pairs(direction) do
		record[field] = value
	end
	record.asked = table.concat(list, " | ")
	directions[key] = record
	return record, key
end

-- Moments -----------------------------------------------------------------

function Recorder.RecordNPC(service, unit)
	unit = unit or "npc"
	local kind, id, spawn = Recorder.ParseGUID(UnitGUID(unit))
	local mapID, x, y = Recorder.Where()
	if not mapID then
		return nil
	end
	if kind == "GameObject" or (not kind and OBJECTS[service]) then
		return tell("object", { service = service, id = id, map = mapID, x = round(x), y = round(y), at = time() })
	end
	if kind ~= "Creature" or not id then
		return nil
	end
	local record = {
		service = service, id = id, spawn = spawn, name = UnitName(unit),
		faction = UnitFactionGroup(unit) or "Neutral", title = Recorder.UnitTitle(unit), locale = GetLocale(),
		map = mapID, x = round(x), y = round(y), at = time(),
	}
	if service == "gossip" then
		record.gossip = gossipOptions()
	elseif service == "trainer" then
		record.skill = Recorder.TrainerSkill()
	elseif service == "vendor" then
		record.repair = CanMerchantRepair and CanMerchantRepair() and true or nil
	end
	return tell("npc", record)
end

-- A window opened through the interaction manager
function Recorder.OnInteraction(interaction)
	local names = Enum and Enum.PlayerInteractionType
	for name, value in pairs(names or {}) do
		if value == interaction and Recorder.INTERACTIONS[name] then
			return Recorder.RecordNPC(Recorder.INTERACTIONS[name])
		end
	end
	return nil
end

-- Graveyards. On dying, the game says where the ghost will appear
-- (C_DeathInfo.GetDeathReleasePosition), but only on the continent's map: on a
-- city's map the graveyard outside it is off the map. The point is then placed
-- on its outdoor zone. It answers nothing while alive. As a ghost, the only NPC
-- one can talk to is a spirit healer: its gossip window says where it stands.

local function onMap(x, y)
	return x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 and not (x == 0 and y == 0)
end

function Recorder.RecordDeath()
	local death = C_DeathInfo
	local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local continent = mapID and Recorder.ContinentOf(mapID)
	local at = continent and death and death.GetDeathReleasePosition and death.GetDeathReleasePosition(continent)
	local cx, cy
	if at then
		cx, cy = at:GetXY()
	end
	if not onMap(cx, cy) then
		return tell("death", nil, { map = mapID, continent = continent })
	end
	local zone, x, y = ns.PlaceOutdoors(continent, cx, cy)
	return tell("death", {
		map = zone, x = round(x), y = round(y), continent = continent, cx = round(cx), cy = round(cy),
		died = mapID, at = time(),
	})
end

function Recorder.RecordHealer()
	local mapID, x, y = Recorder.Where()
	if not mapID then
		return nil
	end
	local _, npcID = Recorder.ParseGUID(UnitGUID("npc"))
	return tell("healer", { npc = npcID, map = mapID, x = round(x), y = round(y), at = time() })
end

-- Entrances: the last place outside, paired with the instance entered next.
-- While outside, the place is noted every second (Forever may not show a real
-- loading screen); entering is noticed after a loading screen or a zone change.
Recorder.TRACK_EVERY = 1
Recorder.MAX_AGE = 3 -- seconds between the last place outside and leaving the world
local outside, ticker, lastInstance, noPosition

function Recorder.NoteOutside()
	if IsInInstance() then
		return
	end
	lastInstance = nil
	local mapID, x, y = Recorder.Where()
	noPosition = not mapID
	if mapID then
		outside = { map = mapID, x = round(x), y = round(y), at = GetTime() }
	end
end

-- Just before a loading screen: the age of the place outside counts until now
-- (a loading screen can take several seconds)
function Recorder.LeavingWorld()
	Recorder.NoteOutside()
	if outside and not outside.left then
		outside.left = GetTime()
	end
end

function Recorder.EnteringWorld()
	local inside, kind = IsInInstance()
	if not inside then
		Recorder.NoteOutside()
		return nil
	end
	local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	if lastInstance and lastInstance == instanceID then
		return nil -- still the same instance (a zone change inside it)
	end
	lastInstance = instanceID
	local from = outside
	outside = nil
	local age = from and ((from.left or GetTime()) - from.at)
	if age and age > Recorder.MAX_AGE then
		from = nil
	end
	if not (from and instanceID and (kind == "party" or kind == "raid" or kind == "scenario")) then
		return tell("entrance", nil, {
			name = name, kind = kind, instance = instanceID, place = from and true or nil,
			age = not from and age or nil, noPosition = noPosition or nil,
		})
	end
	return tell("entrance", { instance = instanceID, name = name, kind = kind, map = from.map, x = from.x, y = from.y,
		at = time() })
end

-- Directions: a city guard asked for a service ("The bank") marks it on the
-- map with a gossip POI. After each gossip choice, the POI is looked for on the
-- player's map and the maps above it, with the choices that led to it
-- ("Profession trainer > Alchemy").
Recorder.POI_DELAYS = { 0.3, 1 } -- seconds after a choice: the POI may come late
local choices = {} -- the options chosen with the current guard, in order

-- The options of the gossip window shown last, by option ID and by position:
-- read when the window opens, because after a choice it already shows the next
-- page's options
local shown = { byID = {}, byIndex = {} }

local function noteOptions()
	shown = { byID = {}, byIndex = {} }
	for i, option in ipairs(C_GossipInfo.GetOptions() or {}) do
		if option.gossipOptionID then
			shown.byID[option.gossipOptionID] = option.name
		end
		shown.byIndex[option.orderIndex or (i - 1)] = option.name
		shown.byIndex[i] = shown.byIndex[i] or option.name
	end
end

-- Whether this client can tell where a guard's answer is
function Recorder.CanAskGuards()
	return C_GossipInfo and C_GossipInfo.GetPoiForUiMapID and C_GossipInfo.GetPoiInfo and true or false
end

-- The gossip POI shown now: uiMapID, x, y, name, texture index, POI ID; or nil
function Recorder.FindPoi()
	local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	while mapID and mapID > 0 do
		local poiID = C_GossipInfo.GetPoiForUiMapID(mapID)
		local info = poiID and C_GossipInfo.GetPoiInfo(mapID, poiID)
		if info and info.position then
			local x, y = info.position:GetXY()
			return mapID, x, y, info.name, info.textureIndex, poiID
		end
		local map = C_Map.GetMapInfo(mapID)
		mapID = map and map.parentMapID
	end
	return nil
end

-- Only a final answer counts: while the window still has options, the choice
-- opened a submenu (or the answer has not come yet) and the POI shown is still
-- the previous one's. Forever gives every POI the ID 0, so it cannot tell them
-- apart. It is looked for twice after a choice: the same answer comes twice.
function Recorder.RecordPoi(asked)
	if #(C_GossipInfo.GetOptions() or {}) > 0 then
		return nil
	end
	local mapID, x, y, name, texture, poiID = Recorder.FindPoi()
	if not mapID then
		return nil
	end
	local kind, guard = Recorder.ParseGUID(UnitGUID("npc"))
	return tell("direction", {
		map = mapID, x = round(x), y = round(y), name = name, texture = texture, poi = poiID, locale = GetLocale(),
		asked = asked or "", guard = kind == "Creature" and guard or nil, at = time(),
	})
end

local function onChoice(name)
	if not running then
		return
	end
	choices[#choices + 1] = name
	local asked = table.concat(choices, " > ")
	for _, delay in ipairs(Recorder.POI_DELAYS) do
		C_Timer.After(delay, function()
			if running then
				Recorder.RecordPoi(asked)
			end
		end)
	end
end

-- A hook cannot be taken back: once hooked, it does nothing while stopped
local hooked
local function hookGossip()
	if hooked or not Recorder.CanAskGuards() then
		return
	end
	hooked = true
	if C_GossipInfo.SelectOption then
		hooksecurefunc(C_GossipInfo, "SelectOption", function(optionID)
			onChoice(shown.byID[optionID] or ("id " .. tostring(optionID)))
		end)
	end
	if C_GossipInfo.SelectOptionByIndex then
		hooksecurefunc(C_GossipInfo, "SelectOptionByIndex", function(index)
			onChoice(shown.byIndex[index] or ("index " .. tostring(index)))
		end)
	end
end

-- Listening ---------------------------------------------------------------

local function onService(event)
	if event == "GOSSIP_SHOW" and hooked then
		noteOptions()
	end
	if event == "GOSSIP_SHOW" and UnitIsGhost("player") then
		Recorder.RecordHealer() -- a ghost only talks to spirit healers: not a service
		return
	end
	Recorder.RecordNPC(Recorder.SERVICES[event])
end

local OTHERS = {
	MAIL_SHOW = function() Recorder.RecordNPC("mailbox") end,
	PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function(_, interaction) Recorder.OnInteraction(interaction) end,
	PLAYER_LEAVING_WORLD = function() Recorder.LeavingWorld() end,
	PLAYER_ENTERING_WORLD = function() Recorder.EnteringWorld() end,
	ZONE_CHANGED_NEW_AREA = function() Recorder.EnteringWorld() end,
	PLAYER_DEAD = function() Recorder.RecordDeath() end,
	GOSSIP_CLOSED = function() choices = {} end,
}

local function listen(on)
	running = on
	for event in pairs(Recorder.SERVICES) do
		if on and Recorder.HasEvent(event) then
			ns.RegisterEvent(event, "Recorder", onService)
		else
			ns.UnregisterEvent(event, "Recorder")
		end
	end
	for event, fn in pairs(OTHERS) do
		if on and Recorder.HasEvent(event) then
			ns.RegisterEvent(event, "Recorder", fn)
		else
			ns.UnregisterEvent(event, "Recorder")
		end
	end
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	choices = {}
	if on then
		hookGossip()
		Recorder.NoteOutside()
		ticker = C_Timer.NewTicker(Recorder.TRACK_EVERY, Recorder.NoteOutside)
	end
end

function Recorder.Start(owner, fn)
	assert(owner ~= nil, "owner is required")
	assert(type(fn) == "function", "fn must be a function")
	listeners[owner] = fn
	if not running then
		listen(true)
	end
end

function Recorder.Stop(owner)
	listeners[owner] = nil
	if running and next(listeners) == nil then
		listen(false)
	end
end

function Recorder.IsRunning()
	return running
end
